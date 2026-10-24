# Construction cache — design

**Date:** 2026-10-24
**Status:** accepted (2026-10-24); implementation record at the end
**Depends on:** the styles presentation work (`Run`, async exhibits, the adaptive patch span), merged in PR #24.

## Intent

Changing style, palette or the tile overlay re-runs the whole construction today, even though only the drawing changes. Heavy tilings cost tens of seconds (`3-8-4-6` ~87 s at one cell, `Girih Star` ~47–50 s at five), so the page is unusable for exactly the tilings where the cache matters. This design adds a shared, persistent construction cache: a build is done once per `{tiling, figure}`, reused across style/palette/tiles changes, and shared by every user of the workbench.

## Goals

- A style, palette or `tiles` change redraws from cached frames and never re-runs the construction.
- One build per `{tiling, figure}` across all users, via a single-flight lock.
- Completed builds persist across restarts and are loaded lazily from disk.
- Bounded resources: at most four entries in memory, at most 1 GB on disk, oldest-first eviction.

## Non-goals

- Cross-node sharing, replication or transactions (Mnesia is explicitly rejected: `disc_copies` loads the whole table into RAM at boot, and we need one get/put).
- Postgres storage; the cache value is large Erlang terms, and serialising them to a database is slower than a disk read.
- Invalidating individual entries; keys are versioned, and a version change clears the disk tier.
- Caching the SVG string or the painted ops; the drawing is cheap relative to construction.
- A cache-management UI.

## Constraints

- **Web layer only.** `lib/girihelix/engine/**` stays pure; the cache is `lib/girihelix_web/workbench/`.
- **Standard library only.** ETS and DETS, no new dependencies.
- **No stale terms.** Keys carry a cache schema version and the app version; a mismatch clears the disk tier on boot.
- **No blocking the LiveView.** Disk reads and builds happen in the existing async task; ETS hits are immediate.
- **Graceful degradation.** A missing or unwritable cache directory disables the disk tier and the workbench still works; a corrupt DETS file is deleted and rebuilt.
- **A writable volume in the deployment.** The homelab service mounts a volume for the cache directory and sets `GIRIHELIX_CACHE_DIR` (not edited in this repository; see `services/girihelix/girihelix.yml` in the homelab repo), so the cache survives container restarts.

## Architecture

`GirihelixWeb.Workbench.ConstructCache` is a GenServer started in the application supervision tree. It owns two stores:

- **Tier 1 — a named, public ETS table** of entries, read-concurrency enabled. At most `@memory_entries = 4`; a put evicts the least recently used entry from ETS only.
- **Tier 2 — a DETS table** (`:dets.open_file(:girihelix_construct_cache, ...)`, `access: :read_write`), capped at `@disk_bytes = 1_000_000_000`. Every put writes DETS; before a write the server evicts the oldest entries until the new size fits. The server tracks each entry's approximate external size (`:erlang.external_size/1`) and last access.

An entry holds:

```elixir
%{
  key: {schema_version, tiling_name, figure},
  frames: [Steps.Frame.t()],
  failure: nil | Steps.Failure.t(),
  cells: 1 | 2,
  faces: nil | {:ok, Faces.colouring()} | {:error, term()},
  size: non_neg_integer(),
  inserted_at: integer(),
  accessed_at: integer()
}
```

The face colouring is filled lazily on the first `Filled` paint and stored back, because re-extracting faces on a heavy map costs seconds even when construction is free.

`fetch(key, build_fun)`:

1. ETS lookup; on a hit, touch `accessed_at` and return.
2. Otherwise take `:global.trans({__MODULE__, key}, fn -> ... end)` and re-check ETS; then DETS. A DETS hit is decoded, promoted into ETS (with eviction) and returned.
3. On a miss, run `build_fun` in the caller (the LiveView's async task, so per-step progress still works), put the result into both tiers, and return.

Failures are cached too: they are deterministic and a failing heavy construct is still expensive.

The disk tier stores a `:"__version__"` entry. On boot, a mismatch with the current `{schema_version, Application.spec(:girihelix, :vsn)}` deletes every entry (and the DETS file if it cannot be opened).

## LiveView integration

- The construct key is `{tiling, figure}`. `ExhibitLive`'s `run_key` becomes the construct key, so style, palette and `tiles` changes reuse the assigned frames: `Run.view/4` redraws the current frame synchronously, and no async run starts.
- A construct-key change cancels any run and starts the async `fetch`: an ETS hit assigns immediately; a DETS hit shows a short "loading cached construction" state; a miss shows the existing per-step progress.
- The adaptive span is part of the cached build; `cells` comes from the entry, so the probe is not repeated.
- Cache path: `config :girihelix, :cache_dir`, defaulting to `var/cache` under the release's working directory, overridable with `GIRIHELIX_CACHE_DIR`. The homelab service adds a volume for it so the cache survives container restarts.
- A cache miss keeps the current behaviour: build in the task, report progress, land with `handle_async`.

## Testing

- A build counter proves a second `fetch` for the same key does not build.
- LRU: five distinct keys leave the four most recent in ETS.
- Disk promotion: evict from ETS, clear memory, fetch again, build count unchanged.
- Disk cap: inserting entries beyond 1 GB (with small synthetic sizes) evicts the oldest.
- Version mismatch: a stored entry with an old version is not returned and the tier is cleared.
- Single-flight: two concurrent `fetch` calls for one key build once.
- Workbench: a palette change, a style change and the `tiles` toggle each leave the construction build count unchanged and update the panel/drawing; frame navigation stays instant.
- Disk disabled: an unwritable cache dir leaves the page working.

## Resolved after builder check

1. **Painting leaves the steps.** `Steps` becomes `place`, `bind`, `units`, `weld`; the style/palette paint moves into the styles exhibit's `draw/2`, applied to the frame's map on every draw. The transport shows the four construct steps; the paint frame disappears, and its source highlighting is no longer a step. This is what makes a `{tiling, figure}` cache key honest: frames never contain a style.
2. **The cache is generic, keyed by an exhibit-declared identity.** `Exhibit` gains an optional `construct_key(params) :: term()`; `Styles` returns `{:styles, tiling, figure}`, `Instancing` returns `{:instancing, tiling, figure}`, and an exhibit without the callback is not cached. `ExhibitLive`'s `run_key` is `{slug, construct_key || values}`, so an exhibit switch can never look like a reuse.
3. **Frames are stored compact.** A cached state keeps only `tiling`, `translations`, `map` and `failure`, plus the step metadata the transport and source pane read; `bindings`, `feature_maps`, `binder` and `region` are dropped, because no draw, row or viewport reads them. An entry whose external size exceeds the disk cap is kept memory-only and reported as such.
4. **Face colouring has an explicit seam.** It is cached in the entry and injected into the params handed to `draw/2` as `:cached_faces` (the exhibit contract stays "frame plus params"). The async build computes it when the requested style is `:filled`; a later switch to `:filled` with no cached colouring starts a second short async phase that computes, stores and redraws — never a synchronous block in the LiveView.
5. **Dev and test isolation.** The disk tier is enabled in `prod` only; `dev` and `test` use the memory tier. Both tiers are keyed by `{schema_version, app_vsn, code_fingerprint}`, where the fingerprint hashes the engine beams that define a cached frame's shape: the dev code reloader recompiles modules without restarting the supervision tree, so without it an in-memory entry could outlive the shapes it was built from. A mismatch at boot clears the disk tier. The cache exposes `reset/1`, and its ETS name and DETS file are injectable so unit tests start an isolated instance. The LiveView tests await both the run and the paint phase rather than resetting the shared cache.

## Decisions taken (our calls)

1. ETS + DETS two-tier, not Mnesia or Postgres, for the reasons above.
2. A 4-entry memory LRU and a 1 GB disk cap with oldest-first eviction.
3. Style, palette and tiles leave the construct key; the face colouring is cached alongside the frames.
4. Failures are cached; the version check clears the disk tier on a deploy with different code.
5. Single-flight runs the build in the requesting task under a global lock, so progress messages stay with the requester.

## Left to the builder

All five answered by the implementation record below.

- The exact DETS file layout, version key and corruption handling.
- The external-size margin used for the caps.
- The loading state's wording and whether a disk hit shows a determinate or indeterminate progress bar.
- The cache directory's configuration name and the homelab volume path.
- Whether the face colouring is stored as part of the entry or in a second keyed table.

## Implementation record (2026-10-24)

Built by `docs/superpowers/plans/2026-10-24-girihelix-construction-cache.md` on branch
`feat/construct-cache`.

- **DETS file and version key.** `construct_cache.dets` under `:cache_dir`, opened as a
  `:set` with `access: :read_write`. The `:"__version__"` entry holds
  `{1, Application.spec(:girihelix, :vsn), code_fingerprint}`, where the fingerprint is
  a hash of the engine beams whose structs a cached frame carries (`Steps`,
  `PlanarMap`, `Point`, `Transform`, `Construct`, `Tiling`). Every stored key in both
  tiers is `{version, key}`, so an entry from another build is unreachable — including
  an in-memory one left behind by a dev hot reload or a deploy that did not bump
  `mix.exs`. A version mismatch at boot deletes every object and rewrites the version
  entry; a file that cannot be opened is closed, deleted and reopened; an unopenable
  directory degrades the cache to its memory tier. A file that opens but yields a read
  error or an object with a non-integer `size` degrades or repairs the tier rather
  than failing the application's boot.
- **External-size margin.** None. Sizes are `:erlang.external_size/1` of the frames,
  recomputed with the face colouring when it arrives, and the byte cap is enforced
  exactly. The memory cap counts entries (four), not bytes.
- **Face-phase wording.** The paint phase reports `painting from the cached map` through
  the existing `#run-progress` status, and the colouring reaches the draw as
  `params[:cached_faces]`. An indeterminately-progressing phase was chosen over a
  determinate bar: the extraction reports no progress.
- **Config names and directory.** `config :girihelix, :cache_dir` comes from
  `GIRIHELIX_CACHE_DIR`, defaulting to `<working dir>/var/cache`;
  `config :girihelix, :construct_cache_disk` is `config_env() == :prod`, so `dev` and
  `test` never open the disk tier. `Application` reads the second flag; the cache reads
  the first for its default DETS path.
- **Face colouring storage.** In the entry's `:faces` field, memory and disk, written by
  `ConstructCache.update_faces/3` when the async phase lands — not a second keyed table.
- **Cache key.** `{exhibit slug, construct_key}`. The exhibit is part of the key, so two
  exhibits naming the same tiling and figure never collide.
- **Compaction.** A cached frame keeps `tiling`, `translations`, `map` and `failure`; a
  cached failure's own frame list is compacted the same way.
- **Single-flight.** `:global.trans({{ConstructCache, {server, key}}, self()})`: the
  resource is the cache and key, the requester the calling process. The plan's literal
  `{__MODULE__, {server, key}}` is not a lock — `:global` reads the id as
  `{resource, requester}`, and two callers passing an identical tuple are treated as the
  same owner.

### Measurements

Dev machine, 2026-10-24. "Cached load" clears the memory tier first, so it measures the
DETS read and promotion, which is the slower of the two tiers.

| Tiling | Build | Cached load (DETS) | Face extraction | Cached draw | Frames | Entry |
| --- | --- | --- | --- | --- | --- | --- |
| `7.6` | 1.281 s | 0.005 s | 0.024 s | 0.005 s | 5 | 827 KB |
| `3-8-4-6` | 82.101 s | 0.042 s | 0.351 s | 0.004 s | 5 | 6.46 MB |

Full suite: 644 tests in about 17 s, with `mix precommit` green and dialyzer
`Total errors: 0`.

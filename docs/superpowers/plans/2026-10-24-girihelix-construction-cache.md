# Construction cache implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build each `{tiling, figure}` construction once, share it across users, persist it to disk, and redraw style, palette and tile-overlay changes without reconstructing.

**Architecture:** A `GirihelixWeb.Workbench.ConstructCache` GenServer owns a named ETS table (LRU four entries) and a DETS table (1 GB, oldest-first), with a `:global.trans` single-flight lock. The styles exhibit stops painting inside its step sequence; `draw/2` paints from the frame's map. `ExhibitLive` keys runs by an exhibit-declared construct identity, so style, palette and `tiles` changes reuse the cached frames, and a cached face colouring feeds `Filled`.

**Tech Stack:** Elixir 1.20, OTP (GenServer, ETS, DETS, `:global`), Phoenix LiveView 1.2, ExUnit. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-24-girihelix-construction-cache-design.md`. Read it first; it fixes the two-tier shape, the caps, the compact frames and the seam for cached faces.

## Global Constraints

- **Web layer only.** The cache lives under `lib/girihelix_web/workbench/`; `lib/girihelix/engine/**` stays pure.
- **Standard library only.** ETS, DETS and `:global`; no new dependencies.
- **Caps.** At most `4` ETS entries; at most `1_000_000_000` bytes on disk, oldest-first; entries larger than the disk cap stay memory-only.
- **No stale terms.** Keys carry `{schema_version, app_vsn}` (or an equivalent fingerprint); a mismatch clears the disk tier. Disk is enabled in `prod` only.
- **Never block the LiveView.** Builds and disk reads happen in the async task; ETS hits are immediate; face extraction is a second async phase, never synchronous in the LiveView.
- **Compact frames.** Cached states keep `tiling`, `translations`, `map`, `failure` and step metadata only; `bindings`, `feature_maps`, `binder` and `region` are dropped.
- **Hard rules.** No `if`/`cond`; function heads and guards; failing public functions return tuples with bang twins where useful.
- **Gates.** The commit hook runs `mix precommit.fast`; before pushing, `mix precommit` with dialyzer `Total errors: 0`.
- **Git.** Work on `feat/construct-cache`; `git commit` as its own command; commits signed via 1Password — on a failure stop and ask.

## Review Focus

1. **An entry larger than the disk cap.** It must remain usable in memory and not crash or be silently lost. Owner: Task 2.
2. **Two concurrent first requests for one key.** Exactly one build must run; the second must receive the same entry. Owner: Task 3.
3. **A corrupt or unopenable DETS file.** The cache must disable the disk tier, clear the file and keep working. Owner: Task 2.
4. **A switch from `Plain` to `Filled` on a cached heavy map.** The first draw must not block the LiveView; the async face phase must compute, store and redraw. Owner: Task 6.
5. **A cached frame after a code change in dev.** The dev cache is memory-only, and a version mismatch clears the prod disk tier; stale frames must never reach `draw/2`. Owner: Tasks 2 and 5.

---

### Task 1: `ConstructCache` memory tier

**Files:**

- Create: `lib/girihelix_web/workbench/construct_cache.ex`
- Modify: `lib/girihelix/application.ex`
- Test: `test/girihelix_web/workbench/construct_cache_test.exs`

**Interfaces:**

- Produces: `ConstructCache.start_link(opts)` with `:name` (default `__MODULE__`), `:ets_name` (default derived), `:memory_entries` (default 4), `:disk?` (default false for tests), `:dets_file`, `:disk_bytes`.
- Produces: `ConstructCache.fetch(server, key, build_fun) :: entry`, `put(server, key, entry)`, `get(server, key) :: entry | nil`, `reset(server)`, where `entry` is a map with at least `:frames`, `:failure`, `:cells`.
- Produces: `ConstructCache.entry(key, frames, failure, cells)` building a normalized entry (computes `:size` via `:erlang.external_size/1`, `:inserted_at`, `:accessed_at`).

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule GirihelixWeb.Workbench.ConstructCacheTest do
  use ExUnit.Case, async: true

  alias GirihelixWeb.Workbench.ConstructCache

  defp start_cache(opts \\ []) do
    name = :"cache_#{System.unique_integer([:positive])}"
    ets = :"cache_tab_#{System.unique_integer([:positive])}"
    start_supervised!({ConstructCache, [name: name, ets_name: ets] ++ opts})
    {name, ets}
  end

  test "a second fetch for one key does not build" do
    {cache, _ets} = start_cache()
    counter = :counters.new(1, [])

    build = fn ->
      :counters.add(counter, 1, 1)
      ConstructCache.entry(:k, [:frame], nil, 2)
    end

    assert ConstructCache.fetch(cache, :k, build).frames == [:frame]
    assert ConstructCache.fetch(cache, :k, build).frames == [:frame]
    assert :counters.get(counter, 1) == 1
  end

  test "the memory tier keeps four entries and evicts the least recently used" do
    {cache, ets} = start_cache()

    for key <- [:a, :b, :c, :d, :e] do
      ConstructCache.put(cache, key, ConstructCache.entry(key, [key], nil, 2))
    end

    keys = :ets.tab2list(ets) |> Enum.map(fn {_k, entry} -> entry.key end)
    assert length(keys) == 4
    refute :a in keys
    assert Enum.sort(keys) == [:b, :c, :d, :e]

    ConstructCache.get(cache, :b)
    ConstructCache.put(cache, :f, ConstructCache.entry(:f, [:f], nil, 2))
    keys = :ets.tab2list(ets) |> Enum.map(fn {_k, entry} -> entry.key end)
    assert :c in keys
    refute :b in keys
    assert :f in keys
  end

  test "reset clears the tier" do
    {cache, _ets} = start_cache()
    ConstructCache.put(cache, :k, ConstructCache.entry(:k, [:k], nil, 2))
    assert ConstructCache.get(cache, :k)
    ConstructCache.reset(cache)
    refute ConstructCache.get(cache, :k)
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix_web/workbench/construct_cache_test.exs`
Expected: FAIL — the module does not exist.

- [ ] **Step 3: Implement the memory tier**

The GenServer owns a named public ETS table (`:set`, `read_concurrency`, `write_concurrency`). `put` writes the entry, then evicts the least recently used entry (smallest `accessed_at`) until at most `memory_entries` remain. `get` reads ETS and touches `accessed_at` via the server (a cast or call); `fetch` does an ETS read, and on a miss calls `build_fun.()`, puts the entry and returns it. `reset` clears ETS. The application supervision tree starts the default instance with `disk?: Application.get_env(:girihelix, :construct_cache_disk, false)` — never `Mix.env/0`, which is unavailable in a release. Add `config :girihelix, :construct_cache_disk, false` to `config/dev.exs` and `config/test.exs`; Task 7 enables it in `runtime.exs` for production.

- [ ] **Step 4: Run the tests to see them pass**

Run: `mix test test/girihelix_web/workbench/construct_cache_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/girihelix_web/workbench/construct_cache.ex lib/girihelix/application.ex test/girihelix_web/workbench/construct_cache_test.exs
git commit -m "feat: add the construction cache memory tier"
```

---

### Task 2: DETS tier, versioning and the 1 GB cap

**Files:**

- Modify: `lib/girihelix_web/workbench/construct_cache.ex`
- Test: `test/girihelix_web/workbench/construct_cache_test.exs`

**Interfaces:**

- Produces: `:disk?`, `:dets_file`, `:disk_bytes` options; a `:"__version__"` entry in DETS; `clear_disk(server)`.
- Produces: on an ETS miss, a DETS lookup that promotes the entry into ETS; on a put, a DETS write unless the entry exceeds `disk_bytes` (then memory-only).
- Produces: disk writes are skipped when `disk?` is false or the file cannot be opened; a corrupt file is deleted and reopened.

- [ ] **Step 1: Write the failing tests**

Add tests that start a cache with a `tmp` DETS file and a small `disk_bytes`, then assert:

- a put followed by `reset` (memory only) and a `fetch` returns the entry and leaves the build counter at zero (promotion);
- inserting entries beyond the byte cap evicts the oldest (`:inserted_at`);
- an entry larger than the cap is returned from memory but absent after `reset`;
- a file containing a mismatched `:"__version__"` is cleared on start;
- `disk?: false` leaves the tier functional without a file.

Use `System.tmp_dir!()` with a unique filename per test and `on_exit` to remove it.

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix_web/workbench/construct_cache_test.exs`
Expected: FAIL — the disk options and behaviour are absent.

- [ ] **Step 3: Implement the disk tier**

Open DETS with `:dets.open_file(name, file: path, type: :set, access: :read_write)`, repairing or deleting on error. Store each entry under its key and a `:"__version__"` key holding `{schema_version, app_vsn}`; on start, a mismatch deletes all entries. Track the total size in the GenServer state; before a put, evict oldest entries until `total + size <= disk_bytes`. Skip DETS when `disk?` is false or opening fails; log the degradation. `fetch` checks ETS, then DETS, promotes, and returns; it never calls `build_fun` when either tier has the entry.

- [ ] **Step 4: Run the tests to see them pass**

Run: `mix test test/girihelix_web/workbench/construct_cache_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/girihelix_web/workbench/construct_cache.ex test/girihelix_web/workbench/construct_cache_test.exs
git commit -m "feat: persist the construction cache to disk"
```

---

### Task 3: Single-flight fetch

**Files:**

- Modify: `lib/girihelix_web/workbench/construct_cache.ex`
- Test: `test/girihelix_web/workbench/construct_cache_test.exs`

**Interfaces:**

- Produces: `fetch/3` takes `:global.trans({__MODULE__, {server, key}}, fun)` on a miss, re-checks both tiers inside the lock, and builds at most once for concurrent callers.

- [ ] **Step 1: Write the failing test**

```elixir
test "two concurrent first fetches build once" do
  {cache, _ets} = start_cache()
  counter = :counters.new(1, [])
  parent = self()

  build = fn ->
    :counters.add(counter, 1, 1)
    send(parent, :built)
    Process.sleep(100)
    ConstructCache.entry(:k, [:frame], nil, 2)
  end

  results =
    [build, build]
    |> Enum.map(fn fun -> Task.async(fn -> ConstructCache.fetch(cache, :k, fun) end) end)
    |> Enum.map(&Task.await/1)

  assert :counters.get(counter, 1) == 1
  assert Enum.map(results, & &1.frames) == [[:frame], [:frame]]
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `mix test test/girihelix_web/workbench/construct_cache_test.exs`
Expected: FAIL — the counter is 2.

- [ ] **Step 3: Implement the lock**

Wrap the miss path in `:global.trans/2`; inside, re-check ETS and DETS before calling `build_fun`, then put. Keep the lock key scoped to `{server, key}` so distinct caches do not contend.

- [ ] **Step 4: Run the tests to see them pass**

Run: `mix test test/girihelix_web/workbench/construct_cache_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/girihelix_web/workbench/construct_cache.ex test/girihelix_web/workbench/construct_cache_test.exs
git commit -m "feat: build each construction once under a global lock"
```

---

### Task 4: Paint moves out of the steps

**Files:**

- Modify: `lib/girihelix_web/workbench/exhibits/styles.ex`
- Tests: `test/girihelix_web/workbench/exhibits/styles_test.exs`, `test/girihelix_web/workbench/exhibit_live_test.exs`

**Interfaces:**

- Produces: `Styles.steps/1` returns the four construct steps (`:place`, `:bind`, `:units`, `:weld`), with no `:paint`.
- Produces: `Styles.draw/2` resolves `Style.roles` and `Palette.roles!` from `params`, paints the frame's `state.map`, composes background → figure → tile overlay, and reports paint errors as a `failure` row rather than a step failure.
- Produces: the paint result is recomputed on every draw; nothing style- or palette-dependent is stored in a frame.

- [ ] **Step 1: Update the failing tests**

Change the step-id assertion to `[:place, :bind, :units, :weld]` and assert the last frame still paints with the default style and shows `faces`; add a test that changing `style`/`palette` params on the same frame changes the ops and rows without re-running the steps.

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix_web/workbench/exhibits/styles_test.exs`
Expected: FAIL — the paint step still exists and the step list has five entries.

- [ ] **Step 3: Move the paint into `draw/2`**

Remove `paint_step/2` from `steps/1` and the `state.paint` write. In `draw/2`, compute the roles, call `Style.paint(style, state.map, roles)`, and compose the ops. A `{:error, reason}` from painting falls back to the structure ops and sets the `failure` row (the same reason names as before). Keep `picture/1`'s painted-vs-fallback logic, now per draw.

- [ ] **Step 4: Run the tests to see them pass**

Run: `mix test test/girihelix_web/workbench/exhibits/styles_test.exs test/girihelix_web/workbench/exhibit_live_test.exs`
Expected: PASS, with the transport showing four steps.

- [ ] **Step 5: Commit**

```bash
git add lib/girihelix_web/workbench/exhibits/styles.ex test/girihelix_web/workbench/exhibits/styles_test.exs test/girihelix_web/workbench/exhibit_live_test.exs
git commit -m "refactor: paint from the frame on every draw"
```

---

### Task 5: Construct identity and cache-backed runs

**Files:**

- Modify: `lib/girihelix_web/workbench/exhibit.ex`
- Modify: `lib/girihelix_web/workbench/exhibits/styles.ex`
- Modify: `lib/girihelix_web/workbench/exhibits/instancing.ex`
- Modify: `lib/girihelix_web/workbench/run.ex`
- Modify: `lib/girihelix_web/workbench/exhibit_live.ex`
- Tests: `test/girihelix_web/workbench/run_test.exs` (create if absent), `test/girihelix_web/workbench/exhibit_live_test.exs`, `test/girihelix_web/workbench/exhibits/styles_test.exs`

**Interfaces:**

- Produces: `Exhibit` optional callback `construct_key(params) :: term()`; `Styles.construct_key/1` returns `{:styles, tiling, figure}`; `Instancing.construct_key/1` returns `{:instancing, tiling, figure}`.
- Produces: `Run.construct(exhibit, values, on_step)` returning `%{frames, failure, cells}` with compact frames; `Run.view(frames, failure, index, values)` unchanged.
- Produces: `ExhibitLive`'s `run_key` is `{slug, construct_key || values}`; a construct-key change fetches through `ConstructCache`, style/palette/tiles changes redraw from the assigned frames without an async run.
- Produces: `Run.compact(frames)` strips the cached states to `tiling`, `translations`, `map`, `failure` plus the step metadata.

- [ ] **Step 1: Write the failing tests**

- `Styles.construct_key` ignores style, palette and `tiles`.
- A LiveView test opens `/workbench/styles`, awaits the run, then `render_change`s the palette, the style and `tiles`; each returns new rows/ops without `#run-progress`, and a build counter passed through `ConstructCache` (or a test-only hook) stays at one.
- `Run.compact/1` drops `bindings`/`feature_maps`/`binder`/`region` and keeps `map`/`translations`/`tiling`/`failure`.
- An Instancing run and a Styles run with the same tiling/figure use different cache keys.

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix_web/workbench`
Expected: FAIL — no construct key, no cache, and a palette change starts a run.

- [ ] **Step 3: Implement the identity and cache-backed run**

Add the callback and the two implementations. In `ExhibitLive`, compute the construct key, compare it with the assigned one, and on a change start `start_async(:run, fn -> ConstructCache.fetch(ConstructCache, key, fn -> Run.construct(exhibit, values, on_step) end) end)`; on a match, select the frame and draw synchronously. Store the entry's `cells` with the frames. `Run.construct/3` runs the steps and compacts them before returning. Keep `@max_frames` and the failure path intact; a cached failure is rendered exactly like a fresh one.

- [ ] **Step 4: Run the tests to see them pass**

Run: `mix test test/girihelix_web/workbench`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/girihelix_web/workbench test/girihelix_web/workbench
git commit -m "feat: reuse cached constructions across style changes"
```

---

### Task 6: Cached face colouring and the async paint phase

**Files:**

- Modify: `lib/girihelix/engine/render/style.ex`
- Modify: `lib/girihelix/engine/render/styles/filled.ex`
- Modify: `lib/girihelix_web/workbench/exhibits/styles.ex`
- Modify: `lib/girihelix_web/workbench/exhibit_live.ex`
- Modify: `lib/girihelix_web/workbench/construct_cache.ex`
- Tests: `test/girihelix/engine/render/styles/filled_test.exs`, `test/girihelix_web/workbench/exhibit_live_test.exs`

**Interfaces:**

- Produces: `Style.paint(style, map, roles, opts)` with `:faces` — a precomputed `Faces.extract_faces/1` result; `Filled` uses it when present, otherwise extracts.
- Produces: `ConstructCache.update_faces(server, key, faces)` storing the colouring in the entry (memory and disk).
- Produces: `Styles.draw/2` reads `params[:cached_faces]`; `ExhibitLive` injects it and starts `start_async(:faces, ...)` when the style is `:filled` and the entry has no colouring; `handle_async(:faces, ...)` stores it and redraws.

- [ ] **Step 1: Write the failing tests**

- `Filled.paint/4` with `faces: {:ok, colouring}` uses the given faces (a counting/marker colouring proves no extraction).
- The LiveView on `/workbench/styles` with a heavy cached tiling and `style=filled`, when the entry has no faces, shows a paint-loading state, then the fills, and the cache entry now has the colouring; a second style switch to `filled` does not start the phase.

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix/engine/render/styles/filled_test.exs test/girihelix_web/workbench/exhibit_live_test.exs`
Expected: FAIL — `paint/4` and the phase do not exist.

- [ ] **Step 3: Implement the seam and the phase**

Add the opts argument and the `Filled` branch. In `ExhibitLive`, after the run/view assigns, start the face phase when needed; send `{:faces_ready, key, faces}` to the LiveView, store via the cache, and redraw. Show "painting" in `#run-progress` while it runs. Do not block `handle_params`.

- [ ] **Step 4: Run the tests to see them pass**

Run: `mix test test/girihelix/engine/render/styles/filled_test.exs test/girihelix_web/workbench/exhibit_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/girihelix/engine/render lib/girihelix_web/workbench test
git commit -m "feat: cache face colouring for cached maps"
```

---

### Task 7: Configuration, docs, homogenisation and gate

**Files:**

- Modify: `config/runtime.exs`
- Modify: `config/dev.exs`, `config/test.exs`
- Modify: `docs/superpowers/specs/2026-10-24-girihelix-construction-cache-design.md`
- Modify: `docs/backlog.md`
- Modify the modules touched by Tasks 1–6
- Note for the homelab repo (do not edit it here): add a writable volume and `GIRIHELIX_CACHE_DIR` to `services/girihelix/girihelix.yml`.

**Interfaces:**

- Consumes: every prior task.
- Produces: `config :girihelix, :cache_dir` from `GIRIHELIX_CACHE_DIR` (default `var/cache`) and `config :girihelix, :construct_cache_disk` (default true in prod); the design status accepted with the implementation record.

- [ ] **Step 1: Run the full gate**

Run: `mix precommit`
Expected: pass with dialyzer `Total errors: 0`.

- [ ] **Step 2: Fix and homogenise**

Fix only what the gate reports. Re-read the touched modules: no `if`/`cond`, docs describe behaviour, no module over 800 lines, the cache never touches engine types outside public functions.

- [ ] **Step 3: Update the documents**

Mark the design accepted, dated 2026-10-24, and record the implementation choices: the DETS file and version key, the external-size margin, the face-phase wording, the config names and the cache directory. Add backlog items only for real deferrals (for example a cache stats page or per-entry invalidation). Record the homelab volume requirement in the design's constraints.

- [ ] **Step 4: Measure**

Record the first-build and cached-load times for `7.6` and `3-8-4-6`, and the suite time, in the report.

- [ ] **Step 5: Ask the user to check**

Ask the user to open `/workbench/styles`, change style/palette/tiles on `7.6`, restart nothing, and confirm the changes are instant; then restart the app (dev memory-only) and confirm the prod disk behaviour is described correctly for the deploy.

- [ ] **Step 6: Commit**

```bash
git add config lib test docs
git commit -m "chore: configure and document the construction cache"
```

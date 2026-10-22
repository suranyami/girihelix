# Catalogue and instancing — design (Plan 4)

**Date:** 2026-10-22
**Status:** draft for builder review
**Porting source:** Taprats 1.1.12 (changeset `b6c172`)
**Depends on:** Plans 1b/1c (`PlanarMap`, `FillRegion`, the Taprats harness), Plan 2 (workbench framework), Plan 3 (figures)
**Follows:** the domain model design (`2026-10-16-girihelix-domain-model-design.md`) and the workbench plan series (`2026-10-16-girihelix-workbench-design.md`, Plan 4 row)

## Intent

Plan 4 turns the tiling catalogue into engine data and makes a tiling plus figures constructible. The concrete result: pick a shipped tiling, bind a figure to its regular features, and walk the construction — placements, one translational unit, the periodic copies, and the final weld — in the workbench.

This is the first plan where three previously separate pieces meet: the catalogue data, the figure builders, and the planar-map merge operations. The algorithm is Taprats' `Prototype.construct`; the data is Taprats' `.tiling` files.

## Goals

- Engine structs for `Tiling`, `Feature`, `PlacedFeature`, and a `construct` operation exposed as `start/steps/result` plus a plain function.
- A parser for Taprats' `.tiling` format, with explicit errors instead of silent desynchronisation.
- The 60 shipped `.tiling` files vendored into `priv/`, with provenance, and loadable by name.
- Constructed maps verified against real Taprats through the local harness.
- Three workbench exhibits in the `:tilings` category: `catalogue`, `tiling`, `instancing`.

## Non-goals

- Ash resources, migrations and seeding — Plan 6.
- Render styles — Plan 5.
- `DesignElement`'s default-figure rule (`Rosette(n, 0.0, 3)` for regular features with more than four sides) — Plan 6. Plan 4 uses an explicit binding supplied by the caller or exhibit.
- Contact inference, aperiodic tilings, interlace, colour systems, alternative geometries — the domain spec's recorded intentions.

## Constraints

- **Engine purity.** The engine imports the standard library only; no Ash, Ecto, Phoenix or `GirihelixWeb`.
- **Faithful first.** Preserve Taprats' four-pass construction, its simple-merge/slow-merge split, its `1.0e-7` coalescing, and its structural feature equality. Do not "improve" geometry.
- **Steps.** `construct` exposes the engine sequence; the plain function is the steps run. No module over 800 lines.
- **The harness stays local.** Nothing under `reference/` is committed. The catalogue files are copied into `priv/` with attribution; that copy is committed.
- **No new dependencies.**

## The model

### `Tiling`

| Field | Type | Meaning |
| --- | --- | --- |
| `name` | `String.t()` | The catalogue key, taken from the file body, never the filename |
| `description` | `String.t() \| nil` | The quoted description; Taprats tolerates a missing one |
| `author` | `String.t() \| nil` | The quoted author; Taprats tolerates a missing one |
| `t1`, `t2` | `Point.t()` | The two lattice generators |
| `features` | `[Feature.t()]` | The de-duplicated feature list, in catalogue order |
| `placements` | `[PlacedFeature.t()]` | Each feature id plus its transform, in a deterministic order |

There is **no symmetry field**. Rotations and reflections are the six doubles of each placement's `Transform`; a reflection has a negative determinant. Only integer lattice translations are modelled.

### `Feature`

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | `integer()` | Assigned after tolerant de-duplication; stable within a catalogue load |
| `regular` | `pos_integer() \| nil` | The side count when the file said `regular`, else `nil` |
| `points` | `[Point.t()]` | Explicit polygon points; empty for a regular feature |

`Feature.points/1` returns the stored points, or generates the regular polygon from the side count. The generation is Taprats' formula: angle `(π/n)(2i+1)`, circumradius `1/cos(π/n)`, so the apothem is 1. The `regular` flag is behaviourally load-bearing (Plan 6 defaults regular features with more than four sides to a rosette), so it is preserved even though the points are derivable.

### `PlacedFeature`

A `feature_id` plus a `Transform`. Two placements are equal only when the six doubles are exactly equal and the feature ids match; Taprats' `Transform.equals` is exact, not tolerant.

### Identity and ordering (our call)

Taprats compares `Feature` structurally with tolerant point equality and iterates a `HashSet`/`Hashtable` in unspecified order. The port needs a deterministic model, so:

- On load, features are de-duplicated by **tolerant structural equality** (same `regular` flag, same point count, points equal within `1.0e-7` in index order), and each distinct feature gets an integer id. This preserves Taprats' ability to share one feature across several placements without relying on Elixir's exact term equality.
- Placements are de-duplicated by exact `(feature_id, transform)` equality, then ordered by feature id and the six transform doubles.
- Figures are supplied by a binder: `construct(tiling, binder, region)` calls `binder.(feature)` in its `:bind` step. A raising constructor is a failure frame, not a LiveView error.

## The `.tiling` format

```text
tiling "<name>" <feature_count>
<t1.x> <t1.y>
<t2.x> <t2.y>
  regular <sides> <placement_count>
  <a b c d e f>            # one placement per line, placement_count of them
  ...
  polygon <point_count> <placement_count>
  <x> <y>                  # point_count pairs
  ...
  <a b c d e f>            # placement_count six-double transforms
  ...
"<description>"
"<author>"
```

- Comments: `#`, `%`, `//` and `/* ... */`. The quote character is `"`. Numbers accept `E` notation.
- The first token must be `tiling`. Any keyword other than `regular` is read as `polygon` by Taprats; the port **rejects** an unknown keyword instead of desynchronising.
- A regular feature stores only the side count; the points are generated.
- A missing `description`/`author` is allowed at end of file.
- Parse errors are returned as `{:error, {:invalid_tiling, file, reason}}`; the catalogue loader reports every bad file and continues.

## Catalogue population (our call)

Taprats ships 58 tilings as Java code, 60 `.tiling` files, and a union of 86 names when the files shadow the code. Plan 4 commits the **60 files**:

- The code-only tilings would require porting 58 Java builder blocks, which is catalogue transcription rather than engine work.
- The files are self-contained data, parseable by the parser this plan builds, and the external files shadow the code versions for the 32 overlapping names.
- The workbench catalogue shows exactly what is loadable.

The files are copied from `reference/1.1.12/tilings/` into `priv/tilings/` with a `README.md` recording the source and GPLv3 provenance (Taprats and girihelix are both GPLv3). An `index.json` lists `{name, file}` in name order. Filenames are not reliable names; the `name` comes from the file body.

Two files carry non-UTF-8 descriptions: `Mughal.tiling` has a cp1252 byte and `pbn_7.tiling` a MacRoman byte. The loader keeps both files and sanitises `description`/`author` to valid UTF-8 with U+FFFD replacements, recording the two files in the README. Names and geometry are ASCII.

## The construction algorithm

`construct(tiling, binder, region)` where `binder :: (Feature.t() -> Figure.t() | nil)`:

1. **Enumerate lattice translations.** Use `FillRegion.fill/3` over a quadrilateral region. For every emitted `{m, n}`, build `Transform.translate(m·t1 + n·t2)`. FillRegion's row-major order is the canonical translation order.
2. **Bind the figures.** Call `binder.(feature)` for every feature, in feature-id order, keeping the non-nil results. Binding is a step, so a raising builder (a triangle `Star`, for example) becomes a failure frame.
3. **Per bound feature**, in feature-id order:
   1. Build `figmap = Figure.map(figure)` — the **whole figure**, which for radial figures is already replicated through the symmetry ladder. This is not `Figure.unit/1`.
   2. Collect the transforms of every placement whose feature id matches.
   3. `transmap = PlanarMap.replicate!(PlanarMap.new(), figmap, transforms)` — the simple merge inside one translational unit. No crossing detection, no splitting.
   4. `featuremap = PlanarMap.replicate!(PlanarMap.new(), transmap, translations)` — the simple merge at every lattice translation.
   5. `ret = PlanarMap.weld!(ret, featuremap)` — the slow merge, the only crossing pass. Different features genuinely cross; the weld splits, unifies by tolerance, and re-sorts.
4. Return `ret`.

### Errors

`construct/3` returns `{:ok, map}` or `{:error, reason}`, with `construct!/3` raising. Reasons: `:degenerate_basis` and `:too_many_units` from FillRegion, `:inconsistent_order` from replicate or weld, and `{:figure_failed, exception}` when the binder raises (the stepped path surfaces the same raise as a `Steps.Failure`). A feature with no bound figure is skipped silently, as in Taprats; a tiling with no translations is unrepresentable by the parser.

### Region type and the default region (our call)

Taprats' `construct` accepts an arbitrary polygon; the current `FillRegion.fill/3` accepts exactly four points. Plan 4 uses a **quadrilateral region** and documents the limit. Extending FillRegion to general polygons is deferred.

The unit-cell parallelogram `[0, t1, t1 + t2, t2]` is not used directly: a vertex whose y is `-1.0e-16` floors to row `-1`, adding a spurious cell (seen on `4.5`). `Construct.default_region/1` instead takes the axis-aligned bounding box of the four unit-cell corners and expands every side by `0.01 * max(|t1|, |t2|)`. The goldens, the `tiling` exhibit and the `instancing` exhibit all use this region on both the Elixir and Java sides. A caller may pass its own quadrilateral.

## Determinism and goldens (our call)

Taprats' construction output depends on `HashSet`/`Hashtable` iteration order, which is unspecified and feeds vertex numbering in a raw dump. A deterministic Elixir order will therefore disagree with a raw index-wise golden even when the geometry matches.

Plan 4 therefore compares constructed maps **canonically**:

- vertices as sorted `{x, y}` pairs rounded to `1.0e-12`;
- edges as sorted pairs of endpoint positions;
- rings as sorted cycles of positions;
- counts and `verify/1` separately.

The Taprats harness gains a canonical construct comparison (or a canonical dump mode). Translation enumeration and the simple merges can still be compared in their deterministic order where the harness already supports it. Emulating Java hash order is rejected: it is brittle and would make the port depend on a hash implementation rather than on geometry.

## Workbench exhibits

All three are `category: :tilings` and registered after the figures exhibits.

### `catalogue`

A `{:panel, rows}` exhibit: one row per shipped tiling (name, feature count, placement count), plus totals and any files that failed to parse. Parameters: none beyond a sort/group choice if useful. It reads the loader, not the database.

### `tiling`

Shows one tiling's structure: the two translation vectors from the origin as guides, every placed feature's outline (transformed points) as a polygon, the unit cell as a guide, and the lattice cells `FillRegion` would stamp. Parameters: `tiling` enum over the catalogue. Steps: a single `:place` step that materialises the translated placements and the cell list; the plain result is the tiling's placed features. Rows: name, t1, t2, features, placements, cells. It does not weld an outline map, so there is no `verify` row.

### `instancing`

The step-through exhibit: `construct`'s actual engine steps (`:place`, `:bind`, `:units`, `:weld`). Parameters: `tiling` enum, `figure` enum (`:rosette`, `:star`, `:none`), and a region size. The `:bind` step calls the binder: every regular feature gets the chosen figure at its side count. `Star` uses `Star.build!/3`, so a triangle tiling (`3-8-12`, `Tricorn`, and eight others) fails as a frame rather than a LiveView error; `Rosette` uses `Rosette.new!/3`. Irregular features are unbound; `:none` binds nothing. The canvas always shows the translation vectors, the unit-cell guide and the tiling's placed-feature outlines, so frame zero and an unbound run stay non-empty; the constructed map is drawn over them when present. `verify` is `n/a` while the map is empty. Rows: tiling, cells, features bound, placements, vertices, edges, `verify`.

A shared `GirihelixWeb.Workbench.Exhibits.Tilings` helper holds the placed-feature polygon ops, the translation/cell guides and the shared rows, following `Exhibits.Figures`.

## Testing

- **Parser:** parse all 60 files; assert the known counts for `4.5` and `6.5`; malformed inputs (bad keyword, truncated transform, missing header) return the named error; a missing description/author parses.
- **Catalogue:** every shipped file loads; names are unique; the index and the files agree; the feature de-duplication is exercised by a file with repeated features.
- **Construct:** a hand-built small tiling with a bound rosette produces a verified map with expected counts; the stepped and plain paths agree; a degenerate basis and the row cap return their errors; an unbound feature is skipped.
- **Goldens:** canonical construct comparison against Taprats for `4.5`, `6.5` and one mixed regular/polygon tiling. Bindings are fixed for the comparison: every regular feature gets `Rosette.new!(sides, 0.0, 3)`, irregular features are unbound, and both sides use `Construct.default_region/1`. No shipped tiling contains a reflection (all 933 placements have positive determinants), so reflection handling is covered by a hand-built unit test rather than a catalogue golden.
- **Workbench:** the registry property test covers the three exhibits at defaults and range extremes; frame zero and failed runs draw.

## Decisions taken (our calls, for review)

1. Ship the 60 `.tiling` files, not the 86-name union. Cost: the 26 code-only tilings are unavailable.
2. Feature ids and tolerant de-duplication on load; figures are supplied by a binder called with the feature. Cost: an extra id field the Ash layer will mirror in Plan 6.
3. Quadrilateral construct regions only. Cost: general polygon regions deferred.
4. Canonical construct goldens, not index-wise raw dumps. Cost: the harness needs a canonical comparison; raw dumps remain useful for counts.
5. `construct` uses `Figure.map/1`, not `Figure.unit/1`. This corrects the porting note's "unit scale" wording.
6. `regular` is stored as the side count and points are generated; the flag survives.
7. The instancing exhibit's bindings are explicit per regular feature; the Plan 6 default-figure rule is not implemented here.
8. Binding is its own step, so a raising figure builder is a failure frame. The instancing exhibit uses `Star.build!/3` for stars, so triangle tilings fail visibly; `Rosette.new!/3` is already total for its clamped inputs.
9. Goldens fix the bindings (`Rosette.new!(sides, 0.0, 3)` on regular features) and `Construct.default_region/1`. No shipped tiling contains a reflection, so reflections get a hand-built unit test, not a catalogue golden.
10. Ship all 60 files, sanitising the two non-UTF-8 descriptions to U+FFFD; the catalogue README records them.
11. The `tiling` exhibit draws outlines and cells without welding an outline map; the `instancing` exhibit always draws the tiling guides, so a frame-zero or unbound run is non-empty.
12. The default region is the expanded bounding box, not the unit-cell parallelogram, avoiding the `-1.0e-16` floor bug.

## Left to the builder

- The exact module split (`Tiling`, `Feature`, `PlacedFeature`, `Construct`, `Catalogue`, the parser) and whether the catalogue loader lives under `engine/` or a sibling namespace.
- The steps' labels (the ids are `:place`, `:bind`, `:units`, `:weld`).
- The canonical comparison's concrete format in the harness.
- The vendored catalogue's licence/provenance note wording.

# Backlog

Deferred work, findings and suggestions, captured so they are not lost mid-plan.

**This file holds what is queued. `AGENTS.md` holds how we work.** Triage this when
writing the next plan: each open item either becomes a task, becomes a recorded
intention in the relevant spec, or is closed with a reason. An item that survives
two triages unchanged is a signal it should be closed rather than carried.

## Format

- One entry per item, with the date captured and a one-line title.
- Say what it is, why it matters, and what fixing it would cost.
- If it came from a review, cite the finding.
- No design rationale here — that belongs in the spec for the thing being
  designed. This file is a queue, not a record of decisions.

## Open

### `Faces.Walk` has no iteration cap (captured 2026-10-20, Plan 1c homogenisation)

The walk stops only on returning to its start, as Taprats' does, so a map whose
ring order does not lead back to the start loops forever instead of failing. No
valid map reaches it, and a visited set or a step cap would change behaviour on a
corrupt map. Fixing it means choosing a new reason for `Faces.extract_faces/1`,
such as `:unwalkable_face`, and pinning it with a hand-built corrupt map.

### `Rect.center_inside/2` raises on a zero-sized rect (captured 2026-10-20, Plan 1c homogenisation)

It divides by both of the inner rect's dimensions, so a zero width or height
raises `ArithmeticError`; Taprats would carry Infinity or NaN. Plan 1c documents
the precondition because the design named no error reason for `Rect`. A later
caller that can supply a degenerate rect needs either an error tuple or a
constructor that rules zero extents out.

### Syntax highlighting in the source pane is deferred (captured 2026-10-21, Plan 2 homogenisation)

The source pane renders plain monospace text and marks the step's lines, so a
reader sees the call but not syntax colours. `makeup` and `makeup_elixir` were
the design's proposal; Plan 2 chose not to add the dependency. Adding it costs
two pure-Elixir deps, a tokenizer call per rendered window and a stylesheet for
the highlight classes. Deferred until the plain line pointer proves insufficient.

### `Svg.render/3` does not XML-escape op option values (captured 2026-10-21, Plan 2 homogenisation)

`fill`, `stroke`, `dash`, `width` and `opacity` are interpolated into attributes
verbatim; only label text and the root class pass through `Svg.escape/1`. Every
current value is an authored constant, so the output is safe today. An exhibit
that derived a colour from a parameter would put arbitrary text into the
document. Escape the option values in the serializer, or constrain them to a
validated set, before the first parameter-derived option lands.

### The source resolver assumes the process cwd is the project root (captured 2026-10-21, Plan 2 homogenisation)

`Source.resolve/1` makes a captured absolute path relative with
`Path.relative_to_cwd/1`, then accepts it only under `lib/`. That holds under
`mix` and for the release, where the cwd is the project root. A caller started
from another directory — an escript, a mix task run elsewhere, a future worker —
would resolve every step to `:unavailable`. Pin a project-root setting at compile
time from `__DIR__` if the workbench ever needs to run outside a project-root
cwd.

### Instancing lacks its region-size parameter (2026-10-23, Plan 4 review)

The instancing exhibit's params are `tiling` and `figure` only, and both
`initial/1` and `steps/1` hardwire `Construct.default_region/1`, so the region
the exhibit fills is fixed. The spec's Catalogue & Instancing exhibit names a
region-size parameter the reader can turn. Adding it costs one `Param`
(`:region` or a scalar multiplier over `default_region/1`) and threading it
through `initial/1`, `steps/1` and `reproduce/1`.

### The catalogue panel lacks its totals row (2026-10-23, Plan 4 review)

The catalogue exhibit renders one row per shipped `.tiling` file and stops — the
spec's Testing → Catalogue section asks for a totals row summing the tile and
placement counts across the catalogue. Adding it is a `panel_rows/1` addition
summing the parsed rows' counts, one placeholder decision for parse-failed rows.

### Rows omit `cells` and `features bound` (2026-10-23, Plan 4 review)

The tiling and instancing exhibits report their step state without a `cells`
count (unit cells the fill produced) or a `features bound` count (bindings kept
by the `:bind` step; the useful one for reading a run). Both are already in
`Construct.state` (`translations` and `bindings`), so the rows would be one
field each plus a panel-row decision in the catalogue panel.

### `priv/tilings/` needs `:code.priv_dir/1` (2026-10-23, Plan 4 review)

`Catalogue` reads `priv/tilings/index.json` and the shipped `.tiling` files
through paths relative to the process cwd at compile time (`@dir`, the
`@external_resource`) and at load time. That holds under `mix`, and a release
started in its project root works today for the same reason the source resolver
above does; a release started elsewhere would read nothing, or fail
`File.read!/1`. Resolve the read paths with `:code.priv_dir(:girihelix)` when the
workbench is first run from a release started outside a project-root cwd.

### Browsing palettes by base colour (captured 2026-10-24, Plan 5 homogenisation)

The palette control is one 348-entry enum of combination numbers. The dataset
is organised the other way round too — each of the 157 colours lists the
combinations it appears in — so a reader could pick a colour and see the
combinations built on it. That needs a second control and a filter over
`Palette`'s combination index.

### A styled figure exhibit without a tiling (captured 2026-10-24, Plan 5 homogenisation)

The `:styles` exhibit always paints a constructed catalogue tiling, so a figure
or a welded figure map cannot be painted directly. The design names this as a
follow-up: it needs a figure-focused exhibit over the existing binders plus the
same terminal paint step.

### Palette labels in the controls (captured 2026-10-24, Plan 5 homogenisation)

The palette enum renders each combination as its raw number (`253`), because
`Palette.options/0` returns digit atoms. A reader cannot tell what a combination
looks like before choosing it. Fixing it needs the param layer to carry a
display label per option, or the palette control to resolve a combination's
colours for a swatch.

## Closed

- **Jason is compile-time-only in the engine** (Plan 4 review). Closed
  2026-10-24: new engine data modules use the standard library's `JSON` module;
  `Tilings.Catalogue` keeps Jason until it is next touched.
- **`Point.compare_to/2` had no documented sorting idiom** (Plan 1a review).
  Closed 2026-10-22: `Point.sorter/0` converts the comparator into the boolean
  predicate `Enum.sort/2` expects, keeping the `tolerance2` band, and is pinned
  by two tests.
- **ConnectFigure's double child-unit build** (Plan 3 homogenisation). Closed
  2026-10-22: `ConnectFigure` caches the unit it builds while deriving the
  scale; `ScaleFigure.build_unit/3` and `start/3` accept it, and `child_changed/1`
  re-derives both. Pinned by a counting child and a stale-child test.
- **Star's crash parameters were accepted by the constructor** (Plan 3
  homogenisation). Closed 2026-10-22: `Star.new/3` builds the unit once and
  refuses `(8, 7.02, 3)` with `{:error, :degenerate_crossing}`. `Star.build/3`
  keeps the faithful unchecked path for the stepped builder, which still shows
  the crash as a failure frame and matches the Java golden.
- **`Point.normalize/1`'s scaling branch unasserted** (Plan 1a review). Closed
  2026-10-19: asserted in `3ad90d3` (engine types plan, Task 2).
- **Untested `Point` accessors** (Plan 1a review). Closed 2026-10-19: `mag/1`,
  `unit_x/0`, `unit_y/0` and `tolerance/0` asserted in `3ad90d3` (Task 2).
- **`Point.project/4` recomputed `delta`** (Plan 1a review). Closed 2026-10-19:
  `delta` is passed down from `dist2_to_line/3` in `3ad90d3` (Task 2).
- **The purity guard did not cover `Ecto`** (Plan 1a review). Closed 2026-10-19:
  pattern added in `d022209` (Task 1).
- **The purity guard's glob could pass vacuously** (Plan 1a review). Closed
  2026-10-19: a test asserts it scans at least seven engine files, including
  `segment.ex`, in `d022209` (Task 1).
- **`GIRI001` had never been observed firing.** Closed 2026-10-19: a planted
  903-line module that parses produced `Module is 904 lines long (max 800)` from
  both `mix credo -a --strict <file>` and an unscoped `mix credo -a --strict`,
  which exited 2. The check works, so `GIRI002`'s failure was specific to that
  check, not to the custom-check wiring (engine types plan, Task 7).
- **Every plan should end with a homogenisation pass.** Closed 2026-10-19:
  `AGENTS.md` already carries it as part of the definition of done, and the
  engine types plan ran it as Task 6 (`cdf7550`).
- **Plan 1a listed `Point.TRUNC` among the constants to port** (Plan 1a review).
  Closed 2026-10-19: moved to the "do not port" sentence with its reason in
  `cdf7550` (Task 6).
- **`Transform`'s raise paths untested** (Plan 1a review). Closed 2026-10-17: the
  error-tuple rework replaced the raises, and `invert!/1`,
  `reflect_through_line/2`'s degenerate case and `match_two_segments/4`'s
  zero-length case all gained tests. (Both degenerate cases have since been made
  unrepresentable by `Segment`.)
- **`Polygon.new/1` did not say the closing edge is implicit** (Plan 1a review).
  Closed 2026-10-17: documented on `new/1` during the rework.
- **`Map` → `PlanarMap`** (captured 2026-10-17). Closed 2026-10-20: the module is
  `PlanarMap`, with `mergeSimpleMany` as `replicate/3` and `mergeMap` as `weld/2`,
  in `53f656f` (`PlanarMap` with vertex and edge insertion), `9e7ff8c`
  (`replicate/3`) and `c37cabf` (`weld/2`), with the flaws recorded in the
  homogenisation commit (Plan 1b, Task 10).

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

### `Point.compare_to/2` has no documented sorting idiom (captured 2026-10-17, from the Plan 1a review)

Triaged once (2026-10-19): carried to Plan 3, which has its first caller.
Triaged twice (2026-10-21): Plan 3 added no `Infer` caller — its figures design
lists `Infer` as a non-goal — so the entry rolls forward to the plan that
introduces `Infer`. It stays open rather than closing, because that plan will
need the sorting idiom.

`Enum.sort(list, &Point.compare_to/2)` raises `CaseClauseError`, because
`Enum.sort/2` wants a boolean predicate. `Enum.sort_by(&Point.mag2/1)` is *not* a
faithful substitute — it drops the `1e-14` band. Needs either a documented
conversion or a `sorter/0` helper, since the comparator's one caller is in
`Infer`. A comparator is exactly the kind of thing a spec should pin down.

### A cached unit if ConnectFigure's double build proves costly (captured 2026-10-21, Plan 3 homogenisation)

`ConnectFigure.new/1` derives the scale with `compute_scale/1`, which builds the
child's unit, and `build_unit/1` then builds it again through
`ScaleFigure.build_unit/2`. Plan 3 measured no cost: the units are small and an
exhibit builds one figure per frame. If the studio re-parameterises a connect
figure on every keystroke, cache the unit on the figure or pass the already-built
unit into the scale derivation. Cost: a cache field, its invalidation in
`child_changed/1`, and a test that a stale child is never served.

### A constructor-level rejection of Star's crash parameters (captured 2026-10-21, Plan 3 homogenisation)

`Star.new/3` accepts parameters whose closure crossing does not exist — the
canonical case is `(8, 7.02, 3)` — and `build_unit/1` then raises
`star: degenerate_crossing`. That is the faithful crash, and the workbench shows
it as a failure frame. If the studio must refuse the parameters at the control
instead, the constructor needs a geometric feasibility check, which means
building the figure at construction and accepting a much slower `new/3`. Not
done now: Plan 3's contract is that a geometric degeneracy is not a parameter
error.

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

## Closed

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

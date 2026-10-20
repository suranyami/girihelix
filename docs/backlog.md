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

`Enum.sort(list, &Point.compare_to/2)` raises `CaseClauseError`, because
`Enum.sort/2` wants a boolean predicate. `Enum.sort_by(&Point.mag2/1)` is *not* a
faithful substitute — it drops the `1e-14` band. Needs either a documented
conversion or a `sorter/0` helper, and Plan 3 will need it, since the
comparator's one caller is in `Infer`. A comparator is exactly the kind of thing
a spec should pin down.

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

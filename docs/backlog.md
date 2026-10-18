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

### Untested branches (captured 2026-10-17, from the Plan 1a review)

- **`Point.normalize/1`'s scaling branch is unasserted.** Only its
  zero-magnitude early return is tested, so the function's entire purpose —
  `scale(point, 1.0 / magnitude)` — is uncovered. Cheap to fix: one assertion on
  a non-unit vector.
- **`Point.compare_to/2` has no documented Elixir sorting idiom, and the obvious
  one crashes.** `Enum.sort(list, &Point.compare_to/2)` raises `CaseClauseError`,
  because `Enum.sort/2` wants a boolean predicate.
  `Enum.sort_by(&Point.mag2/1)` is *not* a faithful substitute — it drops the
  `1e-14` band. Needs either a documented conversion or a `sorter/0` helper, and
  it will be needed by Plan 3, since the Java comparator's one caller is in
  `Infer`. More pressing now that specs are becoming load-bearing: a comparator
  is exactly the kind of thing a spec should pin down.
- **Untested accessors:** `Point.mag/1`, `unit_x/0`, `unit_y/0`, `tolerance/0`.
  Low value individually, but they are the module's stated public surface.

### Guard gaps (captured 2026-10-17, from the Plan 1a review)

- **The purity guard does not cover `Ecto`.** `test/girihelix/engine/architecture_test.exs`
  checks `Ash`, `Phoenix` and `GirihelixWeb`, but the spec's rule reads "the
  standard library only", so an engine file reaching for `Ecto.UUID` would pass.
  One more pattern entry closes it.
- **The guard's file glob would pass vacuously if it ever stopped matching.** It
  matches six files today; asserting the wildcard result is non-empty would make
  a future path change fail loudly instead of silently passing.

### Credo custom checks are unverified (captured 2026-10-17)

`GIRI001` (`ModuleLength`, the 800-line rule) has never been observed firing — no
file has exceeded 800 lines since it was added, so it may be silently
non-functional. That suspicion is not idle: `GIRI002` (an `if`/`cond` ban) was
written during this session, loaded, had its `run/2` invoked for every engine
file, and still reported nothing — even with a hardcoded issue — and was withdrawn
rather than shipped. **Plant a 900-line module in `lib/` and confirm `GIRI001`
fails.** If it does not, the repo has been carrying a guard that guards nothing,
and the fix is worth finding before writing more custom checks.

### Refactorings and idiom homogenisation (captured 2026-10-17)

- **Every plan should end with a homogenisation pass**: docs stripped of
  source-language narration, idioms normalised to the current rules, and the
  plan's own Global Constraints re-checked against the code. This is a standing
  request — it will recur throughout the project — so it belongs in `AGENTS.md`
  as part of the definition of done rather than depending on each plan's author
  remembering it.
- **`Map` → `PlanarMap`**, with `mergeSimpleMany` → `replicate/2` and
  `mergeMap` → `weld/2`. `Map` is a built-in Elixir module, so our module cannot
  refer to itself by that name and a caller aliasing it shadows `Map.new/2` and
  friends. Nothing is in code yet — `Map` exists only in the docs — so this is a
  naming decision with no migration cost, and it should be settled in Plan 1b's
  plan rather than as a rename. The Java-to-Elixir name mapping belongs in one
  table in `reference/porting-notes/`, not in each module's docs.

### Small defects (captured 2026-10-17, from the Plan 1a review)

- **`Point.project/4` recomputes a `delta` its caller already has.** It calls
  `subtract(b, a)` again after `dist2_to_line/3` computed it. Harmless, but it is
  the same class of duplication the review flagged twice.
- The Plan 1a plan document lists `Point.TRUNC` among the constants to port,
  while Task 2's Produces list omits it and its only Java consumer is the
  `hashCode` the port replaces. A one-word plan edit, so the constraint does not
  read as violated.

## Closed

- **`Transform`'s raise paths untested** (Plan 1a review). Closed 2026-10-17: the
  error-tuple rework replaced the raises, and `invert!/1`,
  `reflect_through_line/2`'s degenerate case and `match_two_segments/4`'s
  zero-length case all gained tests.
- **`Polygon.new/1` did not say the closing edge is implicit** (Plan 1a review).
  Closed 2026-10-17: documented on `new/1` during the rework.

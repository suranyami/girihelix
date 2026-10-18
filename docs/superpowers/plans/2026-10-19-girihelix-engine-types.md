# Engine types implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retrofit Plan 1a's engine so malformed values cannot be represented. A
new opaque `Segment` and an opaque `Polygon` make six functions total, so they
return bare values instead of tuples. These conventions must be in place before
Plan 1b is written against them.

**Architecture:** Three tiers, chosen by what kind of guarantee is available:

- **Tier 1:** a structural invariant gets an `@opaque` type with a fallible
  `new/…`.
- **Tier 2:** a requirement that fits in a function-head pattern, so the compiler
  rejects a bad call site.
- **Tier 3:** a numeric property keeps its result tuple.

`Segment` is the primary vehicle. One constructor replaces the "two points turned
out to be one" failure in `Point`, `Transform` and `Intersect`.

**Tech Stack:** Elixir 1.20.3, ExUnit, dialyxir. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-17-girihelix-engine-types-design.md`.
Read it in full before Task 1. Where this plan departs from it, the departure
was measured and is listed under **Corrections to the spec**. Task 6 writes those
corrections back into the spec.

## Decisions settled at review (2026-10-19)

These answer the spec's five open questions. Do not reopen them.

1. **Retrofit now, before Plan 1b.** Plan 1b is written against the finished
   conventions, so the codebase never mixes two idioms.
2. **`Polygon`'s invariant is "at least 3 vertices" and nothing more.**
   Distinctness is the caller's responsibility, and the docs say so.
3. **`Transform.invert/1` stays public and returns error tuples**, alongside
   `invert!/1`.
4. **`Polygon.vertex/2` keeps its result tuple.** Indexing is partial by nature,
   and the function mirrors `Enum.fetch/2`.
5. **The conventions live in `AGENTS.md`** (already done) and in each plan's
   Global Constraints.

## Corrections to the spec

Both corrections were measured on 2026-10-19 against Elixir 1.20.3:

- **A `@spec` alone does not constrain callers.** Given `@spec f([integer(), ...])`
  over a body that does not constrain its argument, `f([])` compiled with **zero**
  diagnostics. The compiler checks call sites against types *inferred from
  patterns, guards and the body*. `def f([_ | _] = list)` gave
  `incompatible types given to …f/1`. **A tier-2 requirement must therefore be
  written in the function head.** The spec is still worth writing, because
  dialyzer reads it, but on its own it does nothing at compile time.
- **`Segment.new/2` cannot test `from === to`.** On OTP 27 and later,
  `0.0 === -0.0` is false, so `Point.new(0.0, 0.0)` and `Point.new(-0.0, 0.0)`
  would make a segment of length zero. Two points can also be distinct while
  their squared distance underflows to `0.0`, for example `(0, 0)` and
  `(1.0e-170, 0)`. Both cases bring back the division by zero that `Segment`
  exists to prevent. The invariant is therefore **`Point.dist2(from, to) > 0.0`**.
  That is exactly the determinant `Transform.match_line_segment/2` builds, and
  the divisor `Point.parameterization_on_line/2` uses.

Dialyzer's opacity check was also re-measured, and it holds. Passing a
`%Mod{…}` literal built outside `Mod` to a function typed `Mod.t()` gives
`call_without_opaque`.

## Global Constraints

- **Engine purity.** Every engine file lives under `lib/girihelix/engine/` and
  uses the standard library only. `test/girihelix/engine/architecture_test.exs`
  enforces this.
- **Hard rules (AGENTS.md):**
  - Branch on data with function heads and guards. No `if` or `cond` in engine
    code.
  - Non-bang public functions return `{:ok, _} | {:error, reason}`. Only a
    `name!` twin raises, and it raises `ArgumentError`.
  - `reason`s are atoms.
- **Opaque only where an invariant exists.** `Segment` and `Polygon` become
  `@opaque`. `Point` and `Transform` stay plain `@type` with total `new/…`.
- **No `%Segment{}` or `%Polygon{}` literal or pattern outside its own module.**
  Other modules use the accessors: `Segment.from/1`, `Segment.to/1`,
  `Polygon.points/1`. Tests may build structs only through `new/…`.
- **Reason atoms, exactly:** `:coincident_points` (`Segment`),
  `:too_few_vertices` and `:out_of_range` (`Polygon`), `:non_invertible`
  (`Transform`). `:degenerate_segment`, `:degenerate_line`, `:no_points` and
  `:empty_polygon` must not appear anywhere in `lib/` or `test/` when the plan
  is done.
- **`Intersect` keeps returning `nil`.** Parallel and off-segment are
  deliberately indistinguishable, so do not introduce an error tuple there.
- **Every commit passes `mix precommit.fast`** through the pre-commit hook. **Run
  `mix dialyzer` before every commit too, and require `Total errors: 0`.**
  Dialyzer is what enforces `@opaque`, so a task is not done while it reports
  anything.
- **Git:** `git commit` must be its own command. Never put a bare `-n` token in a
  command containing `git commit`. Commits are signed through 1Password; if
  signing fails, ask the user to unlock it, and never disable signing. Never add
  anything under `reference/`.
- **Never start or stop the dev server on :4000.** It belongs to the user.
- **Docs carry decisions, not source-language narration.** No new doc text
  mentions Java or Taprats. Where a divergence needs recording, record the
  decision and its reason. Task 6 strips what already exists.
- **Markdown** passes `markdownlint-cli2 --config ~/.markdownlint-cli2.jsonc`. The flag is required, because the CLI does not find that file on its own from this repo, and without it MD013 (off in the config) floods the output.

## Review Focus

Each line below has a test in the task that owns the code:

1. **Signed zero.** `Segment.new(Point.new(0.0, 0.0), Point.new(-0.0, 0.0))`
   must return `{:error, :coincident_points}`. A `===` guard accepts it. Owner:
   Task 1.
2. **Underflowing distance.** `Segment.new(Point.origin(), Point.new(1.0e-170, 0.0))`
   must be refused. `Segment.new(Point.origin(), Point.new(1.0e-150, 0.0))` must
   be accepted, and then `Transform.reflect_through_line/1` must not raise on
   it. Owners: Tasks 1 and 3.
3. **Three coincident vertices.** `Polygon.new/1` with the same point three times
   is accepted under decision 2. `area/1` must be `0.0`, `arc_length/2` must be
   `0.0`, and `contains_point?/2` must not crash. Owner: Task 5.
4. **A negative index.** `Polygon.vertex(p, -1)` must be
   `{:error, :out_of_range}`. `Enum.fetch/2` would quietly return the last vertex
   instead. Owner: Task 5.
5. **`nil` in `Point.center/1`.** The old function skipped `nil`, but the new one
   takes `[Point.t(), ...]`. `Point.center([Point.origin(), nil])` must raise
   `FunctionClauseError`, and the docs must say that `nil` is no longer
   accepted. It must not silently average. Owner: Task 2.

## Backlog triage

Each open item in `docs/backlog.md` has been triaged. Task 7 rewrites the file to
match.

| Item | Disposition |
| --- | --- |
| `Point.normalize/1` scaling branch unasserted | Task 2 |
| `Point.compare_to/2` sorting idiom | Carried to Plan 3, which has its first caller (first triage) |
| Untested `Point` accessors | Task 2 |
| Purity guard misses `Ecto` | Task 1 |
| Purity guard glob could pass vacuously | Task 1 |
| `GIRI001` never observed firing | Task 7 |
| Homogenisation pass in `AGENTS.md` | Closed: already in `AGENTS.md` as part of the definition of done |
| `Map` → `PlanarMap` | Carried to Plan 1b, as recorded (first triage) |
| `Point.project/4` recomputes `delta` | Task 2 |
| Plan 1a lists `Point.TRUNC` | Task 6 |

## File map

| File | Change |
| --- | --- |
| `lib/girihelix/engine/geometry/segment.ex` | **Create.** Opaque two-point segment with a fallible constructor. |
| `lib/girihelix/engine/geometry/point.ex` | `parameterization_on_line/2` becomes total over a `Segment`. `center/1` takes a non-empty list. Backlog fixes. |
| `lib/girihelix/engine/geometry/transform.ex` | `reflect_through_line/1` and `match_two_segments/2` become total over `Segment`s. |
| `lib/girihelix/engine/geometry/intersect.ex` | The four entry points take two `Segment`s. |
| `lib/girihelix/engine/geometry/polygon.ex` | Opaque. Fallible `new/1` and `new!/1`. `area/1` and `arc_length/2` become total. |
| `test/girihelix/engine/geometry/segment_test.exs` | **Create.** |
| `test/girihelix/engine/geometry/{point,transform,intersect,polygon}_test.exs` | Updated to the new signatures. |
| `test/girihelix/engine/architecture_test.exs` | Adds `Ecto`, and a non-empty file-glob assertion. |
| `AGENTS.md`, `mix.exs`, the spec, the Plan 1a plan, `docs/backlog.md` | Homogenisation and triage (Tasks 6 and 7). |

Task order follows the dependencies. Task 1 produces `Segment`, Tasks 2–4 consume
it, Task 5 is independent of it, and Tasks 6–7 sweep up afterwards.

---

### Task 1: `Segment`, and a purity guard that cannot pass vacuously

**Files:**

- Create: `lib/girihelix/engine/geometry/segment.ex`
- Create: `test/girihelix/engine/geometry/segment_test.exs`
- Modify: `test/girihelix/engine/architecture_test.exs`

**Interfaces:**

- Consumes: `Point.new/2`, `Point.origin/0`, `Point.dist2/2` (all unchanged).
- Produces, all in `Girihelix.Engine.Geometry.Segment`:
  - `@opaque t`, a struct with `@enforce_keys [:from, :to]`.
  - `@type reason :: :coincident_points`
  - `new(Point.t(), Point.t()) :: {:ok, t()} | {:error, :coincident_points}`
  - `new!(Point.t(), Point.t()) :: t()`, raising `ArgumentError`.
  - `from(t()) :: Point.t()`
  - `to(t()) :: Point.t()`

  Guaranteed: `Point.dist2(from(s), to(s)) > 0.0` for every `s`.

- [ ] **Step 1: Write the failing tests** in `segment_test.exs` (`use ExUnit.Case, async: true`):

```elixir
test "new/2 builds a segment from two distinct points" do
  assert {:ok, segment} = Segment.new(Point.new(1.0, 2.0), Point.new(3.0, 4.0))
  assert Segment.from(segment) == Point.new(1.0, 2.0)
  assert Segment.to(segment) == Point.new(3.0, 4.0)
end

test "new/2 refuses two equal points" do
  assert Segment.new(Point.new(1.0, 2.0), Point.new(1.0, 2.0)) == {:error, :coincident_points}
end

test "new/2 refuses points that differ only in the sign of zero" do
  assert Segment.new(Point.new(0.0, 0.0), Point.new(-0.0, 0.0)) == {:error, :coincident_points}
end

test "new/2 refuses distinct points whose squared distance underflows" do
  assert Segment.new(Point.origin(), Point.new(1.0e-170, 0.0)) == {:error, :coincident_points}
end

test "new/2 accepts a short segment whose squared length is still positive" do
  assert {:ok, _segment} = Segment.new(Point.origin(), Point.new(1.0e-150, 0.0))
end

test "new!/2 returns the segment or raises" do
  assert Segment.from(Segment.new!(Point.origin(), Point.unit_x())) == Point.origin()
  assert_raise ArgumentError, ~r/coincident_points/, fn -> Segment.new!(Point.origin(), Point.origin()) end
end
```

- [ ] **Step 2: Extend `architecture_test.exs`**

  - Add `{"Ecto", ~r/\bEcto\./}` to `@patterns`. Name `Ecto` in the moduledoc and
    in the failure message alongside Ash, Phoenix and the web layer.
  - Add `assert violations("Ecto.UUID.generate()") == ["Ecto"]` to the detector
    test.
  - Extract the wildcard into a private `engine_files/0`. Add this test:

```elixir
test "the guard scans the engine, so it cannot pass by matching nothing" do
  assert length(engine_files()) >= 7
  assert "lib/girihelix/engine/geometry/segment.ex" in engine_files()
end
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `mix test test/girihelix/engine/geometry/segment_test.exs test/girihelix/engine/architecture_test.exs`
Expected: FAIL. `Segment` is undefined, and `segment.ex` is not in `engine_files()`.

- [ ] **Step 4: Implement `Segment`** in `lib/girihelix/engine/geometry/segment.ex`

  - The invariant is `Point.dist2(from, to) > 0.0`, not `from === to`. See
    **Corrections to the spec**.
  - A guard cannot call `dist2/2`. Compute it in `new/2` and branch in a private
    function whose clauses carry `when squared_length == 0.0`.
  - `new!/2` matches the tuple and raises `ArgumentError` with a message that
    includes the reason atom.
  - The moduledoc states the guarantee in the caller's terms: the two endpoints
    are a positive distance apart, so every function taking a `Segment` can
    divide by its squared length.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test test/girihelix/engine/geometry/segment_test.exs test/girihelix/engine/architecture_test.exs`
Expected: PASS.

- [ ] **Step 6: Prove that opacity is enforced on `Segment`.** This is a probe and
  must not be committed.

  1. Create `lib/girihelix/zz_segment_forgery_probe.ex`, holding a module with
     `@spec forge() :: Point.t()` and
     `def forge, do: Segment.from(%Segment{from: Point.origin(), to: Point.origin()})`.
  2. Run `mix dialyzer`. Expected: `Total errors: 1` and `call_without_opaque`
     at the probe line.
  3. Delete that one file by its exact path:
     `rm lib/girihelix/zz_segment_forgery_probe.ex`.
  4. Run `git status --short`. Expected: the probe is absent.

  If dialyzer reports nothing, **stop and report**, because every tier-1
  guarantee in this plan depends on that check. Do not weaken the probe.

- [ ] **Step 7: Run the gates**

Run: `mix precommit.fast && mix dialyzer`
Expected: both pass, with `Total errors: 0`.

- [ ] **Step 8: Commit**

```bash
git add lib/girihelix/engine/geometry/segment.ex test/girihelix/engine/geometry/segment_test.exs test/girihelix/engine/architecture_test.exs
```

```bash
git commit -m "feat: add Segment, an opaque pair of distinct points"
```

### Task 2: `Point` — total `parameterization_on_line/2` and non-empty `center/1`

**Files:**

- Modify: `lib/girihelix/engine/geometry/point.ex`
- Test: `test/girihelix/engine/geometry/point_test.exs`

**Interfaces:**

- Consumes: `Segment.new!/2`, `Segment.from/1`, `Segment.to/1` (Task 1).
- Produces:
  - `Point.parameterization_on_line(t(), Segment.t()) :: float()`. Arity changes
    from 3 to 2, and the result is no longer a tuple.
  - `Point.center([t(), ...]) :: t()`. The result is no longer a tuple, and the
    function no longer skips `nil`.
  - Every other function keeps its signature.

- [ ] **Step 1: Rewrite the affected tests**

Replace the `parameterization_on_line` and `center` tests with:

```elixir
test "parameterization_on_line/2 returns the parameter unclamped" do
  segment = Segment.new!(Point.new(0.0, 0.0), Point.new(4.0, 0.0))

  assert Point.parameterization_on_line(Point.new(2.0, 0.0), segment) == 0.5
  assert Point.parameterization_on_line(Point.new(-4.0, 0.0), segment) == -1.0
  assert Point.parameterization_on_line(Point.new(8.0, 3.0), segment) == 2.0
end

test "center/1 averages a non-empty list" do
  assert Point.center([Point.new(0.0, 0.0), Point.new(4.0, 2.0)]) == Point.new(2.0, 1.0)
end

test "center/1 no longer accepts nil" do
  assert_raise FunctionClauseError, fn -> Point.center([Point.origin(), nil]) end
end

test "center/1 rejects an empty list at the call site, not at run time" do
  assert compile_diagnostics("Girihelix.Engine.Geometry.Point.center([])")
         |> Enum.any?(&(&1.message =~ "incompatible types given to Girihelix.Engine.Geometry.Point.center/1"))

  assert compile_diagnostics("Girihelix.Engine.Geometry.Point.center([Girihelix.Engine.Geometry.Point.origin()])") == []
end
```

`compile_diagnostics/1` is a private test helper. It wraps the expression in a
uniquely named module, compiles it with `Code.with_diagnostics/1` around
`Code.compile_string/1`, and returns the diagnostics. Name each module with
`System.unique_integer([:positive])`. The second assertion is the positive
control: the probe proves something only if a well-typed call stays silent.

Add the backlog tests:

```elixir
test "normalize/1 scales a non-unit vector to unit length" do
  # Not `== Point.new(0.6, 0.8)`: 3.0 * (1.0 / 5.0) is 0.6000000000000001.
  unit = Point.normalize(Point.new(3.0, 4.0))

  assert_in_delta unit.x, 0.6, 1.0e-15
  assert_in_delta unit.y, 0.8, 1.0e-15
  assert Point.normalize(Point.new(0.0, 2.0)) == Point.new(0.0, 1.0)
end

test "the accessors return their documented values" do
  assert Point.mag(Point.new(3.0, 4.0)) == 5.0
  assert Point.unit_x() == Point.new(1.0, 0.0)
  assert Point.unit_y() == Point.new(0.0, 1.0)
  assert Point.tolerance() == 1.0e-7
end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/girihelix/engine/geometry/point_test.exs`
Expected: FAIL. `parameterization_on_line/2` is undefined, `center/1` returns a
tuple, and the diagnostics probe finds nothing. The `normalize` and accessor
tests may already pass, because they cover existing behaviour.

- [ ] **Step 3: Implement the changes** in `point.ex`

  - `parameterization_on_line(%__MODULE__{} = p, segment)`: read the endpoints
    with `Segment.from/1` and `Segment.to/1`, then return
    `dot(subtract(p, a), delta) / dot(delta, delta)` directly. Delete the
    zero-length clause, which `Segment` has made unreachable.
  - `center([_ | _] = points)`: the head pattern **is** the tier-2 guarantee. Sum
    with `add/2` and scale by `1.0 / length(points)`. Delete the `nil` clause
    and `average/2`.
  - Update the `@spec`s to match.
  - Rewrite both docs:
    - `center/1`'s doc says that an empty list is rejected at compile time and
      that a `nil` element is no longer accepted.
  - Rewrite the moduledoc paragraph that lists "the two functions that can fail".
    No function in `Point` can fail any more, so say that instead.
  - Backlog fix: `project/4` stops recomputing `subtract(b, a)`.
    `dist2_to_line/3` already computes `delta`, so pass it down through
    `to_segment` and `project`.
  - Leave `recenter/2`'s `nil` handling as it is. It cannot fail and is out of
    scope.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/girihelix/engine/geometry/point_test.exs`
Expected: PASS.

- [ ] **Step 5: Gates**

Run: `mix precommit.fast && mix dialyzer`
Expected: both pass, with `Total errors: 0`.

- [ ] **Step 6: Commit**

```bash
git add lib/girihelix/engine/geometry/point.ex test/girihelix/engine/geometry/point_test.exs
```

```bash
git commit -m "refactor: make Point.parameterization_on_line and center total"
```

### Task 3: `Transform` — total reflection and segment matching

**Files:**

- Modify: `lib/girihelix/engine/geometry/transform.ex`
- Test: `test/girihelix/engine/geometry/transform_test.exs`

**Interfaces:**

- Consumes: `Segment.new!/2`, `Segment.from/1`, `Segment.to/1` (Task 1).
- Produces:
  - `Transform.reflect_through_line(Segment.t()) :: t()`. Arity changes from 2
    to 1, and the result is no longer a tuple.
  - `Transform.match_two_segments(Segment.t(), Segment.t()) :: t()`. Arity
    changes from 4 to 2, and the result is no longer a tuple.
  - `@type reason :: :non_invertible`
  - Unchanged:
    - `invert/1 :: {:ok, t()} | {:error, :non_invertible}`, and `invert!/1`.
    - `dist_from_inverted_zero/2`.
    - `match_line_segment(Point.t(), Point.t()) :: t()`.

- [ ] **Step 1: Rewrite the affected tests**

  - Port the existing reflection test and the segment-matching test to the new
    arities. Keep their assertions, and build the arguments with
    `Segment.new!/2`.
  - Delete `"reflect_through_line/2 reports coincident points as data"` and
    `"match_two_segments/4 reports a zero-length source segment as data"`. Both
    inputs are now unrepresentable, and `segment_test.exs` covers the refusal.
  - Add this test:

```elixir
test "reflect_through_line/1 is total on a very short segment" do
  segment = Segment.new!(Point.origin(), Point.new(1.0e-150, 0.0))
  reflection = Transform.reflect_through_line(segment)

  assert Transform.apply_to(reflection, Point.new(0.0, 1.0)) == Point.new(0.0, -1.0)
end

test "match_two_segments/2 never flips orientation" do
  source = Segment.new!(Point.new(0.0, 0.0), Point.new(1.0, 0.0))
  target = Segment.new!(Point.new(5.0, 5.0), Point.new(5.0, 7.0))

  refute Transform.flips(Transform.match_two_segments(source, target))
end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/girihelix/engine/geometry/transform_test.exs`
Expected: FAIL with `undefined function reflect_through_line/1`.

- [ ] **Step 3: Implement** in `transform.ex`

  - `reflect_through_line/1` composes `match_line_segment` on the segment's
    endpoints with `scale(1.0, -1.0)` and the inverse, in the order the current
    body uses. Use `invert!/1` for the inverse.
  - `match_two_segments/2` does the same with `invert!/1`.
  - Put a short comment at each call to `invert!/1`: the segment's endpoints are
    a positive distance apart, `match_line_segment`'s determinant is that
    squared distance, and so the inverse exists. This is a raise on an invariant
    no caller can break, which the hard rules permit.
  - Delete the `p === q` clause and `:degenerate_line`.
  - Fix two docs:
    - The moduledoc's "Failures are data" paragraph. Only `invert/1` and
      `dist_from_inverted_zero/2` can fail now.
    - `dist_from_zero/2`'s doc, which wrongly says it can report
      `{:error, :non_invertible}`. It is total.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/girihelix/engine/geometry/transform_test.exs`
Expected: PASS.

- [ ] **Step 5: Gates**

Run: `mix precommit.fast && mix dialyzer`
Expected: both pass, with `Total errors: 0`.

- [ ] **Step 6: Commit**

```bash
git add lib/girihelix/engine/geometry/transform.ex test/girihelix/engine/geometry/transform_test.exs
```

```bash
git commit -m "refactor: make reflection and segment matching total over Segment"
```

### Task 4: `Intersect` over `Segment`s

**Files:**

- Modify: `lib/girihelix/engine/geometry/intersect.ex`
- Test: `test/girihelix/engine/geometry/intersect_test.exs`

**Interfaces:**

- Consumes: `Segment.new!/2`, `Segment.from/1`, `Segment.to/1` (Task 1).
- Produces. Each changes from arity 4 to arity 2, and `nil` remains the only
  failure value:
  - `Intersect.get_intersection_params(Segment.t(), Segment.t()) :: {float(), float()} | nil`
  - `Intersect.get_intersection(Segment.t(), Segment.t()) :: Point.t() | nil`
  - `Intersect.get_near_intersection(Segment.t(), Segment.t()) :: Point.t() | nil`
  - `Intersect.get_true_intersection(Segment.t(), Segment.t()) :: Point.t() | nil`

  `stay_on_segments/1` and `stay_near_segments/1` are unchanged. The first
  argument is still the segment the returned position lies on.

- [ ] **Step 1: Port the tests**

  - Change `crossing/0` to return `{Segment.new!(…), Segment.new!(…)}`, with the
    same four points.
  - Add a private `segment(x1, y1, x2, y2)` helper that builds through
    `Segment.new!/2`.
  - Rewrite every call to the two-argument form, keeping every expected value.
  - Delete `"get_intersection_params/4 returns nil for a zero-length segment"`.
    That input is now unrepresentable.
  - Remove the zero-length case from the Review Focus 4 test, which pins that
    the `nil` reasons are indistinguishable. Leave its parallel and off-segment
    cases.
  - Rename every test's `/4` to `/2`.

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/girihelix/engine/geometry/intersect_test.exs`
Expected: FAIL with `undefined function get_intersection_params/2`.

- [ ] **Step 3: Implement**

  - Each public entry point reads its two segments' endpoints through
    `Segment.from/1` and `Segment.to/1`, then hands off to the existing private
    arithmetic. The O'Rourke expressions stay transcribed exactly. This task
    changes signatures only.
  - Rewrite the docs:
    - The moduledoc says `nil` covers parallel and off-segment, and no longer
      mentions zero length.
    - `get_intersection_params/2` loses the sentence about a zero-length
      direction vector.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/girihelix/engine/geometry/intersect_test.exs`
Expected: PASS with the same expected values as before.

- [ ] **Step 5: Gates**

Run: `mix precommit.fast && mix dialyzer`
Expected: both pass, with `Total errors: 0`.

- [ ] **Step 6: Commit**

```bash
git add lib/girihelix/engine/geometry/intersect.ex test/girihelix/engine/geometry/intersect_test.exs
```

```bash
git commit -m "refactor: take Segments in Intersect, removing the zero-length case"
```

### Task 5: `Polygon` — opaque, at least three vertices, total measures

**Files:**

- Modify: `lib/girihelix/engine/geometry/polygon.ex`
- Test: `test/girihelix/engine/geometry/polygon_test.exs`

**Interfaces:**

- Consumes: `Point` and `Transform`, both unchanged by this task.
- Produces:
  - `@opaque t`
  - `@type reason :: :too_few_vertices | :out_of_range`
  - `Polygon.new([Point.t()]) :: {:ok, t()} | {:error, :too_few_vertices}`
  - `Polygon.new!([Point.t()]) :: t()`, raising `ArgumentError`.
  - `Polygon.area(t()) :: float()`. No longer a tuple.
  - `Polygon.arc_length(t(), boolean()) :: float()`. No longer a tuple.
  - `Polygon.vertex(t(), integer()) :: {:ok, Point.t()} | {:error, :out_of_range}`.
    Kept per decision 4. A negative index is now out of range.
  - `Polygon.num_vertices(t()) :: pos_integer()`
  - Unchanged: `points/1`, `apply_transform/2`, `contains_point?/2`, and
    `point_in_poly/2`, which still accepts `[]`.

  Guaranteed: `length(points(p)) >= 3`. Vertex distinctness is **not**
  guaranteed (decision 2).

- [ ] **Step 1: Rewrite the tests**

  - `unit_square/0`, and every other polygon built in the file, uses
    `Polygon.new!/1`.
  - Delete these tests, whose inputs are now unrepresentable:
    - `area/1` of an empty polygon.
    - The two `arc_length/2` empty and single-point tests.
    - `"contains_point?/2 is false for an empty polygon"`.
  - Change every `{:ok, value}` expectation on `area/1` and `arc_length/2` to the
    bare value.
  - Add:

```elixir
test "new/1 refuses fewer than three vertices" do
  assert Polygon.new([]) == {:error, :too_few_vertices}
  assert Polygon.new([Point.origin(), Point.unit_x()]) == {:error, :too_few_vertices}
  assert {:ok, _triangle} = Polygon.new([Point.origin(), Point.unit_x(), Point.unit_y()])
end

test "new!/1 raises on fewer than three vertices" do
  assert_raise ArgumentError, ~r/too_few_vertices/, fn -> Polygon.new!([Point.origin()]) end
end

test "arc_length/2 measures a triangle open and closed" do
  triangle = Polygon.new!([Point.new(0.0, 0.0), Point.new(4.0, 0.0), Point.new(0.0, 3.0)])

  assert Polygon.arc_length(triangle, false) == 9.0
  assert Polygon.arc_length(triangle, true) == 12.0
end

# Review Focus 3: distinctness is the caller's responsibility, so a polygon of
# three coincident vertices is representable and must measure as nothing.
test "three coincident vertices make a polygon with no area or length" do
  point = Point.new(2.0, 3.0)
  collapsed = Polygon.new!([point, point, point])

  assert Polygon.area(collapsed) == 0.0
  assert Polygon.arc_length(collapsed, true) == 0.0
  refute Polygon.contains_point?(collapsed, point)
end

# Review Focus 4: Enum.fetch/2 counts from the end on a negative index.
test "vertex/2 treats a negative index as out of range" do
  assert Polygon.vertex(unit_square(), -1) == {:error, :out_of_range}
end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/girihelix/engine/geometry/polygon_test.exs`
Expected: FAIL. `new!/1` is undefined, `new/1` returns a bare struct, and
`vertex(_, -1)` returns `{:ok, _}`.

- [ ] **Step 3: Implement**

  - `@opaque t :: %__MODULE__{points: [Point.t(), ...]}`
  - `new([_, _, _ | _] = points)` returns `{:ok, %__MODULE__{points: points}}`. A
    second clause, `new(points) when is_list(points)`, returns
    `{:error, :too_few_vertices}`.
  - `new!/1` matches the tuple, the same way `Segment.new!/2` does.
  - `vertex/2`:
    - A clause guarded `when is_integer(index) and index >= 0` delegates to
      `Enum.fetch/2`.
    - A final clause returns `{:error, :out_of_range}`.
    - Replace the `case` on `Enum.fetch/2`'s `:error` with a private
      multi-clause function, as the hard rules require.
  - `area/1` and `arc_length/2` lose their empty-list clauses and return bare
    floats. `contains_point?/2` loses its empty clause.
    `point_in_poly([], _)` stays, because it is public over a plain list.
  - Rewrite the docs:
    - `area/1`, `arc_length/2` and `contains_point?/2` lose their sentences about
      empty polygons.
    - `new/1`'s doc states the "at least three" invariant, and says that
      distinctness is the caller's job.
    - The moduledoc says "a polygon has at least three vertices" in place of the
      graph-node comparison that names `Map`. That comparison referred to a
      module that does not exist yet, under a name being retired (`PlanarMap`,
      Plan 1b).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/girihelix/engine/geometry/polygon_test.exs`
Expected: PASS.

- [ ] **Step 5: Gates, and one opacity probe**

Run: `mix precommit.fast && mix dialyzer`
Expected: both pass, with `Total errors: 0`.

Repeat Task 1 Step 6 for `Polygon`. The probe file is
`lib/girihelix/zz_polygon_forgery_probe.ex`, holding
`def forge, do: Polygon.points(%Polygon{points: []})`. Expect
`call_without_opaque`. Delete the file by its exact path, then confirm
`git status --short` does not list it.

- [ ] **Step 6: Commit**

```bash
git add lib/girihelix/engine/geometry/polygon.ex test/girihelix/engine/geometry/polygon_test.exs
```

```bash
git commit -m "refactor: make Polygon opaque with at least three vertices"
```

### Task 6: Homogenisation pass

This is the standing definition-of-done pass from `AGENTS.md`, over everything
this plan touched and over the documents that state the toolchain facts it
corrected.

**Files:**

- Modify: every file under `lib/girihelix/engine/geometry/`
- Modify: `AGENTS.md`, above `<!-- usage-rules-start -->` only
- Modify: `mix.exs`, the comment above the `precommit` alias
- Modify: `docs/superpowers/specs/2026-10-17-girihelix-engine-types-design.md`
- Modify: `docs/superpowers/plans/2026-10-16-girihelix-plan-1a-engine-substrate.md`
- Modify, only if a fact would otherwise be lost: `docs/algorithm-analysis.md`

**Interfaces:** none. Code behaviour must not change in this task.

- [ ] **Step 1: Strip source-language narration from the engine**

  Find the targets:

  ```bash
  grep -rnE "Java|Taprats|Ported from" lib/girihelix/engine
  ```

  For each hit, which may be in a moduledoc, a doc or a comment:

  - **If it only narrates** what the source does, delete it.
  - **If it records a decision**, rewrite it as the decision and its reason, in
    the caller's terms. Example: "the boundary is half-open, so the lower and left
    edges count as inside".
  - **Before deleting a behavioural fact**, check that `docs/algorithm-analysis.md`
    records it. Facts at risk include `Loose`'s omitted members, `sweep/3`'s
    iteration and `point_in_poly/2`'s slice bug. Where the analysis document does
    not record a fact, add it to that module's section there first.

  Citations of the published algorithms (O'Rourke; Bob Stein) are attributions,
  not narration, so they stay.

- [ ] **Step 2: Verify that the engine is clean**

  Run both commands:

  ```bash
  grep -rnE "Java|Taprats|Ported from" lib/girihelix/engine
  ```

  ```bash
  grep -rnE ":degenerate_segment|:degenerate_line|:no_points|:empty_polygon" lib test
  ```

  Expected: both print nothing.

  Do not chain any further step behind these with `&&`. `grep` exits 1 when it
  finds nothing, which is the success case here.

- [ ] **Step 3: Correct the toolchain claims**

  - **`AGENTS.md`, "Gates" bullet:** Dialyzer is in `precommit` (the pre-push
    gate), not "in neither gate". Say so.
  - **`AGENTS.md`, hard-rules bullet:**
    - Replace "Enforced mechanically by the `GIRI002` Credo check" with a
      statement that the rule is enforced by review.
    - Say why: `GIRI002` was withdrawn because it reported nothing, as recorded
      in `.credo.exs`.
  - **`AGENTS.md`, "Dialyzer is load-bearing" bullet, and the `mix.exs` comment
    above `precommit`:** both say the compiler checks call sites against
    `@spec`. Replace that with the measured fact:
    - The compiler checks call sites against types inferred from patterns,
      guards and the body.
    - A `@spec` alone constrains nothing at compile time.
    - So a tier-2 requirement must be written in the function head
      (`def center([_ | _] = points)`).

    Keep the rest of each paragraph.

- [ ] **Step 4: Bring the spec up to date**

  - Set **Status** to: approved 2026-10-18, implemented by
    `docs/superpowers/plans/2026-10-19-girihelix-engine-types.md`.
  - Rewrite the compiler row of the toolchain table, as in Step 3, dated
    2026-10-19.
  - Change the Tier 2 example to `def center([_ | _] = points)`, and say that the
    head carries the guarantee.
  - Change the Tier 1 `Segment` example from the `from === to` guard to the
    `dist2 > 0.0` invariant. Give the signed-zero and underflow reasons in one
    sentence each.
  - Replace **Open questions for review** with **Resolved at review**, listing the
    five decisions from this plan's header.
  - Update the arities in the "Applied to the engine" table to the new ones:
    `reflect_through_line/1`, `match_two_segments/2`,
    `parameterization_on_line/2`, and the four `Intersect` functions at `/2`.

- [ ] **Step 5: Fix Plan 1a's constraint**

  In `docs/superpowers/plans/2026-10-16-girihelix-plan-1a-engine-substrate.md`,
  Global Constraints:

  - Remove `` `Point.TRUNC = 1.0e7` `` from the constants list.
  - Add `Point.TRUNC` to the "do not port" sentence, with the reason: its only
    consumer is the hash function, which the port replaces.

- [ ] **Step 6: Lint and run the full gate**

  ```bash
  markdownlint-cli2 --config ~/.markdownlint-cli2.jsonc AGENTS.md docs/superpowers/specs/2026-10-17-girihelix-engine-types-design.md docs/superpowers/plans/2026-10-16-girihelix-plan-1a-engine-substrate.md docs/algorithm-analysis.md
  ```

  Expected: `0 error(s)`. If a file already had lint errors before this task,
  fix only the lines this task changed, and report the rest.

  ```bash
  mix precommit
  ```

  Expected: passes, with dialyzer reporting `Total errors: 0` and the whole
  suite green under coverage.

- [ ] **Step 7: Commit**

  Stage the files this task changed by name, never with `git add -A`:

  ```bash
  git add lib/girihelix/engine AGENTS.md mix.exs docs/superpowers docs/algorithm-analysis.md
  ```

  ```bash
  git commit -m "docs: homogenise the engine docs and correct the toolchain claims"
  ```

### Task 7: Prove `GIRI001` fires, then rewrite the backlog

**Files:**

- Probe only, never committed: `lib/girihelix/zz_long_probe.ex`
- Modify: `docs/backlog.md`
- Modify, only if `GIRI001` turns out to be silent: `.credo.exs`, the NOTE
  comment above `ModuleLength`

**Interfaces:** none.

- [ ] **Step 1: Plant a file that parses and is over 800 lines**

  The file is `lib/girihelix/zz_long_probe.ex`. It holds
  `defmodule Girihelix.ZzLongProbe do`, a `@moduledoc false`, 900 lines of
  `def fN, do: N`, and `end`. Generate it with a short script.

  Confirm it parses:

  ```bash
  mix format --check-formatted lib/girihelix/zz_long_probe.ex
  ```

  Expected: exits 0. If it does not, run `mix format` on the probe and re-check.
  A probe that does not parse proves nothing (see the handoff anti-pattern).

- [ ] **Step 2: Run Credo on it**

  ```bash
  mix credo -a --strict lib/girihelix/zz_long_probe.ex
  ```

  Expected: an issue reading `Module is 90… lines long (max 800)`.

- [ ] **Step 3: Remove the probe**

  ```bash
  rm lib/girihelix/zz_long_probe.ex
  ```

  ```bash
  git status --short
  ```

  Expected: no probe file listed.

- [ ] **Step 4: Record the outcome**

  - **If it fired:** close the backlog item, dated 2026-10-19, with the
    observation.
  - **If it was silent:**
    - Keep the item open and record exactly what was run and seen.
    - Extend `.credo.exs`'s NOTE to say `GIRI001` shares `GIRI002`'s symptom.
    - **Stop and report to the user.** Deciding whether to debug Credo's issue
      pipeline or to withdraw the check is their call, not this plan's.

- [ ] **Step 5: Rewrite `docs/backlog.md` to match this plan's triage table**

  - Move each item that Tasks 1, 2, 6 and 7 resolved to **Closed**. Date each
    one 2026-10-19 and name the commit or task.
  - Close the `AGENTS.md` homogenisation item, because `AGENTS.md` already holds
    that requirement.
  - Mark `compare_to/2` and `Map` → `PlanarMap` "triaged once (2026-10-19)".
    That way the file's "two triages" rule can be applied next time.

  Then lint it:

  ```bash
  markdownlint-cli2 --config ~/.markdownlint-cli2.jsonc docs/backlog.md
  ```

  Expected: `0 error(s)`.

- [ ] **Step 6: Commit**

  ```bash
  git add docs/backlog.md .credo.exs
  ```

  ```bash
  git commit -m "docs: triage the backlog against the engine types plan"
  ```

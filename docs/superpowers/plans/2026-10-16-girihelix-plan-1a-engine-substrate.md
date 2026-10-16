# Engine substrate implementation plan (Plan 1a)

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure-Elixir geometry substrate — the step/trace mechanism and
the value types everything else is written in terms of — with no Ash, no Phoenix
and no database.

**Architecture:** Every algorithm in the engine is authored as a labelled
sequence of pure step functions over a state, run by one interpreter
(`Girihelix.Engine.Steps`) that retains every frame. Each algorithm therefore has
two entry points over a single implementation: a plain function, and a
`steps/1` that the workbench renders as a step-through. This plan builds that
mechanism first, so no algorithm is ever written twice, then the value types
`Loose`, `Point`, `Transform`, `Intersect` and `Polygon`.

**Tech Stack:** Elixir 1.20.3, OTP 29, ExUnit. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-16-girihelix-workbench-design.md` (the
step model and exhibit contract) and `docs/algorithm-analysis.md` (the porting
specification). Per-module detail, including exact arithmetic and the
source's own comments, is in `reference/porting-notes/geometry.md` — local-only
and git-ignored. Read the relevant section of it before each task; this plan
quotes what you need but the notes are more complete.

## Global Constraints

- **Engine purity.** Every file in this plan lives under
  `lib/girihelix/engine/`. No engine file may reference `Ash`, `Phoenix`,
  `Phoenix.LiveView` or `GirihelixWeb`. A guard test enforces this and is written
  in Task 1, before any geometry exists.
- **Every algorithm is a step sequence.** The public shape is always a `steps/…`
  function returning `[Step.t()]`, plus a plain function built from
  `Steps.run!/2` and `Steps.final/1`. A test pins the two together.
- **Port from Taprats 1.1.12.** `reference/1.1.12/src/` is the source of truth.
  Never port from `reference/0.3/`; it is a comparison baseline only.
- **Constants verbatim, dead code omitted.** `Loose.TOL = 1e-7`,
  `Loose.TOL2 = 1e-10`; `Point.TOLERANCE = 1.0e-7`,
  `Point.TOLERANCE2 = TOLERANCE * TOLERANCE` (= 1e-14), `Point.TRUNC = 1.0e7`.
  `Loose.NEAR_TOL`, `Loose.lessThan/2` and `Loose.greaterThan/2` are declared in
  Java and referenced nowhere — do not port them.
- **Immutability.** The Java mutates in place; every `D`-suffixed method
  (`addD`, `scaleD`, `normalizeD`, `perpD`, `convexSumD`, `applyD`, `composeD`,
  `invertD`) is dropped. Every operation returns a new value.
- **A parameter pair is not a point.** `Intersect.getIntersectionParams` returns
  `s` and `t` packed into a `Point` in Java. Represent it as `{s, t}` in Elixir
  and never as a `Point` — `Point`'s distance and equality operations are
  meaningless on it.
- **File length ≤ 800 lines** (credo `GIRI001`), **line length ≤ 120**
  (`Credo.Check.Readability.MaxLineLength`). Both fire in `mix credo -a --strict`,
  which runs on every commit.
- **Testing.** Pure `ExUnit.Case, async: true`. No `DataCase`, no sandbox, no
  database. Tests live under `test/girihelix/engine/`.
- **Gates.** `mix precommit.fast` (compile-as-errors, format, credo) must pass
  before each commit. `mix precommit` (adds sobelow and the suite under coverage)
  must pass before any push. Commits are SSH-signed; if a commit fails with a
  1Password agent error, ask the user to unlock — never disable signing.
- **`git commit` must be its own command.** A bare `-n` token anywhere in a
  command containing `git commit` trips the `block-no-verify` hook.

## Review Focus

The spec is a vision document: it says what the software must do, not everything
it will meet. These are the five input classes most likely to bite someone using
this code, each pinned by a test in the task that owns it.

1. **Degenerate segments pass silently.** `Point.dist2_to_line/3` projects onto
   the segment by dividing by its squared length. A zero-length segment makes that
   parameter `NaN` in Java; every comparison against `NaN` is false, so it falls
   through to *returning the distance to the second endpoint*. Elixir's `/` raises
   on a zero divisor instead of yielding `NaN`, so the port needs an explicit
   guard to reproduce that same value — which means a caller measuring against a
   degenerate segment still gets a plausible number rather than an error.
   `Point.parameterization_on_line/3` has the same degenerate input and raises
   instead. Pinned in Task 2.
2. **The two tolerance regimes disagree.** `Point.equals/2` tests a squared
   distance below `1e-14`; `Loose.equals/2` tests below `1e-10`. Two functions
   both spelled "equals" differ by 100× in linear terms, and different callers in
   the Java use each. A user who assumes they agree gets different answers from
   the same two points. Pinned in Tasks 2 and 3.
3. **Tolerant comparison is not a total order.** `Point.compare_to/2` orders by
   squared magnitude with a `1e-14` band, so points at nearly the same radius
   compare equal, and the relation is not transitive. A user sorting a list of
   points expects a stable, transitive order and can get neither. Pinned in
   Task 2.
4. **Degenerate segments are indistinguishable from parallel ones.**
   `Intersect` returns `nil` for parallel segments, for a crossing outside the
   segment, and for a zero-length segment, with no way for the caller to tell
   which. A user intersecting two collinear overlapping segments expects a
   crossing and gets `nil`, and cannot discover why. Pinned in Task 5.
5. **Empty and single-element collections.** `Polygon.area/1` takes a remainder
   modulo the vertex count, so an empty polygon raises `ArithmeticException` in
   Java; `arc_length(closed: true)` indexes `-1`. These are the inputs a user
   reaches first when a construction legitimately produces nothing. Pinned in
   Task 6.

## File Structure

| File | Responsibility |
| --- | --- |
| `lib/girihelix/engine/steps.ex` | `Step`, `Frame`, `Failure`, the interpreter and the `step/4` macro. One responsibility: run a sequence and retain frames. |
| `lib/girihelix/engine/geometry/loose.ex` | The fuzzy-comparison module. Tolerances live here and nowhere else. |
| `lib/girihelix/engine/geometry/point.ex` | The `Point` value type and its arithmetic. |
| `lib/girihelix/engine/geometry/transform.ex` | The affine transform: factories, composition, inversion, segment matching. |
| `lib/girihelix/engine/geometry/intersect.ex` | Segment-to-segment crossing. Stateless. |
| `lib/girihelix/engine/geometry/polygon.ex` | A polygon as a point list, plus area, arc length and the point-in-polygon test. |
| `test/girihelix/engine/architecture_test.exs` | The purity guard. |
| `test/girihelix/engine/steps_test.exs` | Interpreter, failure and macro behaviour. |
| `test/girihelix/engine/geometry/*_test.exs` | One test file per module. |

Not in this plan: `Vertex`, `Edge`, `Map`, `Faces`, `FillRegion` and `Rect`.
Those are Plan 1b, and deliberately separate — the planar map holds the two
hardest algorithms in the port and deserves its own review gate.

---

### Task 1: The step interpreter, and the purity guard

**Files:**

- Create: `lib/girihelix/engine/steps.ex`
- Create: `test/girihelix/engine/steps_test.exs`
- Create: `test/girihelix/engine/architecture_test.exs`

**Interfaces:**

- Consumes: nothing.
- Produces: `Girihelix.Engine.Steps.Step` with fields `:id`, `:label`, `:doc`,
  `:run`, `:source`; `Steps.Frame` with `:index`, `:step`, `:state`;
  `Steps.Failure` with `:frames`, `:index`, `:step`, `:exception`,
  `:stacktrace`; the macro `Steps.step/4`; and the functions `Steps.run/3`
  returning `{:ok, [Frame.t()]} | {:error, Failure.t()}`, `Steps.run!/3`
  returning `[Frame.t()]`, `Steps.final/1` returning the last state, and
  `Steps.at/2` returning `Frame.t() | nil`.

Every later task in this plan and in Plans 1b–7 uses these names and shapes. The
convention they establish: **frame zero is the initial state**, before any step
has run, and `max_frames` caps the total number of frames returned.

- [ ] **Step 1: Write the failing test**

```elixir
# test/girihelix/engine/steps_test.exs
defmodule Girihelix.Engine.StepsTest do
  use ExUnit.Case, async: true

  import Girihelix.Engine.Steps

  alias Girihelix.Engine.Steps
  alias Girihelix.Engine.Steps.Failure

  @this_file __ENV__.file

  defp steps do
    [
      step(:double, "double", "multiply the counter by two", fn s ->
        Map.update!(s, :n, &(&1 * 2))
      end),
      step(:add_one, "add one", "add one to the counter", fn s ->
        Map.update!(s, :n, &(&1 + 1))
      end)
    ]
  end

  defp boom do
    step(:boom, "boom", "always raises", fn _ -> raise "nope" end)
  end

  test "run/3 returns one frame per step, plus frame zero" do
    assert {:ok, frames} = Steps.run(steps(), %{n: 1})
    assert length(frames) == 3
    assert Enum.map(frames, & &1.index) == [0, 1, 2]
  end

  test "frame zero carries the initial state and no step" do
    assert {:ok, [first | _]} = Steps.run(steps(), %{n: 1})
    assert first.step == nil
    assert first.state == %{n: 1}
  end

  test "final/1 is the state after the last step" do
    assert {:ok, frames} = Steps.run(steps(), %{n: 1})
    assert Steps.final(frames) == %{n: 3}
  end

  test "at/2 indexes a frame and returns nil past the end" do
    assert {:ok, frames} = Steps.run(steps(), %{n: 1})
    assert Steps.at(frames, 1).step.id == :double
    assert Steps.at(frames, 2).state == %{n: 3}
    assert Steps.at(frames, 99) == nil
  end

  test "a raising step returns a Failure naming the step, keeping prior frames" do
    assert {:error, %Failure{} = failure} =
             Steps.run(steps() ++ [boom()], %{n: 1})

    assert failure.step.id == :boom
    assert failure.index == 3
    assert length(failure.frames) == 3
    assert Exception.message(failure.exception) == "nope"
    assert is_list(failure.stacktrace)
  end

  test "run!/3 re-raises the original exception unchanged" do
    assert_raise RuntimeError, "nope", fn -> Steps.run!([boom()], %{n: 1}) end
  end

  test "step/4 records the file and line of its call site" do
    assert {:ok, [_, frame | _]} = Steps.run(steps(), %{n: 1})
    assert {file, line} = frame.step.source
    assert file == @this_file
    assert is_integer(line) and line > 0
  end

  test "max_frames caps the frames returned, including frame zero" do
    ticks = List.duplicate(step(:tick, "tick", "no-op", &Function.identity/1), 10)
    assert {:ok, frames} = Steps.run(ticks, %{n: 1}, max_frames: 4)
    assert length(frames) == 4
    assert Steps.final(frames) == %{n: 1}
  end
end
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `mix test test/girihelix/engine/steps_test.exs`

Expected: FAIL — `module Girihelix.Engine.Steps is not available` and
`cannot import Girihelix.Engine.Steps.step/4`.

- [ ] **Step 3: Write the minimal implementation**

```elixir
# lib/girihelix/engine/steps.ex
defmodule Girihelix.Engine.Steps do
  @moduledoc """
  Runs a labelled sequence of pure steps over a state, retaining every frame.

  Every algorithm in the engine is authored as such a sequence, which gives it
  two entry points over one implementation: a `steps/…` function returning the
  sequence, and a plain function that runs it and takes the last state. The
  workbench renders the frames; nothing else needs them.
  """

  defmodule Step do
    @moduledoc "One clause of an algorithm: a pure function from state to state."
    @enforce_keys [:id, :label, :doc, :run, :source]
    defstruct [:id, :label, :doc, :run, :source]

    @type t :: %__MODULE__{
            id: atom(),
            label: String.t(),
            doc: String.t(),
            run: (term() -> term()),
            source: {String.t(), non_neg_integer()}
          }
  end

  defmodule Frame do
    @moduledoc "The state after one step, or the initial state when `step` is nil."
    @enforce_keys [:index, :step, :state]
    defstruct [:index, :step, :state]

    @type t :: %__MODULE__{index: non_neg_integer(), step: Step.t() | nil, state: term()}
  end

  defmodule Failure do
    @moduledoc "A step that raised, with every frame that did build."
    @enforce_keys [:frames, :index, :step, :exception, :stacktrace]
    defstruct [:frames, :index, :step, :exception, :stacktrace]

    @type t :: %__MODULE__{
            frames: [Frame.t()],
            index: non_neg_integer(),
            step: Step.t(),
            exception: Exception.t(),
            stacktrace: list()
          }
  end

  @doc """
  Builds a step, recording the file and line of the call site.

  The captured location is what lets the workbench highlight the code that
  produced a frame, without searching for the module on disk.
  """
  defmacro step(id, label, doc, run) do
    quote do
      %Girihelix.Engine.Steps.Step{
        id: unquote(id),
        label: unquote(label),
        doc: unquote(doc),
        run: unquote(run),
        source: {unquote(__CALLER__.file), unquote(__CALLER__.line)}
      }
    end
  end

  @doc """
  Runs `steps` from `initial`, returning every frame.

  Frame zero is `initial` itself, with a nil step. Options:

    * `:max_frames` — cap on the frames returned, frame zero included. Defaults
      to `:infinity`.
  """
  @spec run([Step.t()], term(), keyword()) :: {:ok, [Frame.t()]} | {:error, Failure.t()}
  def run(steps, initial, opts \\ []) do
    max = Keyword.get(opts, :max_frames, :infinity)
    zero = %Frame{index: 0, step: nil, state: initial}
    advance(steps, zero, [zero], max)
  end

  @doc "Runs `steps` and returns the frames, re-raising the original exception."
  @spec run!([Step.t()], term(), keyword()) :: [Frame.t()]
  def run!(steps, initial, opts \\ []) do
    case run(steps, initial, opts) do
      {:ok, frames} -> frames
      {:error, %Failure{exception: exception, stacktrace: stacktrace}} ->
        reraise(exception, stacktrace)
    end
  end

  @doc "The state a plain caller wants: the last frame's state."
  @spec final([Frame.t()]) :: term()
  def final(frames), do: List.last(frames).state

  @doc "The frame at `index`, or nil when out of range."
  @spec at([Frame.t()], non_neg_integer()) :: Frame.t() | nil
  def at(frames, index), do: Enum.at(frames, index)

  defp advance([], _previous, acc, _max), do: {:ok, Enum.reverse(acc)}

  defp advance([step | rest], previous, acc, max) do
    index = previous.index + 1

    if at_capacity?(index, max) do
      {:ok, Enum.reverse(acc)}
    else
      run_one(step, rest, previous, acc, max, index)
    end
  end

  defp run_one(step, rest, previous, acc, max, index) do
    state = step.run.(previous.state)
    frame = %Frame{index: index, step: step, state: state}
    advance(rest, frame, [frame | acc], max)
  rescue
    exception ->
      {:error,
       %Failure{
         frames: Enum.reverse(acc),
         index: index,
         step: step,
         exception: exception,
         stacktrace: __STACKTRACE__
       }}
  end

  defp at_capacity?(_index, :infinity), do: false
  defp at_capacity?(index, max), do: index >= max
end
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `mix test test/girihelix/engine/steps_test.exs`

Expected: PASS, 8 tests.

- [ ] **Step 5: Write the purity guard test**

This is the test behind the engine's first architecture rule. It goes in first,
before any geometry exists, because its whole purpose is to stop the boundary
eroding later.

```elixir
# test/girihelix/engine/architecture_test.exs
defmodule Girihelix.Engine.ArchitectureTest do
  @moduledoc """
  Guards the rule that keeps the engine portable and testable: it may not
  reference Ash, Phoenix or the web layer.
  """

  use ExUnit.Case, async: true

  @engine_root "lib/girihelix/engine"

  @patterns [
    {"Ash", ~r/\bAsh\./},
    {"Phoenix", ~r/\bPhoenix\./},
    {"GirihelixWeb", ~r/\bGirihelixWeb\b/}
  ]

  test "every engine source file is free of Ash, Phoenix and web references" do
    offenders =
      @engine_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> violations()
        |> Enum.map(&"#{path} references #{&1}")
      end)

    assert offenders == [],
           """
           The engine must stay pure. These files break the boundary:

           #{Enum.join(offenders, "\n")}

           Ash resources may hold engine values; the engine may never hold Ash.
           The same goes for Phoenix and the web layer.
           """
  end

  test "the detector finds a violation, so the guard cannot pass vacuously" do
    assert violations("defmodule X do\n  alias Ash.Foo\nend") == ["Ash"]
    assert violations("Phoenix.LiveView.socket()") == ["Phoenix"]
    assert violations("alias GirihelixWeb.Endpoint") == ["GirihelixWeb"]
    assert violations("defmodule Clean do\nend") == []
  end

  defp violations(source) do
    for {name, pattern} <- @patterns, Regex.match?(pattern, source), do: name
  end
end
```

- [ ] **Step 6: Run the guard and confirm it actually guards**

Run: `mix test test/girihelix/engine/architecture_test.exs`

Expected: PASS, 2 tests.

Then confirm it is not vacuous: temporarily add `alias Ash.Foo` to
`lib/girihelix/engine/steps.ex`, run the test again, and expect FAIL naming that
file. Remove the line and re-run to see it pass. Do not skip this — a guard that
cannot fail is worse than no guard.

- [ ] **Step 7: Commit**

```bash
git add lib/girihelix/engine/steps.ex test/girihelix/engine/steps_test.exs test/girihelix/engine/architecture_test.exs
```

```bash
git commit -m "feat: add the engine step interpreter and the purity guard"
```

---

### Task 2: `Point`

**Files:**

- Create: `lib/girihelix/engine/geometry/point.ex`
- Create: `test/girihelix/engine/geometry/point_test.exs`

**Interfaces:**

- Consumes: nothing.
- Produces: `%Girihelix.Engine.Geometry.Point{x: float, y: float}` with
  `new/2`, `origin/0`, `unit_x/0`, `unit_y/0`, `tolerance/0`, `tolerance2/0`,
  `mag2/1`, `mag/1`, `dist2/2`, `dist/2`, `add/2`, `subtract/2`, `dot/2`,
  `cross/2`, `scale/2`, `scale/3`, `perp/1`, `normalize/1`, `convex_sum/3`,
  `equals/2`, `compare_to/2`, `angle/1`, `angle_to/2`, `sweep/3`,
  `dist2_to_line/3`, `dist_to_line/3`, `parameterization_on_line/3`, `center/1`
  and `recenter/2`. Every later geometry module consumes these.

This module is the one class in the Java that ports almost mechanically: the `D`
variants are dropped and everything else is a pure function. Three things need a
decision rather than a translation, and all three are tested below: which
tolerance regime `equals/2` means, whether `compare_to/2` is needed at all, and
what `center/1` does with an empty list.

- [ ] **Step 1: Write the failing test**

```elixir
# test/girihelix/engine/geometry/point_test.exs
defmodule Girihelix.Engine.Geometry.PointTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point

  test "arithmetic is pure and returns new points" do
    a = Point.new(1.0, 2.0)
    b = Point.new(3.0, 5.0)

    assert Point.add(a, b) == Point.new(4.0, 7.0)
    assert Point.subtract(b, a) == Point.new(2.0, 3.0)
    assert Point.scale(a, 2.0) == Point.new(2.0, 4.0)
    assert Point.scale(a, 2.0, 3.0) == Point.new(2.0, 6.0)
    assert Point.dot(a, b) == 13.0
    assert Point.cross(a, b) == -1.0

    # the original is untouched
    assert a == Point.new(1.0, 2.0)
  end

  test "perp/1 is a counter-clockwise quarter turn" do
    assert Point.perp(Point.new(1.0, 0.0)) == Point.new(0.0, 1.0)
  end

  test "normalize/1 returns the point unchanged when its magnitude is zero" do
    zero = Point.new(0.0, 0.0)
    assert Point.normalize(zero) == zero
  end

  test "convex_sum/3 extrapolates outside the unit interval" do
    a = Point.new(0.0, 0.0)
    b = Point.new(1.0, 0.0)

    assert Point.convex_sum(a, b, 0.5) == Point.new(0.5, 0.0)
    # t is not clamped, which the Rosette construction depends on
    assert Point.convex_sum(a, b, 2.0) == Point.new(2.0, 0.0)
    assert Point.convex_sum(a, b, -1.0) == Point.new(-1.0, 0.0)
  end

  test "equals/2 tests a squared distance below Point.TOLERANCE2" do
    base = Point.new(1.0, 1.0)

    assert Point.equals(base, Point.new(1.0, 1.0 + 1.0e-9))
    refute Point.equals(base, Point.new(1.0, 1.0 + 1.0e-5))
  end

  # The cross-tolerance check — that Point.equals/2 is stricter than
  # Loose.equals/2 — lives in Task 3, because Loose does not exist yet.

  test "compare_to/2 orders by squared magnitude, not lexicographically" do
    # both have y = 0, so this is unambiguous about which axis is being compared
    near = Point.new(2.0, 0.0)
    far = Point.new(0.0, 3.0)

    # lexicographic by x would put `far` first; by radius, `near` is smaller
    assert Point.compare_to(near, far) == -1
    assert Point.compare_to(far, near) == 1
    assert Point.compare_to(near, near) == 0
  end

  # Review Focus 3: the comparison band makes the ordering non-transitive. A
  # caller expecting a total order can get neither stability nor transitivity,
  # so the surprising behaviour is pinned here rather than discovered later.
  test "compare_to/2 is not transitive" do
    band = Point.tolerance2()

    a = Point.new(0.0, 0.0)
    b = Point.new(:math.sqrt(band * 0.75), 0.0)
    c = Point.new(:math.sqrt(band * 1.5), 0.0)

    assert Point.compare_to(a, b) == 0
    assert Point.compare_to(b, c) == 0
    # a and c span more than the band, so they compare unequal
    assert Point.compare_to(a, c) == -1
  end

  test "angles follow the Java conventions" do
    assert Point.angle(Point.new(1.0, 0.0)) == 0.0
    assert Point.angle(Point.new(0.0, 1.0)) == :math.pi() / 2.0

    from = Point.new(0.0, 0.0)
    assert Point.angle_to(from, Point.new(0.0, 1.0)) == :math.pi() / 2.0
  end

  test "sweep/3 returns a value in [0, 2pi)" do
    vertex = Point.new(0.0, 0.0)
    from = Point.new(1.0, 0.0)
    to = Point.new(0.0, 1.0)

    assert Point.sweep(vertex, from, to) == :math.pi() / 2.0
    assert Point.sweep(vertex, to, from) == 3.0 * :math.pi() / 2.0
  end

  test "dist2_to_line/3 is a clamped point-to-segment distance" do
    a = Point.new(0.0, 0.0)
    b = Point.new(4.0, 0.0)

    # on the segment
    assert Point.dist2_to_line(Point.new(2.0, 3.0), a, b) == 9.0

    # beyond an endpoint: the distance is to the endpoint, not to the infinite line
    assert Point.dist2_to_line(Point.new(-3.0, 0.0), a, b) == 9.0
    assert Point.dist2_to_line(Point.new(7.0, 0.0), a, b) == 9.0
  end

  # Review Focus 1: a zero-length segment makes the projection parameter NaN,
  # and every comparison against NaN is false, so the clamp falls through to the
  # second endpoint. The call returns a plausible number that means nothing.
  test "dist2_to_line/3 silently falls through on a zero-length segment" do
    degenerate = Point.new(1.0, 1.0)
    probe = Point.new(4.0, 5.0)

    # not a distance to the segment at all: it is the distance to the second endpoint
    assert Point.dist2_to_line(probe, degenerate, degenerate) ==
             Point.dist2(degenerate, probe)
  end

  test "parameterization_on_line/3 returns the parameter unclamped" do
    a = Point.new(0.0, 0.0)
    b = Point.new(4.0, 0.0)

    assert Point.parameterization_on_line(Point.new(2.0, 0.0), a, b) == 0.5
    assert Point.parameterization_on_line(Point.new(-4.0, 0.0), a, b) == -1.0
  end

  test "parameterization_on_line/3 raises on a zero-length segment" do
    degenerate = Point.new(1.0, 1.0)

    assert_raise ArgumentError, ~r/zero-length/, fn ->
      Point.parameterization_on_line(Point.new(4.0, 5.0), degenerate, degenerate)
    end
  end

  test "center/1 averages the non-nil entries" do
    points = [Point.new(0.0, 0.0), nil, Point.new(4.0, 2.0)]
    assert Point.center(points) == Point.new(2.0, 1.0)
  end

  # Java returns Point(NaN, NaN) here, because 1.0/0.0 is Infinity and
  # 0.0 * Infinity is NaN. Raising is a deliberate divergence: an empty list is
  # a programming error, and a NaN coordinate propagates silently for ever.
  test "center/1 raises on a list with no real points" do
    assert_raise ArgumentError, ~r/cannot average/, fn -> Point.center([]) end
    assert_raise ArgumentError, ~r/cannot average/, fn -> Point.center([nil]) end
  end

  test "recenter/2 subtracts the centre, leaving nils alone" do
    points = [Point.new(1.0, 1.0), nil, Point.new(3.0, 3.0)]
    assert Point.recenter(points, Point.new(1.0, 1.0)) ==
             [Point.new(0.0, 0.0), nil, Point.new(2.0, 2.0)]
  end
end
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `mix test test/girihelix/engine/geometry/point_test.exs`

Expected: FAIL — `module Girihelix.Engine.Geometry.Point is not available`.

- [ ] **Step 3: Write the minimal implementation**

```elixir
# lib/girihelix/engine/geometry/point.ex
defmodule Girihelix.Engine.Geometry.Point do
  @moduledoc """
  A point in the plane: a pure value with tolerant equality.

  Ported from `geometry/Point.java`. The Java exists in pure and in-place
  flavours, every in-place one suffixed `D`; the `D` forms are dropped here and
  every operation returns a new value.

  Note that `Point`'s tolerance is **not** `Loose`'s. `Point.equals/2` tests a
  squared distance below `tolerance2/0` (`1e-14`), while `Loose.equals/2` tests
  `1e-10`. Both spell "equals" and they differ by two orders of magnitude in
  squared terms, so a caller must know which one it wants.
  """

  @tolerance 1.0e-7
  @tolerance2 @tolerance * @tolerance

  @enforce_keys [:x, :y]
  defstruct [:x, :y]

  @type t :: %__MODULE__{x: float(), y: float()}

  @doc "Builds a point."
  @spec new(number(), number()) :: t()
  def new(x, y), do: %__MODULE__{x: x * 1.0, y: y * 1.0}

  @doc "The linear tolerance used by `equals/2`, `1e-7`."
  def tolerance, do: @tolerance

  @doc "The squared tolerance used by `equals/2`, `1e-14`."
  def tolerance2, do: @tolerance2

  # The Java exposes ORIGIN, UNIT_X and UNIT_Y as shared mutable singletons, which
  # any caller could corrupt through setX/setY. They are functions here.
  @doc "The origin."
  def origin, do: new(0.0, 0.0)

  @doc "The point `(1, 0)`."
  def unit_x, do: new(1.0, 0.0)

  @doc "The point `(0, 1)`."
  def unit_y, do: new(0.0, 1.0)

  @doc "Squared magnitude."
  @spec mag2(t()) :: float()
  def mag2(%__MODULE__{x: x, y: y}), do: x * x + y * y

  @doc "Magnitude."
  @spec mag(t()) :: float()
  def mag(p), do: :math.sqrt(mag2(p))

  @doc "Squared distance between two points."
  @spec dist2(t(), t()) :: float()
  def dist2(%__MODULE__{x: ax, y: ay}, %__MODULE__{x: bx, y: by}) do
    dx = ax - bx
    dy = ay - by
    dx * dx + dy * dy
  end

  @doc "Distance between two points."
  @spec dist(t(), t()) :: float()
  def dist(a, b), do: :math.sqrt(dist2(a, b))

  @doc "Vector sum."
  @spec add(t(), t()) :: t()
  def add(%__MODULE__{x: ax, y: ay}, %__MODULE__{x: bx, y: by}), do: new(ax + bx, ay + by)

  @doc "Vector difference."
  @spec subtract(t(), t()) :: t()
  def subtract(%__MODULE__{x: ax, y: ay}, %__MODULE__{x: bx, y: by}), do: new(ax - bx, ay - by)

  @doc "Dot product."
  @spec dot(t(), t()) :: float()
  def dot(%__MODULE__{x: ax, y: ay}, %__MODULE__{x: bx, y: by}), do: ax * bx + ay * by

  @doc "Two-dimensional cross product."
  @spec cross(t(), t()) :: float()
  def cross(%__MODULE__{x: ax, y: ay}, %__MODULE__{x: bx, y: by}), do: ax * by - ay * bx

  @doc "Uniform scale."
  @spec scale(t(), number()) :: t()
  def scale(%__MODULE__{x: x, y: y}, r), do: new(x * r, y * r)

  @doc "Component-wise scale."
  @spec scale(t(), number(), number()) :: t()
  def scale(%__MODULE__{x: x, y: y}, xr, yr), do: new(x * xr, y * yr)

  @doc "A counter-clockwise quarter turn: `(x, y) -> (-y, x)`."
  @spec perp(t()) :: t()
  def perp(%__MODULE__{x: x, y: y}), do: new(-y, x)

  @doc """
  The unit vector in this direction.

  Returns the point **itself** when the magnitude is exactly zero — an exact
  comparison, not a tolerant one, matching the Java.
  """
  @spec normalize(t()) :: t()
  def normalize(p) do
    case mag(p) do
      0.0 -> p
      m -> scale(p, 1.0 / m)
    end
  end

  @doc """
  The convex sum `(1 - t) * a + t * b`.

  `t` is **not** clamped, so values outside `[0, 1]` extrapolate. The Rosette
  construction relies on that: it passes `t = 10.0`.
  """
  @spec convex_sum(t(), t(), number()) :: t()
  def convex_sum(%__MODULE__{x: ax, y: ay}, %__MODULE__{x: bx, y: by}, t) do
    mt = 1.0 - t
    new(mt * ax + t * bx, mt * ay + t * by)
  end

  @doc """
  Tolerant value equality: a squared distance below `tolerance2/0`.

  Not transitive, and inconsistent with any hash you might build from it, so do
  not use a point as a set or map key.
  """
  @spec equals(t(), t()) :: boolean()
  def equals(a, b), do: dist2(a, b) < @tolerance2

  @doc """
  Orders by **squared magnitude**, with a `tolerance2/0` band, not
  lexicographically by coordinates.

  The band makes the relation non-transitive: `a` can compare equal to `b`, and
  `b` to `c`, while `a` compares less than `c`. Sorting through this comparator
  therefore produces an unstable order, which is faithful to the Java and is
  pinned by a test rather than silently relied upon.
  """
  @spec compare_to(t(), t()) :: -1 | 0 | 1
  def compare_to(a, b) do
    diff = mag2(a) - mag2(b)

    cond do
      diff < -@tolerance2 -> -1
      diff > @tolerance2 -> 1
      true -> 0
    end
  end

  @doc "The angle of this point with respect to the origin, in `-pi..pi`."
  @spec angle(t()) :: float()
  def angle(%__MODULE__{x: x, y: y}), do: :math.atan2(y, x)

  @doc "The angle of the edge from `from` to `to`, in `-pi..pi`."
  @spec angle_to(t(), t()) :: float()
  def angle_to(%__MODULE__{x: ax, y: ay}, %__MODULE__{x: bx, y: by}),
    do: :math.atan2(by - ay, bx - ax)

  @doc """
  The angle swept from `from` to `to` about `vertex`, in `[0, 2pi)`.

  Normalised by adding `2pi` until positive rather than by taking a remainder,
  so a very negative angle iterates — faithful to the Java, and only reachable
  if a caller passes angles differing by many turns.
  """
  @spec sweep(t(), t(), t()) :: float()
  def sweep(vertex, from, to) do
    unwrap(angle_to(vertex, to) - angle_to(vertex, from))
  end

  defp unwrap(res) when res < 0.0, do: unwrap(res + 2.0 * :math.pi())
  defp unwrap(res), do: res

  @doc """
  The squared distance from `p` to the **segment** `a`-`b`, not to the infinite
  line through them.

  A point beyond an endpoint gets its distance to that endpoint. A zero-length
  segment is guarded rather than divided through: Java's division yields `NaN`,
  every comparison against `NaN` is false, and the clamp falls through to the
  second endpoint. This returns that same value explicitly — Elixir's `/` raises
  on a zero divisor, so the guard is required to reproduce it. See
  `parameterization_on_line/3`, which raises instead.
  """
  @spec dist2_to_line(t(), t(), t()) :: float()
  def dist2_to_line(%__MODULE__{} = p, %__MODULE__{} = a, %__MODULE__{} = b) do
    delta = subtract(b, a)

    case dot(delta, delta) do
      # degenerate segment: reproduce the Java's NaN fall-through to `b`
      0.0 -> dist2(b, p)
      denom -> project(p, a, b, denom)
    end
  end

  defp project(p, a, b, denom) do
    delta = subtract(b, a)
    t = dot(subtract(p, a), delta) / denom

    cond do
      t >= 0.0 and t <= 1.0 ->
        projection = new(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y))
        dist2(p, projection)

      t < 0.0 ->
        dist2(a, p)

      true ->
        dist2(b, p)
    end
  end

  @doc "The distance from `p` to the segment `a`-`b`."
  @spec dist_to_line(t(), t(), t()) :: float()
  def dist_to_line(p, a, b), do: :math.sqrt(dist2_to_line(p, a, b))

  @doc """
  The unclamped parameter of `p` along the line through `a` and `b`.

  `0.0` at `a`, `1.0` at `b`, negative before `a`, greater than `1.0` past `b`.

  Raises on a zero-length segment. Java divides through and yields `NaN`, which
  every caller then reads as "not on the segment"; raising is a deliberate
  divergence, recorded here, because a parameter along a segment with no length
  is meaningless and a silent `NaN` is worse than an error.
  """
  @spec parameterization_on_line(t(), t(), t()) :: float()
  def parameterization_on_line(%__MODULE__{} = p, %__MODULE__{} = a, %__MODULE__{} = b) do
    delta = subtract(b, a)

    case dot(delta, delta) do
      0.0 -> raise ArgumentError, "cannot parameterise along a zero-length segment"
      denom -> dot(subtract(p, a), delta) / denom
    end
  end

  @doc """
  The mean of the non-nil points.

  Raises when there is nothing to average. The Java divides by a zero count and
  returns `Point(NaN, NaN)`, which is a silent coordinate poison; raising is a
  deliberate divergence, recorded in the plan.
  """
  @spec center([t() | nil]) :: t()
  def center(points) do
    {sum, count} =
      Enum.reduce(points, {origin(), 0}, fn
        nil, acc -> acc
        %__MODULE__{} = p, {sum, n} -> {add(sum, p), n + 1}
      end)

    if count == 0 do
      raise ArgumentError, "cannot average an empty set of points"
    end

    scale(sum, 1.0 / count)
  end

  @doc """
  Subtracts `center` from each non-nil point, leaving nils in place.

  Returns a new list. The Java returns its input array unchanged when the centre
  is null, which aliases the caller's data; that case cannot arise here.
  """
  @spec recenter([t() | nil], t()) :: [t() | nil]
  def recenter(points, center) do
    Enum.map(points, fn
      nil -> nil
      %__MODULE__{} = p -> subtract(p, center)
    end)
  end
end
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `mix test test/girihelix/engine/geometry/point_test.exs`

Expected: PASS, 16 tests.

If the non-transitivity test fails, the arithmetic is the thing to check, not the
test: the band constant is `tolerance2/0` and the values are derived from it.

- [ ] **Step 5: Commit**

```bash
git add lib/girihelix/engine/geometry/point.ex test/girihelix/engine/geometry/point_test.exs
```

```bash
git commit -m "feat: add Point, the tolerant value type the geometry is written in"
```

---

### Task 3: `Loose`

**Files:**

- Create: `lib/girihelix/engine/geometry/loose.ex`
- Create: `test/girihelix/engine/geometry/loose_test.exs`

**Interfaces:**

- Consumes: `Point.dist2/2`, `Point.mag2/1`.
- Produces: `Loose.tol/0`, `Loose.tol2/0`, `Loose.equals/2`, `Loose.zero/1`,
  `Loose.near/2`, `Loose.near/3`. `Infer` in a later plan depends most on
  `near/3`, whose tolerance is **squared**.

The whole of this module is one idea: the Java compares several different kinds
of quantity, and applies its tolerances to whatever it is handed — differences in
some places, squared distances in others. That is why it gets its own task and
its own tests rather than being inlined.

- [ ] **Step 1: Write the failing test**

```elixir
# test/girihelix/engine/geometry/loose_test.exs
defmodule Girihelix.Engine.Geometry.LooseTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.{Loose, Point}

  test "the tolerances are the source's values" do
    assert Loose.tol() == 1.0e-7
    assert Loose.tol2() == 1.0e-10
  end

  test "equals/2 on numbers is a linear tolerance" do
    assert Loose.equals(1.0, 1.0 + 1.0e-8)
    refute Loose.equals(1.0, 1.0 + 1.0e-6)
  end

  test "equals/2 on points applies its tolerance to a squared distance" do
    origin = Point.new(0.0, 0.0)

    # 1e-6 apart means a squared distance of 1e-12, which is below TOL2 = 1e-10
    assert Loose.equals(origin, Point.new(1.0e-6, 0.0))
    # 1e-4 apart means 1e-8, which is above it
    refute Loose.equals(origin, Point.new(1.0e-4, 0.0))
  end

  # Review Focus 2: two predicates both spelled "equals" that disagree by a
  # factor of a hundred in linear terms. Pinned here so that any future
  # unification of them has to be a deliberate act.
  test "Point.equals/2 is stricter than Loose.equals/2" do
    origin = Point.new(0.0, 0.0)
    nearby = Point.new(1.0e-6, 0.0)

    refute Point.equals(origin, nearby)
    assert Loose.equals(origin, nearby)
  end

  test "zero/1 on a number tests a difference against TOL" do
    assert Loose.zero(1.0e-8)
    refute Loose.zero(1.0e-6)
  end

  test "zero/1 on a point tests a squared magnitude against TOL2" do
    assert Loose.zero(Point.new(1.0e-6, 0.0))
    refute Loose.zero(Point.new(1.0e-3, 0.0))
  end

  test "near/2 compares a difference against an explicit tolerance" do
    assert Loose.near(1.0e-9, 1.0e-7)
    refute Loose.near(1.0e-5, 1.0e-7)
  end

  # The tolerance handed to near/3 is squared. This is the easiest thing in the
  # whole port to misread: 1e-12 here is a linear radius of 1e-6, not 1e-12.
  test "near/3 applies its tolerance to a squared distance" do
    origin = Point.new(0.0, 0.0)
    radius = 1.0e-6
    tolerance = radius * radius

    # exactly at the radius: the squared distance equals the tolerance, and the
    # comparison is strict, so this is not "near"
    refute Loose.near(origin, Point.new(radius, 0.0), tolerance)
    # comfortably inside it
    assert Loose.near(origin, Point.new(radius / 2.0, 0.0), tolerance)
  end
end
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `mix test test/girihelix/engine/geometry/loose_test.exs`

Expected: FAIL — `module Girihelix.Engine.Geometry.Loose is not available`.

- [ ] **Step 3: Write the minimal implementation**

```elixir
# lib/girihelix/engine/geometry/loose.ex
defmodule Girihelix.Engine.Geometry.Loose do
  @moduledoc """
  Fuzzy comparisons — the tolerance surface of the port.

  Ported from `general/Loose.java`. Two constants, and one fact worth
  internalising before using either: **`near/3` applies its tolerance to a
  squared distance**, while `near/2` applies it to a difference. The Java reuses
  a single tolerance value for both, so in `Infer`'s escalating loop the `1e-12`
  floor is a linear radius of `1e-6`, and its `5.0` ceiling is a radius of about
  `2.24`.

  Three members of the Java class are deliberately omitted, because no code
  anywhere in the reference tree references them: `NEAR_TOL`, `lessThan/2` and
  `greaterThan/2`. Porting dead surface as though it were live invites someone to
  build on it. See `docs/algorithm-analysis.md`.
  """

  alias Girihelix.Engine.Geometry.Point

  @tol 1.0e-7
  @tol2 1.0e-10

  @doc "The linear tolerance, `1e-7`."
  @spec tol() :: float()
  def tol, do: @tol

  @doc """
  The squared tolerance, `1e-10`.

  Note this is a **literal in the Java, not `tol * tol`**, which would be
  `1e-14`. That is the whole reason this module and `Point` disagree.
  """
  @spec tol2() :: float()
  def tol2, do: @tol2

  @doc """
  Equality to within `tol/0`.

  Two clauses because the Java overloads on type, and they are not the same
  predicate: numbers have their difference compared against `tol/0`, points have
  a **squared** distance compared against `tol2/0`. Those thresholds sit 100x
  apart in linear terms, so a caller must know which it is asking for.
  """
  @spec equals(number(), number()) :: boolean()
  def equals(a, b) when is_number(a) and is_number(b), do: abs(a - b) < @tol

  @spec equals(Point.t(), Point.t()) :: boolean()
  def equals(%Point{} = a, %Point{} = b), do: Point.dist2(a, b) < @tol2

  @doc """
  Whether a quantity is negligible.

  A number has its magnitude compared against `tol/0`; a point has its squared
  magnitude compared against `tol2/0`. Because callers pass squared distances in
  some places and true distances in others, the *effective linear* radius here
  ranges from `1e-7` to about `3.16e-4` depending on the call site — the single
  most likely source of a subtly different map.
  """
  @spec zero(number() | Point.t()) :: boolean()
  def zero(a) when is_number(a), do: abs(a) < @tol
  def zero(%Point{} = a), do: Point.mag2(a) < @tol2

  @doc "Whether a **difference** is within an explicit tolerance."
  @spec near(number(), number()) :: boolean()
  def near(difference, tolerance)
      when is_number(difference) and is_number(tolerance),
      do: abs(difference) < tolerance

  @doc """
  Whether two points are within an explicit tolerance.

  The tolerance is applied to the **squared** distance, so passing a radius here
  is wrong by a square root. Every caller in `Infer` relies on this reading.
  """
  @spec near(Point.t(), Point.t(), number()) :: boolean()
  def near(%Point{} = a, %Point{} = b, tolerance), do: Point.dist2(a, b) < tolerance
end
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `mix test test/girihelix/engine/geometry/loose_test.exs`

Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/girihelix/engine/geometry/loose.ex test/girihelix/engine/geometry/loose_test.exs
```

```bash
git commit -m "feat: add Loose, so the tolerance regime is stated in one place"
```

---

### Task 4: `Transform`

**Files:**

- Create: `lib/girihelix/engine/geometry/transform.ex`
- Create: `test/girihelix/engine/geometry/transform_test.exs`

**Interfaces:**

- Consumes: `Point` (and `Point.new/2`, `Point.dist/2`, `Point.origin/0`).
- Produces: `%Transform{a, b, c, d, e, f}` with `new/6`, `identity/0`, `zero/0`,
  `scale/1`, `scale/2`, `translate/2`, `translate_point/1`, `rotate/1`,
  `rotate_around_point/2`, `reflect_through_line/2`, `compose/2`, `apply_to/2`,
  `apply_coords/3`, `invert/1`, `flips/1`, `match_line_segment/2`,
  `match_two_segments/4`, `dist_from_zero/2`, `dist_from_inverted_zero/2`.
  Every figure and the instancing pass consume `compose/2` and `apply_to/2`.

Three names differ from the Java, all to stay clear of Elixir's `Kernel`:
`apply/2` becomes `apply_to/2`, `apply(double, double)` becomes `apply_coords/3`,
and `translate(Point)` becomes `translate_point/1`.

- [ ] **Step 1: Write the failing test**

```elixir
# test/girihelix/engine/geometry/transform_test.exs
defmodule Girihelix.Engine.Geometry.TransformTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.{Point, Transform}

  test "identity/0 leaves a point alone" do
    point = Point.new(3.0, -4.0)
    assert Transform.apply_to(Transform.identity(), point) == point
  end

  test "the factories build the matrices the Java builds" do
    assert Transform.scale(2.0) == Transform.new(2.0, 0.0, 0.0, 0.0, 2.0, 0.0)
    assert Transform.scale(2.0, 3.0) == Transform.new(2.0, 0.0, 0.0, 0.0, 3.0, 0.0)
    assert Transform.translate(1.0, 2.0) == Transform.new(1.0, 0.0, 1.0, 0.0, 1.0, 2.0)
    assert Transform.translate_point(Point.new(1.0, 2.0)) == Transform.translate(1.0, 2.0)
  end

  test "rotate/1 turns a point a quarter turn counter-clockwise" do
    rotated = Transform.rotate(:math.pi() / 2.0) |> Transform.apply_to(Point.new(1.0, 0.0))

    assert_in_delta rotated.x, 0.0, 1.0e-12
    assert_in_delta rotated.y, 1.0, 1.0e-12
  end

  test "apply_to/2 and apply_coords/3 agree" do
    transform = Transform.rotate(0.3) |> Transform.compose(Transform.translate(2.0, -1.0))

    assert Transform.apply_to(transform, Point.new(5.0, 7.0)) ==
             Transform.apply_coords(transform, 5.0, 7.0)
  end

  # The composition order is the single easiest thing in this module to read
  # backwards, so it gets an explicit test rather than a comment alone.
  test "compose/2 applies its second argument first" do
    doubler = Transform.scale(2.0)
    shifter = Transform.translate(10.0, 0.0)
    unit = Point.new(1.0, 0.0)

    # translate, then scale: (1 + 10) * 2
    assert Transform.compose(doubler, shifter) |> Transform.apply_to(unit) ==
             Point.new(22.0, 0.0)

    # scale, then translate: 1 * 2 + 10
    assert Transform.compose(shifter, doubler) |> Transform.apply_to(unit) ==
             Point.new(12.0, 0.0)
  end

  test "rotate_around_point/2 leaves its centre fixed" do
    centre = Point.new(3.0, 4.0)
    rotated = Transform.rotate_around_point(centre, 1.1) |> Transform.apply_to(centre)

    assert_in_delta rotated.x, centre.x, 1.0e-12
    assert_in_delta rotated.y, centre.y, 1.0e-12
  end

  test "reflect_through_line/2 fixes the line and reverses either side of it" do
    transform = Transform.reflect_through_line(Point.new(0.0, 0.0), Point.new(1.0, 0.0))

    on_line = Transform.apply_to(transform, Point.new(7.0, 0.0))
    assert_in_delta on_line.x, 7.0, 1.0e-12
    assert_in_delta on_line.y, 0.0, 1.0e-12

    mirrored = Transform.apply_to(transform, Point.new(2.0, 3.0))
    assert_in_delta mirrored.x, 2.0, 1.0e-12
    assert_in_delta mirrored.y, -3.0, 1.0e-12

    # and it is orientation-reversing, which is what flips/1 reports
    assert Transform.flips(transform)
  end

  test "invert/1 undoes a transform" do
    transform = Transform.rotate(0.7) |> Transform.compose(Transform.translate(4.0, -2.0))
    point = Point.new(1.5, -3.25)

    round_tripped =
      transform |> Transform.apply_to(point) |> then(&Transform.apply_to(Transform.invert(transform), &1))

    assert_in_delta round_tripped.x, point.x, 1.0e-12
    assert_in_delta round_tripped.y, point.y, 1.0e-12
  end

  test "invert/1 raises on a singular transform" do
    assert_raise ArgumentError, ~r/non-invertible/, fn ->
      Transform.invert(Transform.zero())
    end
  end

  test "flips/1 is false for rotations and uniform scales" do
    refute Transform.flips(Transform.rotate(0.3))
    refute Transform.flips(Transform.scale(2.0))
    assert Transform.flips(Transform.scale(1.0, -1.0))
  end

  test "match_line_segment/2 carries the unit x interval onto p to q" do
    p = Point.new(2.0, 3.0)
    q = Point.new(5.0, 7.0)
    transform = Transform.match_line_segment(p, q)

    assert Transform.apply_coords(transform, 0.0, 0.0) == p
    assert Transform.apply_coords(transform, 1.0, 0.0) == q
  end

  test "match_line_segment/2 never flips, because its determinant is a squared length" do
    backwards = Transform.match_line_segment(Point.new(0.0, 0.0), Point.new(-3.0, -4.0))

    refute Transform.flips(backwards)
    # the determinant is |q - p| squared, so it is 25 here
    assert backwards.a * backwards.e - backwards.b * backwards.d == 25.0
  end

  test "match_two_segments/4 carries one segment onto another" do
    transform =
      Transform.match_two_segments(
        Point.new(1.0, 1.0),
        Point.new(2.0, 1.0),
        Point.new(0.0, 0.0),
        Point.new(0.0, 4.0)
      )

    start = Transform.apply_to(transform, Point.new(1.0, 1.0))
    finish = Transform.apply_to(transform, Point.new(2.0, 1.0))

    assert_in_delta start.x, 0.0, 1.0e-12
    assert_in_delta start.y, 0.0, 1.0e-12
    assert_in_delta finish.x, 0.0, 1.0e-12
    assert_in_delta finish.y, 4.0, 1.0e-12
  end

  test "equality is exact on all six doubles, with no tolerance" do
    assert Transform.translate(1.0, 2.0) == Transform.translate(1.0, 2.0)
    refute Transform.translate(1.0, 2.0) == Transform.translate(1.0, 2.0 + 1.0e-12)
  end

  test "dist_from_zero/2 scales with the transform and its argument" do
    assert_in_delta Transform.dist_from_zero(Transform.scale(3.0), 1.0), 3.0, 1.0e-12
    assert_in_delta Transform.dist_from_zero(Transform.scale(3.0), 2.0), 6.0, 1.0e-12
  end
end
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `mix test test/girihelix/engine/geometry/transform_test.exs`

Expected: FAIL — `module Girihelix.Engine.Geometry.Transform is not available`.

- [ ] **Step 3: Write the minimal implementation**

```elixir
# lib/girihelix/engine/geometry/transform.ex
defmodule Girihelix.Engine.Geometry.Transform do
  @moduledoc """
  A two-dimensional affine transform: the top two rows of the homogeneous 3x3
  matrix.

      [ a  b  c ]
      [ d  e  f ]
      [ 0  0  1 ]

  `(a, b, d, e)` is the linear part and `(c, f)` the translation, so the mapping
  is `x' = a*x + b*y + c` and `y' = d*x + e*y + f`.

  **Composition order.** `compose(a, b)` applies `b` **first**, then `a`. The Java
  computes `self x other`, which means every nested composition there reads
  outermost-first in the source and innermost-first at run time — the reason
  `rotateAroundPoint` and `reflectThroughLine` look "backwards". The convention
  is kept deliberately, so the factory bodies could be transcribed rather than
  re-derived, and it is documented here and tested.

  Three names differ from the Java, to stay clear of Elixir's `Kernel`:
  `apply/2` is `apply_to/2`, `apply(double, double)` is `apply_coords/3`, and
  `translate(Point)` is `translate_point/1`.
  """

  alias Girihelix.Engine.Geometry.Point

  @enforce_keys [:a, :b, :c, :d, :e, :f]
  defstruct [:a, :b, :c, :d, :e, :f]

  @type t :: %__MODULE__{
          a: float(),
          b: float(),
          c: float(),
          d: float(),
          e: float(),
          f: float()
        }

  @doc "Builds a transform from its six scalars."
  @spec new(number(), number(), number(), number(), number(), number()) :: t()
  def new(a, b, c, d, e, f) do
    %__MODULE__{a: a * 1.0, b: b * 1.0, c: c * 1.0, d: d * 1.0, e: e * 1.0, f: f * 1.0}
  end

  @doc "The identity transform."
  @spec identity() :: t()
  def identity, do: scale(1.0)

  @doc """
  The all-zero matrix, which collapses everything to the origin.

  It is **not** a null transform: its determinant is zero, so `invert/1` raises on
  it. The Java exposes this as the shared mutable constant `ZERO`; here it is a
  function, so no caller can corrupt it for another.
  """
  @spec zero() :: t()
  def zero, do: scale(0.0)

  @doc "Uniform scale."
  @spec scale(number()) :: t()
  def scale(r), do: new(r, 0.0, 0.0, 0.0, r, 0.0)

  @doc "Component-wise scale."
  @spec scale(number(), number()) :: t()
  def scale(xs, ys), do: new(xs, 0.0, 0.0, 0.0, ys, 0.0)

  @doc "Translation."
  @spec translate(number(), number()) :: t()
  def translate(x, y), do: new(1.0, 0.0, x, 0.0, 1.0, y)

  @doc "Translation by a point's coordinates. The point is read, not kept."
  @spec translate_point(Point.t()) :: t()
  def translate_point(%Point{x: x, y: y}), do: translate(x, y)

  @doc """
  Rotation by `t` radians, counter-clockwise in a y-up frame.

  In the y-down screen frame this reads clockwise, which matters for the renderer
  and not for the geometry.
  """
  @spec rotate(number()) :: t()
  def rotate(t) do
    new(:math.cos(t), -:math.sin(t), 0.0, :math.sin(t), :math.cos(t), 0.0)
  end

  @doc """
  Rotation by `t` about a point.

  Applies `-pt`, then the rotation, then `+pt`, which is what the nested
  composition below spells out.
  """
  @spec rotate_around_point(Point.t(), number()) :: t()
  def rotate_around_point(%Point{x: x, y: y} = point, t) do
    compose(translate_point(point), compose(rotate(t), translate(-x, -y)))
  end

  @doc """
  Reflection in the line through `p` and `q`.

  Maps the line onto the unit x interval, flips y, and maps back. Raises when the
  two points coincide, because the line is then undefined and the intermediate
  transform is singular — one of the few places the Java validates anything.
  """
  @spec reflect_through_line(Point.t(), Point.t()) :: t()
  def reflect_through_line(p, q) do
    onto_line = match_line_segment(p, q)
    compose(onto_line, compose(scale(1.0, -1.0), invert(onto_line)))
  end

  @doc """
  Composition: `compose(a, b)` applies **`b` first**, then `a`.

  For any point `v`, `apply_to(compose(a, b), v) == apply_to(a, apply_to(b, v))`.
  """
  @spec compose(t(), t()) :: t()
  def compose(
        %__MODULE__{a: a, b: b, c: c, d: d, e: e, f: f},
        %__MODULE__{a: oa, b: ob, c: oc, d: od, e: oe, f: of}
      ) do
    new(
      a * oa + b * od,
      a * ob + b * oe,
      a * oc + b * of + c,
      d * oa + e * od,
      d * ob + e * oe,
      d * oc + e * of + f
    )
  end

  @doc "Applies the transform to a point."
  @spec apply_to(t(), Point.t()) :: Point.t()
  def apply_to(%__MODULE__{a: a, b: b, c: c, d: d, e: e, f: f}, %Point{x: x, y: y}) do
    Point.new(a * x + b * y + c, d * x + e * y + f)
  end

  @doc "Applies the transform to a coordinate pair, with no allocation in between."
  @spec apply_coords(t(), number(), number()) :: Point.t()
  def apply_coords(%__MODULE__{a: a, b: b, c: c, d: d, e: e, f: f}, x, y) do
    Point.new(a * x + b * y + c, d * x + e * y + f)
  end

  @doc """
  The inverse transform.

  Raises on a singular transform. The Java tests the determinant for **exact**
  equality with `0.0`, not against a tolerance, so a matrix with a determinant of
  `1e-300` inverts to enormous values rather than raising. That behaviour is kept:
  the test is `det == 0.0` here too.
  """
  @spec invert(t()) :: t()
  def invert(%__MODULE__{a: a, b: b, c: c, d: d, e: e, f: f}) do
    det = a * e - b * d

    if det == 0.0 do
      raise ArgumentError, "non-invertible transform"
    end

    new(
      e / det,
      -b / det,
      (b * f - c * e) / det,
      -d / det,
      a / det,
      (c * d - a * f) / det
    )
  end

  @doc "Whether the transform reverses orientation, i.e. its determinant is negative."
  @spec flips(t()) :: boolean()
  def flips(%__MODULE__{a: a, b: b, d: d, e: e}), do: a * e - b * d < 0.0

  @doc """
  The transform carrying the unit interval on the positive x axis onto `p`-`q`.

  `(0, 0)` maps to `p` and `(1, 0)` maps to `q`. It is always a similarity —
  rotation composed with uniform scale — and its determinant is `|q - p|`
  squared, so it **never** flips orientation.
  """
  @spec match_line_segment(Point.t(), Point.t()) :: t()
  def match_line_segment(%Point{x: px, y: py}, %Point{x: qx, y: qy}) do
    new(qx - px, py - qy, px, qy - py, qx - px, py)
  end

  @doc """
  The transform carrying the segment `p1`-`q1` onto `p2`-`q2`.

  Maps `p1` to `p2` and `q1` to `q2`. Both factors are similarities
  parameterised `p` to `q`, so the result never flips either.
  """
  @spec match_two_segments(Point.t(), Point.t(), Point.t(), Point.t()) :: t()
  def match_two_segments(p1, q1, p2, q2) do
    compose(match_line_segment(p2, q2), invert(match_line_segment(p1, q1)))
  end

  @doc """
  The distance between the images of `(v, 0)` and `(0, 0)`.

  A renderer utility in the Java, used to scale stroke widths with zoom. The
  geometry core does not need it, but the SVG emitter will.
  """
  @spec dist_from_zero(t(), number()) :: float()
  def dist_from_zero(transform, v) do
    Point.dist(
      apply_to(transform, Point.new(v, 0.0)),
      apply_to(transform, Point.origin())
    )
  end

  @doc "`dist_from_zero/2` measured through the inverse. Raises on a singular transform."
  @spec dist_from_inverted_zero(t(), number()) :: float()
  def dist_from_inverted_zero(transform, v) do
    transform |> invert() |> dist_from_zero(v)
  end
end
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `mix test test/girihelix/engine/geometry/transform_test.exs`

Expected: PASS, 15 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/girihelix/engine/geometry/transform.ex test/girihelix/engine/geometry/transform_test.exs
```

```bash
git commit -m "feat: add Transform, keeping the Java's composition order"
```

---

### Task 5: `Intersect`

**Files:**

- Create: `lib/girihelix/engine/geometry/intersect.ex`
- Create: `test/girihelix/engine/geometry/intersect_test.exs`

**Interfaces:**

- Consumes: `Point` and `Loose`.
- Produces: `Intersect.get_intersection_params/4` returning `{s, t} | nil`,
  `Intersect.stay_on_segments/1`, `Intersect.stay_near_segments/1`,
  `Intersect.get_intersection/4`, `Intersect.get_near_intersection/4`,
  `Intersect.get_true_intersection/4`. `Map` and `Rosette` in later plans
  consume these; `mergeMap` depends on `get_true_intersection/4` in particular,
  because rejecting a crossing at both segments' endpoints is what stops a shared
  vertex being split.

**The parameter pair is not a point.** The Java packs `s` and `t` into a `Point`,
where every distance and equality operation on it is meaningless. Here it is a
`{s, t}` tuple from end to end. Any code that treats it as a position is a bug.

- [ ] **Step 1: Write the failing test**

```elixir
# test/girihelix/engine/geometry/intersect_test.exs
defmodule Girihelix.Engine.Geometry.IntersectTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.{Intersect, Point}

  # a cross: a horizontal segment and a vertical one through its middle
  defp crossing do
    {Point.new(0.0, 0.0), Point.new(2.0, 0.0), Point.new(1.0, -1.0), Point.new(1.0, 1.0)}
  end

  test "get_intersection_params/4 returns the parameter pair, not a position" do
    {p1, q1, p2, q2} = crossing()

    assert Intersect.get_intersection_params(p1, q1, p2, q2) == {0.5, 0.5}
  end

  test "get_intersection_params/4 returns nil for parallel segments" do
    assert Intersect.get_intersection_params(
             Point.new(0.0, 0.0),
             Point.new(1.0, 0.0),
             Point.new(0.0, 1.0),
             Point.new(1.0, 1.0)
           ) == nil
  end

  test "get_intersection_params/4 returns nil for a zero-length segment" do
    degenerate = Point.new(1.0, 1.0)

    assert Intersect.get_intersection_params(
             degenerate,
             degenerate,
             Point.new(0.0, 0.0),
             Point.new(2.0, 2.0)
           ) == nil
  end

  # Review Focus 4: three quite different situations all produce nil, and the
  # caller cannot tell them apart. Pinned so that no caller grows a dependency
  # on a distinction that does not exist.
  test "parallel, off-segment and degenerate inputs are all indistinguishable" do
    parallel =
      Intersect.get_intersection(
        Point.new(0.0, 0.0),
        Point.new(1.0, 0.0),
        Point.new(0.0, 1.0),
        Point.new(1.0, 1.0)
      )

    # a genuine crossing, but beyond the end of the first segment
    beyond =
      Intersect.get_intersection(
        Point.new(0.0, 0.0),
        Point.new(1.0, 0.0),
        Point.new(2.0, -1.0),
        Point.new(2.0, 1.0)
      )

    degenerate = Point.new(1.0, 1.0)

    empty =
      Intersect.get_intersection(
        degenerate,
        degenerate,
        Point.new(0.0, 0.0),
        Point.new(2.0, 2.0)
      )

    assert parallel == nil
    assert beyond == nil
    assert empty == nil
  end

  # overlapping collinear segments are a documented non-case in the source: the
  # parallel branch returns nil and the author's comment concedes there is
  # nothing useful to do
  test "get_intersection/4 returns nil for overlapping collinear segments" do
    assert Intersect.get_intersection(
             Point.new(0.0, 0.0),
             Point.new(2.0, 0.0),
             Point.new(1.0, 0.0),
             Point.new(3.0, 0.0)
           ) == nil
  end

  test "get_intersection/4 interpolates on the first segment" do
    {p1, q1, p2, q2} = crossing()
    assert Intersect.get_intersection(p1, q1, p2, q2) == Point.new(1.0, 0.0)
  end

  test "stay_on_segments/1 admits parameters a hair outside the unit interval" do
    assert Intersect.stay_on_segments({0.0, 1.0}) == {0.0, 1.0}
    assert Intersect.stay_on_segments({-1.0e-8, 0.5}) == {-1.0e-8, 0.5}
    assert Intersect.stay_on_segments({1.0 + 1.0e-8, 0.5}) == {1.0 + 1.0e-8, 0.5}

    assert Intersect.stay_on_segments({1.5, 0.5}) == nil
    assert Intersect.stay_on_segments({0.5, -0.5}) == nil
    assert Intersect.stay_on_segments(nil) == nil
  end

  test "get_near_intersection/4 accepts a crossing up to 20% past an end" do
    # the second segment sits at x = 1.1, past the end of the first
    p1 = Point.new(0.0, 0.0)
    q1 = Point.new(1.0, 0.0)
    p2 = Point.new(1.1, -1.0)
    q2 = Point.new(1.1, 1.0)

    assert Intersect.get_intersection(p1, q1, p2, q2) == nil
    # ... and the near variant returns a point genuinely off the segment
    assert Intersect.get_near_intersection(p1, q1, p2, q2) == Point.new(1.1, 0.0)
  end

  test "get_true_intersection/4 rejects a crossing at both segments' endpoints" do
    # both segments start at the origin
    assert Intersect.get_true_intersection(
             Point.new(0.0, 0.0),
             Point.new(1.0, 0.0),
             Point.new(0.0, 0.0),
             Point.new(0.0, 1.0)
           ) == nil
  end

  test "get_true_intersection/4 keeps a crossing at one segment's endpoint only" do
    # the shared point is an endpoint of the first segment and interior to the second
    assert Intersect.get_true_intersection(
             Point.new(0.0, 0.0),
             Point.new(1.0, 0.0),
             Point.new(0.0, -1.0),
             Point.new(0.0, 1.0)
           ) == Point.new(0.0, 0.0)
  end

  test "get_true_intersection/4 keeps an ordinary interior crossing" do
    {p1, q1, p2, q2} = crossing()
    assert Intersect.get_true_intersection(p1, q1, p2, q2) == Point.new(1.0, 0.0)
  end
end
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `mix test test/girihelix/engine/geometry/intersect_test.exs`

Expected: FAIL — `module Girihelix.Engine.Geometry.Intersect is not available`.

- [ ] **Step 3: Write the minimal implementation**

```elixir
# lib/girihelix/engine/geometry/intersect.ex
defmodule Girihelix.Engine.Geometry.Intersect do
  @moduledoc """
  Segment-to-segment crossing. Stateless.

  Ported from `geometry/Intersect.java`. Three things about it are deliberate in
  the source and must not be "improved" without recording the change.

  **A crossing is a parameter pair, not a position.** `get_intersection_params/4`
  returns `{s, t}`, the fractions along each segment. The Java packs those into a
  `Point`, where they are not a location at all.

  **Everything that fails returns `nil`, and the reasons are indistinguishable.**
  Parallel segments, a crossing outside the segment, and a zero-length segment all
  give `nil`, so no caller can tell which happened.

  **Overlapping collinear segments and endpoint-touching pairs are not handled.**
  The source says so and stops there. Callers that need those cases handle them
  themselves, which is exactly what the `nil` check in `Rosette` is for.
  """

  alias Girihelix.Engine.Geometry.{Loose, Point}

  @near_slack 0.2

  @doc """
  The crossing of two segments as `{s, t}`, or `nil`.

  `s` is the fraction along `p1 -> q1`, `t` along `p2 -> q2`. Parallel segments —
  including a zero-length one, whose direction vector is zero — return `nil`.

  The parallel test is `Loose.zero(det)`, an **absolute** `1e-7` on a quantity
  with units of length squared. It is therefore scale dependent: a map scaled up
  by 1000 will have near-parallel edges declared intersecting. Kept as-is, because
  it is the source's behaviour.
  """
  @spec get_intersection_params(Point.t(), Point.t(), Point.t(), Point.t()) ::
          {float(), float()} | nil
  def get_intersection_params(%Point{} = p1, %Point{} = q1, %Point{} = p2, %Point{} = q2) do
    d1 = Point.subtract(q1, p1)
    d2 = Point.subtract(q2, p2)
    det = d1.x * d2.y - d1.y * d2.x

    if Loose.zero(det) do
      nil
    else
      # Adapted from O'Rourke's _Computational Geometry in C_, transcribed rather
      # than simplified: the signs are easy to get wrong and a mistake here is
      # silently a swapped or negated parameter.
      s = -((p1.x * d2.y) + p2.x * (p1.y - q2.y) + q2.x * (p2.y - p1.y)) / det
      t = ((p1.x * (p2.y - q1.y)) + q1.x * (p1.y - p2.y) + p2.x * d1.y) / det

      {s, t}
    end
  end

  @doc """
  Keeps a parameter pair only if both parameters are within `Loose.tol/0` of
  `[0, 1]`, so a crossing a hair past an endpoint still counts.
  """
  @spec stay_on_segments({float(), float()} | nil) :: {float(), float()} | nil
  def stay_on_segments(nil), do: nil

  def stay_on_segments({s, t}) do
    if within?(s, Loose.tol()) and within?(t, Loose.tol()), do: {s, t}, else: nil
  end

  @doc """
  Keeps a parameter pair only if both parameters are within `0.2` of `[0, 1]`.

  A hard-coded parameter-space slack, not a distance, so it is scale invariant —
  unlike the determinant test in `get_intersection_params/4`. It is what the newer
  inference strategies reach for when no tidy crossing exists.
  """
  @spec stay_near_segments({float(), float()} | nil) :: {float(), float()} | nil
  def stay_near_segments(nil), do: nil

  def stay_near_segments({s, t}) do
    if within?(s, @near_slack) and within?(t, @near_slack), do: {s, t}, else: nil
  end

  @doc """
  The crossing of two segments, as a position on the first.

  Returns the point `(1 - s) * p1 + s * q1`, or `nil`. The `t` parameter is
  validated but never used to build the position, so the result always lies on
  the first segment — or, for `get_near_intersection/4`, up to 20% beyond it.
  """
  @spec get_intersection(Point.t(), Point.t(), Point.t(), Point.t()) :: Point.t() | nil
  def get_intersection(p1, q1, p2, q2) do
    interpolate(p1, q1, get_intersection_params(p1, q1, p2, q2) |> stay_on_segments())
  end

  @doc "As `get_intersection/4`, with the wider `0.2` parameter slack."
  @spec get_near_intersection(Point.t(), Point.t(), Point.t(), Point.t()) :: Point.t() | nil
  def get_near_intersection(p1, q1, p2, q2) do
    interpolate(p1, q1, get_intersection_params(p1, q1, p2, q2) |> stay_near_segments())
  end

  @doc """
  The crossing, excluding one that lands at the endpoints of **both** segments.

  This is `mergeMap`'s variant. Two edges meeting at a shared vertex cross there,
  with `s` and `t` both near `0` or both near `1`; discarding that case is what
  stops the shared vertex being split into two.

  Note it does **not** reject a crossing at an endpoint of one segment that is
  interior to the other, which is why the ordinary "T" junction survives.
  """
  @spec get_true_intersection(Point.t(), Point.t(), Point.t(), Point.t()) :: Point.t() | nil
  def get_true_intersection(p1, q1, p2, q2) do
    case get_intersection_params(p1, q1, p2, q2) |> stay_on_segments() do
      nil ->
        nil

      {s, t} ->
        if both_endpoints?(s, t), do: nil, else: Point.convex_sum(p1, q1, s)
    end
  end

  defp interpolate(_p1, _q1, nil), do: nil
  defp interpolate(p1, q1, {s, _t}), do: Point.convex_sum(p1, q1, s)

  defp within?(value, slack), do: value >= -slack and value <= 1.0 + slack

  # the crossing sits at an end of segment 1 AND at an end of segment 2
  defp both_endpoints?(s, t) do
    at_start_of_1 = s < Loose.tol()
    at_end_of_1 = 1.0 - s < Loose.tol()
    at_an_end_of_2 = t < Loose.tol() or 1.0 - t < Loose.tol()

    (at_start_of_1 or at_end_of_1) and at_an_end_of_2
  end
end
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `mix test test/girihelix/engine/geometry/intersect_test.exs`

Expected: PASS, 11 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/girihelix/engine/geometry/intersect.ex test/girihelix/engine/geometry/intersect_test.exs
```

```bash
git commit -m "feat: add Intersect, with crossings as parameter pairs"
```

---

### Task 6: `Polygon`

**Files:**

- Create: `lib/girihelix/engine/geometry/polygon.ex`
- Create: `test/girihelix/engine/geometry/polygon_test.exs`

**Interfaces:**

- Consumes: `Point` and `Transform`.
- Produces: `%Polygon{points: [Point.t()]}` with `new/1`, `points/1`,
  `num_vertices/1`, `vertex/2`, `apply_transform/2`, `arc_length/2`, `area/1`,
  `contains_point?/2` and `point_in_poly/2`. `FillRegion` and `Infer` in later
  plans consume `contains_point?/2`; `Map`'s bounds and the renderer consume
  `area/1`.

**One structural simplification, and it is the whole module.** The Java's
`Polygon` carries a backing array, a `size`, a `grow` policy and an
`ensureSize/1` that reallocates on every insert. All of that exists to emulate a
growable array, which a list already is. None of it is ported, and two of the
five Java constructors therefore do not correspond to anything here.

- [ ] **Step 1: Write the failing test**

```elixir
# test/girihelix/engine/geometry/polygon_test.exs
defmodule Girihelix.Engine.Geometry.PolygonTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.{Point, Polygon, Transform}

  defp unit_square do
    Polygon.new([
      Point.new(0.0, 0.0),
      Point.new(1.0, 0.0),
      Point.new(1.0, 1.0),
      Point.new(0.0, 1.0)
    ])
  end

  test "new/1 keeps the vertex order and reports the count" do
    square = unit_square()

    assert Polygon.num_vertices(square) == 4
    assert Polygon.vertex(square, 0) == Point.new(0.0, 0.0)
    assert Polygon.vertex(square, 2) == Point.new(1.0, 1.0)
    assert Polygon.points(square) |> length() == 4
  end

  test "vertex/2 raises past the end rather than returning a spare slot" do
    assert_raise ArgumentError, ~r/out of range/, fn -> Polygon.vertex(unit_square(), 4) end
  end

  test "area/1 is the shoelace area, and discards winding" do
    assert Polygon.area(unit_square()) == 1.0

    # the same square, wound the other way, has the same area
    clockwise =
      Polygon.new([
        Point.new(0.0, 0.0),
        Point.new(0.0, 1.0),
        Point.new(1.0, 1.0),
        Point.new(1.0, 0.0)
      ])

    assert Polygon.area(clockwise) == 1.0
  end

  test "area/1 of a triangle" do
    triangle =
      Polygon.new([Point.new(0.0, 0.0), Point.new(4.0, 0.0), Point.new(0.0, 3.0)])

    assert Polygon.area(triangle) == 6.0
  end

  # Review Focus 5: the Java takes a remainder modulo the vertex count, so an
  # empty polygon raises ArithmeticException rather than returning zero. Raising
  # here keeps that an error rather than turning it into a value.
  test "area/1 raises on an empty polygon" do
    assert_raise ArgumentError, ~r/empty polygon/, fn -> Polygon.area(Polygon.new([])) end
  end

  test "arc_length/2 measures the open or closed path" do
    square = unit_square()

    assert Polygon.arc_length(square, false) == 3.0
    assert Polygon.arc_length(square, true) == 4.0
  end

  test "arc_length/2 of a single point is zero either way" do
    single = Polygon.new([Point.new(2.0, 3.0)])

    assert Polygon.arc_length(single, false) == 0.0
    assert Polygon.arc_length(single, true) == 0.0
  end

  test "arc_length/2 raises on an empty closed polygon" do
    assert_raise ArgumentError, ~r/empty polygon/, fn ->
      Polygon.arc_length(Polygon.new([]), true)
    end

    # ... but an empty open path is legitimately zero
    assert Polygon.arc_length(Polygon.new([]), false) == 0.0
  end

  test "contains_point?/2 is true inside and false outside" do
    square = unit_square()

    assert Polygon.contains_point?(square, Point.new(0.5, 0.5))
    refute Polygon.contains_point?(square, Point.new(2.0, 2.0))
    refute Polygon.contains_point?(square, Point.new(-0.5, 0.5))
  end

  # An empty polygon contains nothing, which is a decision: the Java indexes
  # pts[0] and throws. Returning false is the honest answer to the question.
  test "contains_point?/2 is false for an empty polygon" do
    refute Polygon.contains_point?(Polygon.new([]), Point.new(0.0, 0.0))
  end

  test "apply_transform/2 returns a new polygon and leaves the original alone" do
    square = unit_square()
    moved = Polygon.apply_transform(square, Transform.translate(10.0, 0.0))

    assert Polygon.vertex(moved, 0) == Point.new(10.0, 0.0)
    assert Polygon.vertex(square, 0) == Point.new(0.0, 0.0)
  end

  test "point_in_poly/2 takes the polygon as a closed list" do
    points = Polygon.points(unit_square())

    assert Polygon.point_in_poly(points, Point.new(0.5, 0.5))
    refute Polygon.point_in_poly(points, Point.new(1.5, 0.5))
  end
end
```

- [ ] **Step 2: Run the test and watch it fail**

Run: `mix test test/girihelix/engine/geometry/polygon_test.exs`

Expected: FAIL — `module Girihelix.Engine.Geometry.Polygon is not available`.

- [ ] **Step 3: Write the minimal implementation**

```elixir
# lib/girihelix/engine/geometry/polygon.ex
defmodule Girihelix.Engine.Geometry.Polygon do
  @moduledoc """
  A polygon: a closed list of points, with area, length and containment.

  Ported from `geometry/Polygon.java`. It is a **value**: equality is structural
  and order-sensitive, with no identity semantics. That is the opposite of the
  graph nodes in `Map`, which are identities.

  The Java's growable-array machinery — a backing array, a `size` cursor, a `grow`
  policy and an `ensureSize/1` that reallocates on every insert — is not ported.
  A list is already growable, so three of the five Java constructors have no
  counterpart here, and `addVertex`/`setVertex` are replaced by building a new
  polygon from a list.
  """

  alias Girihelix.Engine.Geometry.{Point, Transform}

  @enforce_keys [:points]
  defstruct [:points]

  @type t :: %__MODULE__{points: [Point.t()]}

  @doc "Builds a polygon from its vertices, in order."
  @spec new([Point.t()]) :: t()
  def new(points) when is_list(points), do: %__MODULE__{points: points}

  @doc "The vertices, in order."
  @spec points(t()) :: [Point.t()]
  def points(%__MODULE__{points: points}), do: points

  @doc "How many vertices the polygon has."
  @spec num_vertices(t()) :: non_neg_integer()
  def num_vertices(%__MODULE__{points: points}), do: length(points)

  @doc """
  The vertex at `index`.

  Raises when out of range. The Java's `getVertex` does not check against its
  `size`, so it can read a spare array slot and return `null` — a caller that
  trusts it can be handed nothing rather than an error.
  """
  @spec vertex(t(), non_neg_integer()) :: Point.t()
  def vertex(%__MODULE__{points: points}, index) do
    case Enum.fetch(points, index) do
      {:ok, point} -> point
      :error -> raise ArgumentError, "vertex index #{index} out of range"
    end
  end

  @doc "Applies a transform to every vertex, returning a new polygon."
  @spec apply_transform(t(), Transform.t()) :: t()
  def apply_transform(%__MODULE__{points: points}, %Transform{} = transform) do
    %__MODULE__{points: Enum.map(points, &Transform.apply_to(transform, &1))}
  end

  @doc """
  The shoelace area, with the sign discarded.

  Raises on an empty polygon. The Java's `% size` divides by zero and raises
  `ArithmeticException`; returning `0.0` here would turn an error into a value.
  """
  @spec area(t()) :: float()
  def area(%__MODULE__{points: []}) do
    raise ArgumentError, "an empty polygon has no area"
  end

  def area(%__MODULE__{points: points}) do
    vertices = List.to_tuple(points)
    size = tuple_size(vertices)

    total =
      Enum.reduce(0..(size - 1), 0.0, fn index, acc ->
        %Point{x: x1, y: y1} = elem(vertices, index)
        %Point{x: x2, y: y2} = elem(vertices, rem(index + 1, size))
        acc + (x1 * y2 - y1 * x2)
      end)

    abs(total) * 0.5
  end

  @doc """
  The length of the path through the vertices.

  When `closed`, the edge from the last vertex back to the first is included.
  Raises on an empty **closed** polygon, where the Java indexes out of bounds;
  an empty open path is legitimately zero.
  """
  @spec arc_length(t(), boolean()) :: float()
  def arc_length(%__MODULE__{points: []}, true) do
    raise ArgumentError, "an empty polygon has no closed perimeter"
  end

  def arc_length(%__MODULE__{points: []}, false), do: 0.0

  def arc_length(%__MODULE__{points: points}, closed) do
    open =
      points
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.reduce(0.0, fn [a, b], acc -> acc + Point.dist(a, b) end)

    if closed do
      open + Point.dist(List.first(points), List.last(points))
    else
      open
    end
  end

  @doc """
  Whether a point lies inside the polygon.

  Returns `false` for an empty polygon: it contains nothing, and the Java's
  out-of-bounds index is not a more useful answer.
  """
  @spec contains_point?(t(), Point.t()) :: boolean()
  def contains_point?(%__MODULE__{points: []}, %Point{}), do: false
  def contains_point?(%__MODULE__{points: points}, %Point{} = probe), do: point_in_poly(points, probe)

  @doc """
  The even-odd containment test, over a **closed** list of points.

  From Bob Stein's *A Point about Polygons*, as the Java's comment records. A
  crossing ray is counted with a half-open straddle test in x, which is what makes
  a ray passing exactly through a vertex count once rather than twice, and the
  crossing test itself uses no division.

  Despite the Java's variable being named `outside`, the result is **true for
  inside** — a ray crosses a closed polygon an odd number of times exactly when
  the point is within it.

  The Java also accepts a `start`/`end` slice, and its index arithmetic wraps
  against the slice length rather than the array, so any `start > 0` reads the
  wrong vertices. That form is not exposed here: every call site in the reference
  tree passes `start = 0`, and a port that reproduced the bug would be
  reproducing something no caller ever asked for.
  """
  @spec point_in_poly([Point.t()], Point.t()) :: boolean()
  def point_in_poly([], %Point{}), do: false

  def point_in_poly([first | _] = points, %Point{x: x, y: y}) do
    vertices = List.to_tuple(points)
    size = tuple_size(vertices)

    {_last, inside} =
      Enum.reduce(0..(size - 1), {first, false}, fn index, {previous, inside} ->
        current = elem(vertices, rem(index + 1, size))
        {current, straddles?(previous, current, x, y, inside)}
      end)

    inside
  end

  # Normalise the edge so that (xmin, ymin) is its lower-x end, then ask whether
  # the point is above the edge at this x. Strict `>` throughout, so a point
  # exactly on an edge does not toggle.
  defp straddles?(%Point{x: ax, y: ay}, %Point{x: bx, y: by}, x, y, inside) do
    {xmin, ymin, xmax, ymax} = if ax < bx, do: {ax, ay, bx, by}, else: {bx, by, ax, ay}

    if xmin <= x and x < xmax and (x - xmin) * (ymax - ymin) > (y - ymin) * (xmax - xmin) do
      not inside
    else
      inside
    end
  end
end
```

- [ ] **Step 4: Run the test and watch it pass**

Run: `mix test test/girihelix/engine/geometry/polygon_test.exs`

Expected: PASS, 12 tests.

- [ ] **Step 5: Run the whole suite and the fast gate**

Run: `mix precommit.fast && mix test`

Expected: the gate passes and every test in the plan is green. This is the first
point at which 1a is demonstrably complete, so it is worth running the full gate
rather than the single file.

- [ ] **Step 6: Commit**

```bash
git add lib/girihelix/engine/geometry/polygon.ex test/girihelix/engine/geometry/polygon_test.exs
```

```bash
git commit -m "feat: add Polygon, and complete the engine substrate"
```

---

## What 1a delivers

At the end of this plan there is a pure-Elixir geometry substrate with no Ash, no
Phoenix and no database, and a guard test that keeps it that way. Seventy-two
tests cover it, and five of them exist specifically to pin the surprising
behaviours listed under Review Focus rather than to confirm the happy path.

What it does **not** deliver, and what Plan 1b picks up: `Vertex`, `Edge`, `Map`,
`Faces`, `FillRegion` and `Rect`. The planar map is where the port's real
difficulty lives — `mergeMap`'s two-pointer weld and `Faces`' two-colouring are
the two hardest algorithms in Taprats — so it gets its own plan and its own
review gate rather than riding along at the end of this one.

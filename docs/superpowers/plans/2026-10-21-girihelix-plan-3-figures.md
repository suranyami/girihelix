# Figures implementation plan (Plan 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port Taprats 1.1.12's radial figures — `Star`, `Rosette`,
`ScaleFigure`, `ConnectFigure` and `ExplicitFigure` — over a shared `Figure` and
`RadialFigure`, with fallible clamped constructors, stepped builders verified
against real Taprats through the local harness, and five workbench exhibits.

**Architecture:** Engine modules live under `lib/girihelix/engine/figures/` and
use the standard library plus the existing geometry and `PlanarMap` public API.
`Figure` is a behaviour and dispatcher; `RadialFigure` is a behaviour plus the
derived-state and c_n-ladder helper. Each builder exposes `start/…`, `steps/…`
and `result/1`, and its plain `build_unit/1` is the steps run. The local Java
harness gains one terminal `figure` operation with a recursive expression; the
Elixir side of the harness parses it in `test/support`. The five exhibits live
in `lib/girihelix_web/workbench/exhibits/` and are registered in
`GirihelixWeb.Workbench.Registry`.

**Tech Stack:** Elixir 1.20.3, ExUnit, dialyxir; Java 21 for the local harness.
No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-21-girihelix-figures-design.md`. Read
it in full first; it fixes every interface this plan uses. The authoritative
source behaviour is the local, git-ignored `reference/porting-notes/figures.md`:

- §0.4–0.5: `Figure` and `RadialFigure`
- §1: `Star`; §2: `Rosette`; §3: `ScaleFigure`; §4: `ConnectFigure`
- §6: `ExplicitFigure`; §7: clamps, tolerances and defaults
- §11: the judgement calls; §12: the per-builder checklist

The Java is in `reference/1.1.12/src/app/`.

## Global Constraints

- **Engine purity.** `lib/girihelix/engine/**` imports the standard library
  only. `test/girihelix/engine/architecture_test.exs` enforces no Ash, Ecto,
  Phoenix or `GirihelixWeb` reference.
- **Hard rules.** No `if` or `cond`; branch in function heads and guards. A
  failing public constructor returns `{:error, reason}` and has a `name!` twin
  that raises `ArgumentError` naming the reason. A `case` matching
  `{:ok, _}` / `{:error, _}` is pattern matching, not a conditional.
- **Tier-3 constructors.** `Star.new/3`, `Rosette.new/3`, `ScaleFigure.new/2`,
  `ConnectFigure.new/1` and `ExplicitFigure.new/1` return
  `{:ok, struct} | {:error, atom}`; each has a `new!` twin. The clamps are
  shared with the `:clamp` step and the constructor stores the clamped values.
- **`build_unit/1` returns a map, never a tuple.** Where the source crashes on
  degenerate geometry, the port raises `ArgumentError` naming the reason. It
  never silently substitutes geometry.
- **Step sequences.** Each builder with stages exposes `start/…`, `steps/…` and
  `result/1`. Its plain builder is
  `steps(...) |> Steps.run!(start(...)) |> Steps.final() |> result()`. A test
  pins the pair.
- **`PlanarMap` only through its public API.** Never match `%PlanarMap{}`. Use
  `insert_vertex/2`, `insert_edge!/3`, `remove_vertex!/2`, `scale/2`,
  `transform!/2`, `vertices/1`, `edges/1`, `endpoints!/2`, `ring!/2`,
  `position!/2`, `num_vertices/1`, `num_edges/1`, `verify/1`.
- **Faithful first.** Do not fix a FIXME, a null crash or a tolerance. Record
  each flaw at one named function and pin it by a test.
- **The harness stays local.** Everything under `reference/oracle/` is
  git-ignored. Never `git add` anything under `reference/`, and never use
  `git add -f`.
- **Gates.** `mix dialyzer` reports `Total errors: 0` before every commit. No
  module may exceed 800 lines. `mix format --check-formatted` passes.
- **Markdown.** Lint with
  `markdownlint-cli2 --config ~/.markdownlint-cli2.jsonc`.
- **Formatting.** `mix format` runs Styler, which can displace `# --` section
  comments; check them after formatting.
- **Git.** Run `git commit` as its own command. Commits are signed; if a
  1Password signing error occurs, stop and ask the user and never disable
  signing.
- **The dev server.** Never start or stop the dev server on port 4000;
  Tidewave owns it.

## Review Focus

1. **A parameter the source clamps.** `d = 99`, `q = -2` and an oversized `s`
   must yield the clamped geometry from both `new/3` and the stepped path, and
   the two maps must be equal. Owner: Tasks 2, 4, and the exhibit panels in
   Tasks 8 and 9.
2. **A degenerate construction.** Star's failed crossing, Rosette's skipped
   step, ScaleFigure's missing tip and ConnectFigure's zero extent must raise
   or skip exactly where the source does. A silent different figure is a
   failure. Owner: Tasks 2, 4, 5 and 6.
3. **The unit-to-map boundary.** The c_n ladder must begin at `Tr`, not the
   identity, and boundary vertices must coalesce at `1e-7` per coordinate. A
   doubled seam is visible and is a failure. Owner: Task 1.
4. **A nested child.** Scale and Connect must build the child afresh, must not
   modify it, and must honour the `s = 1` passthrough and its coupling to
   Connect's half-step rotation. Owner: Tasks 5, 6 and 9.
5. **An incomplete frame.** Before `:assemble` a figure state has `map: nil`,
   and a failure frame has fewer stages. Every exhibit must draw without
   raising. Owner: Tasks 8 and 9, plus the registry property test they extend.

---

### Task 1: `Figure`, `RadialFigure` and the ladder

**Files:**

- Create: `lib/girihelix/engine/figures/figure.ex`
- Create: `lib/girihelix/engine/figures/radial_figure.ex`
- Create: `test/support/figure_fixtures.ex`
- Create: `test/girihelix/engine/figures/figure_test.exs`
- Create: `test/girihelix/engine/figures/radial_figure_test.exs`

**Interfaces:**

- Consumes: `Girihelix.Engine.Geometry.{Point, Transform}`,
  `Girihelix.Engine.PlanarMap`.
- Produces:
  - `Girihelix.Engine.Figures.Figure`
    - `@type t :: struct()` in this task; the full union in Task 7
    - `@callback build_unit(t()) :: PlanarMap.t()` (`n/1` is `RadialFigure`'s)
    - `unit(t()) :: PlanarMap.t()`
    - `map(t()) :: PlanarMap.t()`
    - `radial?(t()) :: boolean()`
  - `Girihelix.Engine.Figures.RadialFigure`
    - `@type t :: struct()` in this task; the four-variant union in Task 7
    - `@callback build_unit(t()) :: PlanarMap.t()`
    - `@callback n(t()) :: pos_integer()`
    - `don(pos_integer()) :: float()`
    - `tr(pos_integer()) :: Transform.t()`
    - `arc(float()) :: Point.t()`
    - `mirror(Point.t()) :: Point.t()`
    - `unit_ngon(pos_integer()) :: [Point.t()]`
    - `ladder(pos_integer()) :: [Transform.t()]`
    - `map(t()) :: PlanarMap.t()`
  - `Girihelix.Engine.FigureFixtures.Square` (test only), a four-fold figure
    whose unit is the single-side wedge `(1,0)`–`(0,1)`: two vertices, one
    edge. Four quarter turns then produce the diamond's four sides — 4
    vertices, 4 edges, `verify/1 == :ok` — rather than four copies of a closed
    diamond (which would append 16 parallel edges).

`Figure.map/1` needs clauses for `ExplicitFigure` (not yet defined) and the
radial behaviour. For this task, declare `@type t :: struct()` in both
`Figure` and `RadialFigure`, and keep only the radial clause in `Figure.map/1`.
Task 7 replaces both types with the full five-variant union and adds the
`ExplicitFigure` clause; typing them earlier would reference modules that do
not exist yet and fail dialyzer.

- [ ] **Step 1: Write the failing `RadialFigure` tests**

```elixir
test "don, tr, arc and mirror are the source's primitives" do
  assert RadialFigure.don(8) == 0.125
  assert RadialFigure.tr(8) == Transform.rotate(2.0 * :math.pi() / 8.0)
  assert RadialFigure.arc(0.0) == Point.new(1.0, 0.0)

  # Trigonometry at the quarter turns leaves rounding noise, so compare the
  # axes with a tolerance rather than exact equality.
  assert %Point{x: x0, y: y0} = RadialFigure.arc(0.5)
  assert_in_delta x0, -1.0, 1.0e-15
  assert_in_delta y0, 0.0, 1.0e-15

  assert %Point{x: x1, y: y1} = RadialFigure.arc(-0.25)
  assert_in_delta x1, 0.0, 1.0e-15
  assert_in_delta y1, -1.0, 1.0e-15

  assert RadialFigure.mirror(Point.new(0.3, 0.2)) == Point.new(0.3, -0.2)
end

test "ladder/1 is Tr through Tr^n, starting at Tr" do
  ladder = RadialFigure.ladder(4)
  assert length(ladder) == 4
  assert hd(ladder) == Transform.rotate(2.0 * :math.pi() / 4.0)

  # The last entry is Tr composed with itself n times: identity only up to
  # rounding, which is why the ladder must not start at the identity.
  last = List.last(ladder)
  assert_in_delta last.a, 1.0, 1.0e-12
  assert last.a != 1.0 or last.b != 0.0
end

test "unit_ngon/1 is counter-clockwise from (1, 0)" do
  [p0, p1, p2, p3] = RadialFigure.unit_ngon(4)

  assert p0 == Point.new(1.0, 0.0)
  assert_in_delta p1.x, 0.0, 1.0e-15
  assert_in_delta p1.y, 1.0, 1.0e-15
  assert_in_delta p2.x, -1.0, 1.0e-15
  assert_in_delta p2.y, 0.0, 1.0e-15
  assert_in_delta p3.x, 0.0, 1.0e-15
  assert_in_delta p3.y, -1.0, 1.0e-15
end
```

The last assertion in the ladder test must be adjusted to the arithmetic the
implementation produces if the composition happens to be exactly identity; the
test's purpose is that `hd(ladder)` is `Tr`, not `identity`.

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix/engine/figures/radial_figure_test.exs`
Expected: FAIL, the module is undefined.

- [ ] **Step 3: Write the failing `Figure` tests**

```elixir
test "unit/1 and map/1 replicate the fixture four times without doubling" do
  figure = %FigureFixtures.Square{}

  unit = Figure.unit(figure)
  assert PlanarMap.num_vertices(unit) == 4
  assert PlanarMap.num_edges(unit) == 4

  map = Figure.map(figure)
  assert PlanarMap.verify(map) == :ok
  assert PlanarMap.num_vertices(map) == 4
  assert PlanarMap.num_edges(map) == 4
end

test "radial?/1 distinguishes the radial figures" do
  assert Figure.radial?(%FigureFixtures.Square{})
end
```

The fixture is a four-fold figure: every copy's vertices coincide exactly with
the previous copy's, so a correct ladder and coalescing leave four vertices and
four edges. A ladder that starts at the identity would produce eight vertices.

- [ ] **Step 4: Run them to see them fail**

Run: `mix test test/girihelix/engine/figures/figure_test.exs`
Expected: FAIL, `Girihelix.Engine.Figures.Figure` and the fixture are undefined.

- [ ] **Step 5: Implement the behaviours, helpers and fixture**

`RadialFigure.map/1` is:

```elixir
def map(figure), do: PlanarMap.replicate!(PlanarMap.new(), unit(figure), ladder(n(figure)))
```

where `unit(figure)` calls the implementing module's `build_unit/1`. `ladder/1`
folds `Transform.compose/2` from a starting `tr(n)`, prepending each value, and
must not use `Transform.identity/0`. Use `Point.new` for `arc/1` so the
coordinates are floats.

`Figure.map/1` dispatches to `RadialFigure.map/1` for the radial structs;
`Figure.unit/1` calls the module's `build_unit/1`. `Figure.radial?/1` is a
function-head predicate over the radial structs.

- [ ] **Step 6: Run the tests to see them pass**

Run: `mix test test/girihelix/engine/figures/figure_test.exs test/girihelix/engine/figures/radial_figure_test.exs`
Expected: PASS.

- [ ] **Step 7: Gates and commit**

Run `mix precommit.fast && mix dialyzer` (`Total errors: 0`), then:

```bash
git add lib/girihelix/engine/figures test/girihelix/engine/figures test/support/figure_fixtures.ex
git commit -m "feat: add the figure behaviour and the radial replication ladder"
```

### Task 2: `Star`

**Files:**

- Create: `lib/girihelix/engine/figures/star.ex`
- Create: `test/girihelix/engine/figures/star_test.exs`

**Interfaces:**

- Consumes: `Figure` and `RadialFigure` from Task 1;
  `Geometry.{Point, Transform, Segment, Intersect, Loose}`; `PlanarMap`;
  `Steps`.
- Produces: `Girihelix.Engine.Figures.Star` with
  - `@enforce_keys [:n, :d, :clamp_d, :s]`
  - `defstruct [:n, :d, :clamp_d, :s]`
  - `@type t :: %__MODULE__{n: pos_integer(), d: float(), clamp_d: float(), s: non_neg_integer()}`
  - `@type reason :: :invalid_order | :invalid_step_count`
  - `@type state :: map()` with at least `:n, :d, :s, :figure, :map, :di, :dfrac, :is_int, :outer_s, :points, :top, :bottom`
  - `new(pos_integer(), float(), integer()) :: {:ok, t()} | {:error, reason()}`
  - `new!(pos_integer(), float(), integer()) :: t()`
  - `clamp_d(pos_integer(), float()) :: float()`
  - `clamp_s(integer(), integer()) :: non_neg_integer()`
  - `start(pos_integer(), float(), integer()) :: state()`
  - `steps(pos_integer(), float(), integer()) :: [Steps.Step.t()]`
  - `result(state()) :: PlanarMap.t()`
  - `build_unit(t()) :: PlanarMap.t()`
  - `@impl RadialFigure` `build_unit/1`, `n/1`

- [ ] **Step 1: Write the failing constructor and clamp tests**

```elixir
test "new/3 stores the clamped d and s beside the raw d" do
  assert {:ok, star} = Star.new(8, 99.0, 9)
  assert star.d == 99.0
  assert star.clamp_d == 3.99
  assert star.s == 3
  assert {:ok, %Star{d: 3.0, clamp_d: 3.0, s: 2}} = Star.new(8, 3.0, 2)
  assert {:ok, %Star{clamp_d: 1.0}} = Star.new(8, 0.5, 2)
end

test "invalid order and negative steps are refused" do
  assert Star.new(2, 3.0, 2) == {:error, :invalid_order}
  assert Star.new(8, 3.0, -1) == {:error, :invalid_step_count}
  assert_raise ArgumentError, ~r/invalid_order/, fn -> Star.new!(2, 3.0, 2) end
end

test "clamp_d and clamp_s are the source's expressions" do
  assert Star.clamp_d(8, 99.0) == 3.99
  assert Star.clamp_d(8, 0.5) == 1.0
  assert Star.clamp_s(9, 3) == 3
  assert Star.clamp_s(2, 3) == 2
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix/engine/figures/star_test.exs`
Expected: FAIL, the module is undefined.

- [ ] **Step 3: Write the failing unit and step tests**

```elixir
test "the default unit is an open five-vertex chain" do
  map = Star.build_unit(Star.new!(8, 3.0, 2))
  assert PlanarMap.verify(map) == :ok
  assert PlanarMap.num_vertices(map) == 5
  assert PlanarMap.num_edges(map) == 4
end

test "s = 3 closes the unit at the rotated apex" do
  map = Star.build_unit(Star.new!(8, 3.0, 3))
  assert PlanarMap.verify(map) == :ok
  assert PlanarMap.num_vertices(map) == 6
  assert PlanarMap.num_edges(map) == 5
end

test "a fractional d inserts the cent vertex and two closure edges" do
  map = Star.build_unit(Star.new!(8, 2.5, 2))
  assert PlanarMap.verify(map) == :ok
  assert PlanarMap.num_vertices(map) == 7
  assert PlanarMap.num_edges(map) == 6
end

test "the near-integral snap disables the closure" do
  map = Star.build_unit(Star.new!(8, 2.99999999, 2))
  assert PlanarMap.verify(map) == :ok
  assert PlanarMap.num_vertices(map) == 5
end

test "the stepped builder and the plain builder agree" do
  plain = Star.build_unit(Star.new!(8, 3.0, 2))

  stepped =
    Star.steps(8, 3.0, 2)
    |> Steps.run!(Star.start(8, 3.0, 2))
    |> Steps.final()
    |> Star.result()

  assert stepped == plain
end

test "a failed crossing raises rather than substituting a point" do
  # Found by the golden scenario figure-star-crash; the source dereferences a
  # null here. The reason names the failure.
  assert_raise ArgumentError, ~r/degenerate_crossing/, fn ->
    Star.build_unit(Star.new!(12, 5.9, 6))
  end
end
```

The last test's parameters are illustrative. Replace them with the parameters
the harness finds to crash, and record them in the test name. Do not invent a
substitute.

- [ ] **Step 4: Run them to see them fail**

Run: `mix test test/girihelix/engine/figures/star_test.exs`
Expected: FAIL, `Star.build_unit/1` is undefined.

- [ ] **Step 5: Implement `Star`**

Implement in this order, each as a named private function: `clamp_d/2`,
`clamp_s/2`, the snap (`{di, dfrac, is_int}` in three function heads, the
`dfrac < 1e-7` clause first, then `1.0 - dfrac < 1e-7`, then the default),
`crossings/1`, the shared mirrored-chain assembly, and the closure. The snap
must use the **pre-increment** `di` for `clamp_s` and `outer_s`. Build every
segment with `Segment.new!`; raise `ArgumentError, "star: degenerate_crossing"`
where the source stores `null`. The closure's `cent` chord uses the raw
`figure.d`, not `clamp_d`. The step list is `:clamp`, `:chord`, `:crossings`,
`:assemble`, `:closure`.

- [ ] **Step 6: Run the tests to see them pass**

Run: `mix test test/girihelix/engine/figures/star_test.exs`
Expected: PASS.

- [ ] **Step 7: Gates and commit**

Run `mix precommit.fast && mix dialyzer`, then:

```bash
git add lib/girihelix/engine/figures/star.ex test/girihelix/engine/figures/star_test.exs
git commit -m "feat: add the Star figure builder"
```

### Task 3: The harness `figure` operation and Star goldens

**Files:**

- Modify (local only, never committed): `reference/oracle/src/csk/taprats/geometry/HarnessDriver.java`
- Create (local only, never committed): `reference/oracle/scenarios/figure-star-*.ops`
- Modify: `test/support/taprats_harness.ex`
- Modify: `test/girihelix/taprats_harness_test.exs`
- Create: `test/girihelix/engine/figures_golden_test.exs`

**Interfaces:**

- Consumes: `Star` from Task 2; `Girihelix.Engine.Figures.Figure`.
- Produces:
  - `Girihelix.TapratsHarness`
    - `@type figure_expr :: {:star, integer(), float(), integer()} | {:rosette, integer(), float(), integer()} | {:scale, figure_expr(), float()} | {:connect, figure_expr()}`
    - `@type op :: ... | {:figure, :map | :unit, figure_expr()}`
    - `build_figure(figure_expr()) :: PlanarMap.t()`
    - a `%{figure: {:ok, map_dump()} | {:error, :null}}` dump shape
  - `Girihelix.Engine.FiguresGoldenTest`, tagged `:taprats`

- [ ] **Step 1: Write the failing parser tests**

```elixir
test "parse_script/1 reads figure expressions recursively" do
  assert TapratsHarness.parse_script("figure map star 8 3.0 2\n") ==
           [{:figure, :map, {:star, 8, 3.0, 2}}]

  assert TapratsHarness.parse_script("figure unit rosette 12 -0.8 4\n") ==
           [{:figure, :unit, {:rosette, 12, -0.8, 4}}]

  assert TapratsHarness.parse_script("figure map scale rosette 8 0.0 3 1.5\n") ==
           [{:figure, :map, {:scale, {:rosette, 8, 0.0, 3}, 1.5}}]

  assert TapratsHarness.parse_script("figure map connect scale star 8 3.0 2 1.4\n") ==
           [{:figure, :map, {:connect, {:scale, {:star, 8, 3.0, 2}, 1.4}}}]
end

test "parse_script/1 rejects a malformed figure expression" do
  assert_raise ArgumentError, ~r/figure/, fn ->
    TapratsHarness.parse_script("figure map star 8 3.0")
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix/taprats_harness_test.exs`
Expected: FAIL, `figure` is an unknown operation.

- [ ] **Step 3: Add the Java operation and scenarios, then build and run the harness**

In `HarnessDriver.java`, extract the body of `dump(Map)` into
`private static String mapDump(Map m)` and make `dump(Map)` delegate. Add a
terminal branch before the per-map switch:

```java
if( t[0].equals( "figure" ) ) {
    Figure f = parseFigure( t, 2, t.length );
    Map m;
    try {
        m = t[1].equals( "unit" ) ? ((RadialFigure) f).buildUnit() : f.getMap();
    } catch( RuntimeException e ) {
        Files.write( Paths.get( args[1] ), "figure error null\n".getBytes( StandardCharsets.UTF_8 ) );
        return;
    }
    String header = t[1].equals( "unit" ) ? "figure unit ok\n" : "figure ok\n";
    Files.write( Paths.get( args[1] ), ( header + mapDump( m ) ).getBytes( StandardCharsets.UTF_8 ) );
    return;
}
```

`parseFigure` recursively parses `star n d s`, `rosette n q s`,
`scale <expr> s` and `connect <expr>`, and throws `IllegalArgumentException`
naming the bad token otherwise. Add the scenarios from the design's table.
Run `reference/oracle/build` then `reference/oracle/run`; confirm each `.dump`
is either `figure ok`, `figure unit ok`, or `figure error null`, and that
`figure-star-crash` is the last.

Nothing under `reference/` is staged.

- [ ] **Step 4: Write the failing golden test**

```elixir
defmodule Girihelix.Engine.FiguresGoldenTest do
  use ExUnit.Case, async: true

  @moduletag :taprats

  @scenarios ~w(figure-star-default figure-star-unit figure-star-fractional
    figure-star-closure figure-star-clamped figure-star-crash)

  for name <- @scenarios do
    test "matches Taprats: #{name}" do
      {ops, expected} = Girihelix.TapratsHarness.load(unquote(name))

      assert Girihelix.TapratsHarness.compare(expected, Girihelix.TapratsHarness.run_script(ops)) ==
               :ok
    end
  end
end
```

- [ ] **Step 5: Run it to see it fail**

Run: `mix test test/girihelix/engine/figures_golden_test.exs`
Expected: FAIL, either the scenario files are absent or the dump shape is
unsupported.

- [ ] **Step 6: Implement the Elixir harness half**

Add the expression parser, `build_figure/1`, the `run_script` clauses for the
two terminal figure ops, and `compare/2`. `build_figure/1` calls the port's
`new!/1`, `new!/2` or `new!/3`, then `Figure.map/1` or `Figure.unit/1`; it
rescues any exception into `%{figure: {:error, :null}}`, because every source
side failure is an NPE. Reuse the map comparison for the success shape.

- [ ] **Step 7: Run the tests to see them pass**

Run: `mix test test/girihelix/taprats_harness_test.exs test/girihelix/engine/figures_golden_test.exs`
Expected: PASS, or SKIP when `reference/oracle/fixtures` is absent.

- [ ] **Step 8: Gates and commit**

Run `mix precommit.fast && mix dialyzer`, then:

```bash
git add test/support/taprats_harness.ex test/girihelix/taprats_harness_test.exs test/girihelix/engine/figures_golden_test.exs
git commit -m "test: add the figure harness operation and Star goldens"
```

### Task 4: `Rosette`

**Files:**

- Create: `lib/girihelix/engine/figures/rosette.ex`
- Create: `test/girihelix/engine/figures/rosette_test.exs`
- Modify: `test/girihelix/engine/figures_golden_test.exs`

**Interfaces:**

- Consumes: Tasks 1 and 3.
- Produces: `Girihelix.Engine.Figures.Rosette` with
  - `@enforce_keys [:n, :q, :s]`
  - `defstruct [:n, :q, :s]`
  - `@type t :: %__MODULE__{n: pos_integer(), q: float(), s: non_neg_integer()}`
  - `@type reason :: :invalid_order | :invalid_step_count`
  - `@type state :: map()` with at least `:n, :q, :s, :figure, :map, :frame, :points, :top, :bottom, :skipped`
  - `new/3`, `new!/3`, `clamp_q/1`, `clamp_s/2`, `with_q/2`, `with_s/2`
  - `start/3`, `steps/3`, `result/1`, `build_unit/1`, `n/1`

- [ ] **Step 1: Write the failing constructor tests**

```elixir
test "new/3 clamps q and s and stores the clamped values" do
  assert {:ok, rosette} = Rosette.new(8, 2.0, 9)
  assert rosette.q == 0.99
  assert rosette.s == 3
  assert {:ok, %Rosette{q: -0.99, s: 3}} = Rosette.new(8, -2.0, 3)
  assert Rosette.clamp_s(12, 9) == 5
  assert Rosette.clamp_s(5, 9) == 2
end

test "with_s/2 clamps like the constructor" do
  rosette = Rosette.new!(8, 0.0, 1)
  assert Rosette.with_s(rosette, 99).s == 3
  assert Rosette.with_q(rosette, -9.0).q == -0.99
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix/engine/figures/rosette_test.exs`
Expected: FAIL, the module is undefined.

- [ ] **Step 3: Write the failing builder tests**

```elixir
test "the default unit verifies and its stepped and plain builds agree" do
  plain = Rosette.build_unit(Rosette.new!(8, 0.0, 3))
  assert PlanarMap.verify(plain) == :ok

  stepped =
    Rosette.steps(8, 0.0, 3)
    |> Steps.run!(Rosette.start(8, 0.0, 3))
    |> Steps.final()
    |> Rosette.result()

  assert stepped == plain
end

test "the documented FIXME case skips a step and still builds" do
  map = Rosette.build_unit(Rosette.new!(12, -0.8, 4))
  assert PlanarMap.verify(map) == :ok

  state =
    Rosette.steps(12, -0.8, 4)
    |> Steps.run!(Rosette.start(12, -0.8, 4))
    |> Steps.final()

  assert state.skipped > 0
end

test "the unit is symmetric about the x axis" do
  map = Rosette.build_unit(Rosette.new!(8, 0.0, 3))
  ys = Enum.map(PlanarMap.vertices(map), &PlanarMap.position!(map, &1).y)

  assert Enum.sort(ys) == Enum.sort(Enum.map(ys, &-&1))
end
```

- [ ] **Step 4: Run them to see them fail**

Run: `mix test test/girihelix/engine/figures/rosette_test.exs`
Expected: FAIL, `build_unit/1` is undefined.

- [ ] **Step 5: Implement `Rosette`**

Named private functions in the order the design lists: `frame/1`
(`r_outer`, `up_outer`, `bisector`, `th`, `stable_isect`, `stable_angle`),
`blend/2` (two function heads on `q >= 0.0`), `key/1`, `walk/1` (the
accumulating `Transform.apply_to/2`, never a recomputed power), and the shared
assembly. `bisector` is `(up_outer - (0, r_outer)) * 0.5`. `key_end` is
`Point.convex_sum(key_point, stable_isect, 10.0)`. Skip a `nil` crossing
without advancing the point list, and increment `skipped`. Raise
`ArgumentError, "rosette: degenerate_key"` for a null `key_point`. The step ids
are `:clamp`, `:frame`, `:blend`, `:key`, `:walk`, `:assemble`.

- [ ] **Step 6: Run the tests to see them pass**

Run: `mix test test/girihelix/engine/figures/rosette_test.exs`
Expected: PASS.

- [ ] **Step 7: Add the rosette golden scenarios**

Append `figure-rosette-default`, `figure-rosette-negative-q`,
`figure-rosette-clamped` and `figure-rosette-fixme` to the golden module's
`@scenarios`. Rebuild and rerun the harness for the new scenarios.

- [ ] **Step 8: Run the goldens**

Run: `mix test test/girihelix/engine/figures_golden_test.exs`
Expected: PASS.

- [ ] **Step 9: Gates and commit**

Run `mix precommit.fast && mix dialyzer`, then:

```bash
git add lib/girihelix/engine/figures/rosette.ex test/girihelix/engine/figures/rosette_test.exs test/girihelix/engine/figures_golden_test.exs
git commit -m "feat: add the Rosette figure builder"
```

### Task 5: `ScaleFigure`

**Files:**

- Create: `lib/girihelix/engine/figures/scale_figure.ex`
- Create: `test/girihelix/engine/figures/scale_figure_test.exs`
- Modify: `test/girihelix/engine/figures_golden_test.exs`

**Interfaces:**

- Consumes: `Rosette`, `Star`, `Figure`, `RadialFigure`; `PlanarMap`.
- Produces: `Girihelix.Engine.Figures.ScaleFigure` with
  - `@enforce_keys [:child, :s]`
  - `defstruct [:child, :s]`
  - `@type t :: %__MODULE__{child: RadialFigure.t(), s: float()}`
  - `@type reason :: :not_radial`
  - `@type state :: map()` with at least `:child, :requested_s, :figure, :map, :passthrough, :tip, :below, :endpoint`
  - `new(Figure.t(), float()) :: {:ok, t()} | {:error, reason()}`
  - `new!/2`
  - `normalise_s(float()) :: float()`
  - `with_s(t(), float()) :: t()`
  - `with_child(t(), Figure.t()) :: {:ok, t()} | {:error, reason()}`
  - `build_unit(t()) :: PlanarMap.t()`
  - `build_unit(RadialFigure.t(), float()) :: PlanarMap.t()`
  - `start(RadialFigure.t(), float()) :: state()`
  - `steps(RadialFigure.t(), float()) :: [Steps.Step.t()]`
  - `result(state()) :: PlanarMap.t()`
  - `n/1` delegating to the child

- [ ] **Step 1: Write the failing constructor and clamp tests**

```elixir
test "s within 1e-7 of one is stored as exactly 1.0" do
  assert ScaleFigure.normalise_s(1.00000005) == 1.0
  assert ScaleFigure.normalise_s(1.001) == 1.001
  assert {:ok, %ScaleFigure{s: 1.0}} = ScaleFigure.new(Rosette.new!(8, 0.0, 3), 0.99999999)
end

test "an explicit child is not radial" do
  map = PlanarMap.new() |> PlanarMap.insert_vertex(Point.new(0.0, 0.0)) |> elem(0)

  assert ScaleFigure.new(ExplicitFigure.new!(map), 1.5) == {:error, :not_radial}
end
```

`ExplicitFigure` is defined in Task 7. Move this test to Task 7 if the plan is
executed strictly in order, or reorder Task 7 before Task 5. The recommended
order is Task 7 before this task; the design's task numbering is by importance,
not dependency. See the dependency note at the end of Task 7.

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix/engine/figures/scale_figure_test.exs`
Expected: FAIL, the module is undefined.

- [ ] **Step 3: Write the failing builder tests**

```elixir
test "s = 1 passes the child's unit through unchanged" do
  child = Rosette.new!(8, 0.0, 3)

  assert ScaleFigure.build_unit(child, 1.0) == Rosette.build_unit(child)

  stepped =
    ScaleFigure.steps(child, 1.0)
    |> Steps.run!(ScaleFigure.start(child, 1.0))
    |> Steps.final()

  assert stepped.passthrough
  assert ScaleFigure.result(stepped) == Rosette.build_unit(child)
end

test "a scaled rosette stays inside the unit n-gon and verifies" do
  child = Rosette.new!(8, 0.0, 3)
  map = ScaleFigure.build_unit(child, 1.5)

  assert PlanarMap.verify(map) == :ok
  max_x = map |> PlanarMap.vertices() |> Enum.map(&PlanarMap.position!(map, &1).x) |> Enum.max()
  assert max_x <= 1.0 + 1.0e-9
end

test "the stepped builder and the plain builder agree" do
  child = Rosette.new!(8, 0.0, 3)

  plain = ScaleFigure.build_unit(child, 1.5)

  stepped =
    ScaleFigure.steps(child, 1.5)
    |> Steps.run!(ScaleFigure.start(child, 1.5))
    |> Steps.final()
    |> ScaleFigure.result()

  assert stepped == plain
end
```

- [ ] **Step 4: Run them to see them fail**

Run: `mix test test/girihelix/engine/figures/scale_figure_test.exs`
Expected: FAIL, `build_unit/2` is undefined.

- [ ] **Step 5: Implement `ScaleFigure`**

`new/2` refuses a non-radial child and stores `normalise_s/1`. `build_unit/2`
follows the design's eight steps. Use `PlanarMap.vertices/1` for the tip scan
(`Loose.equals/2` on positions), `PlanarMap.scale/2` for the scale,
`PlanarMap.ring!/2` and `PlanarMap.endpoints!/2` for the lower-neighbour scan
(first in ring order with `y < 0.0`), and build segments with `Segment.new!`.
Where the endpoint equals the tip (the clip fallback), skip the rotated-copy
intersection rather than building a zero-length segment, because the source's
determinant is zero and its intersection returns `nil`. Raise
`ArgumentError, "scale: no_tip"` and `"scale: no_lower_neighbour"`. The final
endpoint guard is handle equality (`iv == last_top`), not coordinate equality.
Step ids: `:clamp`, `:child`, `:scale`, `:clip`, `:extend`, `:endpoint`.

- [ ] **Step 6: Run the tests to see them pass**

Run: `mix test test/girihelix/engine/figures/scale_figure_test.exs`
Expected: PASS.

- [ ] **Step 7: Add the scale goldens**

Add `figure-scale-passthrough` and `figure-scale-rosette` to `@scenarios`,
rebuild and rerun the harness, then:

Run: `mix test test/girihelix/engine/figures_golden_test.exs`
Expected: PASS.

- [ ] **Step 8: Gates and commit**

Run `mix precommit.fast && mix dialyzer`, then:

```bash
git add lib/girihelix/engine/figures/scale_figure.ex test/girihelix/engine/figures/scale_figure_test.exs test/girihelix/engine/figures_golden_test.exs
git commit -m "feat: add the ScaleFigure builder"
```

### Task 6: `ConnectFigure`

**Files:**

- Create: `lib/girihelix/engine/figures/connect_figure.ex`
- Create: `test/girihelix/engine/figures/connect_figure_test.exs`
- Modify: `test/girihelix/engine/figures_golden_test.exs`

**Interfaces:**

- Consumes: `ScaleFigure.build_unit/2`, `ScaleFigure.normalise_s/1`,
  `RadialFigure`, `PlanarMap`.
- Produces: `Girihelix.Engine.Figures.ConnectFigure` with
  - `@enforce_keys [:child, :s]`
  - `defstruct [:child, :s]`
  - `@type t :: %__MODULE__{child: RadialFigure.t(), s: float()}`
  - `@type reason :: :not_radial`
  - `@type state :: map()` with at least `:child, :figure, :map, :fallback, :max_x`
  - `new(Figure.t()) :: {:ok, t()} | {:error, reason()}`
  - `new!/1`
  - `compute_scale(RadialFigure.t()) :: float()`
  - `child_changed(t()) :: t()`
  - `start(RadialFigure.t(), float()) :: state()`
  - `steps(RadialFigure.t(), float()) :: [Steps.Step.t()]`
  - `result(state()) :: PlanarMap.t()`
  - `build_unit(t()) :: PlanarMap.t()`
  - `n/1`

- [ ] **Step 1: Write the failing constructor tests**

```elixir
test "new/1 derives and stores the scale, and refuses a non-radial child" do
  rosette = Rosette.new!(8, 0.0, 3)
  assert {:ok, connect} = ConnectFigure.new(rosette)
  assert connect.s == ScaleFigure.normalise_s(ConnectFigure.compute_scale(rosette))
  assert connect.s > 1.0

  map = PlanarMap.new() |> PlanarMap.insert_vertex(Point.new(0.0, 0.0)) |> elem(0)
  assert ConnectFigure.new(ExplicitFigure.new!(map)) == {:error, :not_radial}
end

test "child_changed/1 re-derives the scale" do
  connect = ConnectFigure.new!(Rosette.new!(8, 0.0, 3))
  changed = ConnectFigure.child_changed(%{connect | child: Rosette.new!(8, -0.3, 3)})
  assert changed.s == ScaleFigure.normalise_s(ConnectFigure.compute_scale(changed.child))
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix/engine/figures/connect_figure_test.exs`
Expected: FAIL, the module is undefined.

- [ ] **Step 3: Write the failing builder tests**

```elixir
test "a connected rosette verifies and normalises to x <= 1" do
  connect = ConnectFigure.new!(Rosette.new!(8, 0.0, 3))
  map = ConnectFigure.build_unit(connect)

  assert PlanarMap.verify(map) == :ok
  max_x = map |> PlanarMap.vertices() |> Enum.map(&PlanarMap.position!(map, &1).x) |> Enum.max()
  assert_in_delta max_x, 1.0, 1.0e-9
end

test "the fold keeps the apex on the axis" do
  connect = ConnectFigure.new!(Rosette.new!(8, 0.0, 3))
  map = ConnectFigure.build_unit(connect)

  apex = Enum.find(PlanarMap.vertices(map), fn v ->
    PlanarMap.position!(map, v).x > 0.999
  end)

  assert apex
  assert_in_delta PlanarMap.position!(map, apex).y, 0.0, 1.0e-7
end

test "the stepped builder and the plain builder agree" do
  connect = ConnectFigure.new!(Rosette.new!(8, 0.0, 3))

  stepped =
    ConnectFigure.steps(connect.child, connect.s)
    |> Steps.run!(ConnectFigure.start(connect.child, connect.s))
    |> Steps.final()
    |> ConnectFigure.result()

  assert stepped == ConnectFigure.build_unit(connect)
end
```

- [ ] **Step 4: Run them to see them fail**

Run: `mix test test/girihelix/engine/figures/connect_figure_test.exs`
Expected: FAIL, the module is undefined.

- [ ] **Step 5: Implement `ConnectFigure`**

`compute_scale/1` scans `PlanarMap.vertices/1` in order for a tip candidate
(`Loose.equals/2`) that has a lower neighbour, and returns `1.0` on any failure.
The intersection is against the **full-length** ray and the moving segment is
`Tr(tip) → Tr(mirror(seg_end))`; do not reuse ScaleFigure's clipped endpoint.
`rotate_half/1` is the five passes in the source's order: select `y > -1e-7`,
insert the copies, collect edges with both ends selected, insert the permuted
edges, delete originals with `y > 1e-7` strictly. Use a map keyed by vertex
handle for the movers. The half-step rotation is `PlanarMap.transform!/2` when
`s != 1.0`. `scale_to_unit/1` raises `ArgumentError, "connect: zero_extent"`
when the maximum x is `0.0`. Step ids: `:clamp`, `:scale_clip`, `:fold`,
`:half_step`, `:normalise`.

- [ ] **Step 6: Run the tests to see them pass**

Run: `mix test test/girihelix/engine/figures/connect_figure_test.exs`
Expected: PASS.

- [ ] **Step 7: Add the connect goldens**

Add `figure-connect-rosette`, `figure-connect-star` and
`figure-connect-nested` to `@scenarios`, rebuild and rerun the harness, then:

Run: `mix test test/girihelix/engine/figures_golden_test.exs`
Expected: PASS.

- [ ] **Step 8: Gates and commit**

Run `mix precommit.fast && mix dialyzer`, then:

```bash
git add lib/girihelix/engine/figures/connect_figure.ex test/girihelix/engine/figures/connect_figure_test.exs test/girihelix/engine/figures_golden_test.exs
git commit -m "feat: add the ConnectFigure builder"
```

### Task 7: `ExplicitFigure`

**Files:**

- Create: `lib/girihelix/engine/figures/explicit_figure.ex`
- Create: `test/girihelix/engine/figures/explicit_figure_test.exs`
- Modify: `lib/girihelix/engine/figures/figure.ex` (the `ExplicitFigure` clause
  and the extended `@type t`)

**Interfaces:**

- Consumes: `PlanarMap`, `Figure`.
- Produces: `Girihelix.Engine.Figures.ExplicitFigure` with
  - `@enforce_keys [:map]`
  - `defstruct [:map]`
  - `@type t :: %__MODULE__{map: PlanarMap.t()}`
  - `@type reason :: :not_a_map`
  - `new(PlanarMap.t()) :: {:ok, t()} | {:error, reason()}`
  - `new!/1`
  - `build_unit(t()) :: PlanarMap.t()`
  - `n/1` is not implemented; the module is not a `RadialFigure`

**Dependency note:** execute this task **before Task 5**. `ScaleFigure.new/2`
and `ConnectFigure.new/1` need `ExplicitFigure` to test `:not_radial`, and
`Figure.t()` needs the fifth variant. The task numbers follow importance, not
execution order.

- [ ] **Step 1: Write the failing tests**

```elixir
test "new/1 accepts a map and returns the same map from build_unit/1" do
  {map, _vertex} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(1.0, 2.0))

  assert {:ok, figure} = ExplicitFigure.new(map)
  assert figure.map == map
  assert ExplicitFigure.build_unit(figure) == map
  assert Figure.unit(figure) == map
  assert Figure.map(figure) == map
end

test "new/1 refuses a non-map and new!/1 raises" do
  assert ExplicitFigure.new(:nope) == {:error, :not_a_map}
  assert_raise ArgumentError, ~r/not_a_map/, fn -> ExplicitFigure.new!(:nope) end
end

test "an explicit figure is not radial" do
  assert Figure.radial?(ExplicitFigure.new!(PlanarMap.new())) == false
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix/engine/figures/explicit_figure_test.exs`
Expected: FAIL, the module is undefined.

- [ ] **Step 3: Implement `ExplicitFigure` and extend `Figure`**

`new/1` has a `%PlanarMap{}`-guarded clause returning `{:ok, _}` and a fallback
returning `{:error, :not_a_map}`. `build_unit/1` returns the stored map.
`Figure.map/1` gains the `ExplicitFigure` clause returning the stored map,
`Figure.@type t` gains the fifth struct, and `RadialFigure.@type t` is replaced
with its four-variant union. Both were `struct()` in Task 1 because the structs
did not exist yet.

- [ ] **Step 4: Run the tests to see them pass**

Run: `mix test test/girihelix/engine/figures/explicit_figure_test.exs test/girihelix/engine/figures/figure_test.exs`
Expected: PASS.

- [ ] **Step 5: Gates and commit**

Run `mix precommit.fast && mix dialyzer`, then:

```bash
git add lib/girihelix/engine/figures/explicit_figure.ex lib/girihelix/engine/figures/figure.ex test/girihelix/engine/figures/explicit_figure_test.exs
git commit -m "feat: add the ExplicitFigure wrapper"
```

### Task 8: The `star` and `rosette` exhibits

**Files:**

- Create: `lib/girihelix_web/workbench/exhibits/figures.ex`
- Create: `lib/girihelix_web/workbench/exhibits/star.ex`
- Create: `lib/girihelix_web/workbench/exhibits/rosette.ex`
- Modify: `lib/girihelix_web/workbench/registry.ex`
- Create: `test/girihelix_web/workbench/exhibits/star_test.exs`
- Create: `test/girihelix_web/workbench/exhibits/rosette_test.exs`

**Interfaces:**

- Consumes: `Girihelix.Engine.Figures.{Star, Rosette, Figure}`,
  `Girihelix.Engine.Steps`, `GirihelixWeb.Workbench.{Exhibit, Param}`,
  `Exhibits.Format`, the draw ops.
- Produces:
  - `GirihelixWeb.Workbench.Exhibits.Figures`
    - `map_ops(PlanarMap.t()) :: [Op.t()]`
    - `unit_ops(PlanarMap.t()) :: [Op.t()]`
    - `vertex_ops(PlanarMap.t(), keyword()) :: [Op.t()]`
    - `rows_for(PlanarMap.t()) :: [{String.t(), String.t()}]` (the shared
      `vertices`, `edges`, `verify` rows)
  - `GirihelixWeb.Workbench.Exhibits.Star` and `.Rosette`, each implementing
    all callbacks
  - Registry entries after `FillRegion`, in the order `Star`, `Rosette`

- [ ] **Step 1: Write the failing star exhibit test**

```elixir
test "the star exhibit builds, draws and reproduces" do
  params = Param.values(Star.params(), :default)
  state = Star.initial(params)
  frames = Star.steps(params) |> Steps.run!(state)
  last = List.last(frames)

  assert Star.slug() == "star"
  assert Star.category() == :figures
  assert_steps(Star.steps(params), [:clamp, :chord, :crossings, :assemble, :closure])

  assert {:both, ops, rows} = Star.draw(last, params)
  assert Enum.any?(ops, &match?({:line, _, _, _}, &1))
  assert {"vertices", _} = List.keyfind(rows, "vertices", 0)
  assert Star.reproduce(params) =~ "Girihelix.Engine.Figures.Star.new!(8, 3.0, 2)"
end

test "every frame draws, including frame zero" do
  params = Param.values(Star.params(), :default)

  for frame <- Star.steps(params) |> Steps.run!(Star.initial(params)) do
    assert {:both, _ops, _rows} = Star.draw(frame, params)
  end
end
```

Use a local `assert_steps/2` helper matching the step ids, or assert
`Enum.map(steps, & &1.id)` directly.

- [ ] **Step 2: Run it to see it fail**

Run: `mix test test/girihelix_web/workbench/exhibits/star_test.exs`
Expected: FAIL, the module is undefined.

- [ ] **Step 3: Implement the shared helper and the `star` exhibit**

`Star.initial/1` calls `Star.start(n, d, s)`; `steps/1` calls `Star.steps/3`;
`draw/2` reads `frame.state`, draws the whole map with
`Figure.map(state.figure)` when the figure exists, overlays the unit heavier,
the tip, the base chord, the crossings and the closure, and merges
`Figures.rows_for/1` with the star's own rows. `reproduce/1` returns the
`Star.build_unit(Star.new!(n, d, s))` call. Register `Star` in the registry.

- [ ] **Step 4: Run it to see it pass**

Run: `mix test test/girihelix_web/workbench/exhibits/star_test.exs test/girihelix_web/workbench/registry_test.exs`
Expected: PASS.

- [ ] **Step 5: Write the failing rosette exhibit test**

```elixir
test "the rosette exhibit reports the clamp and the skip count" do
  params = %{Param.values(Rosette.params(), :default) | n: 12, q: -0.8, s: 4}
  last = Rosette.steps(params) |> Steps.run!(Rosette.initial(params)) |> List.last()

  assert {:both, ops, rows} = Rosette.draw(last, params)
  assert Enum.any?(ops, &match?({:guide, _, _, _}, &1))
  assert {"steps skipped", skipped} = List.keyfind(rows, "steps skipped", 0)
  assert skipped != "0"
  assert Rosette.reproduce(params) =~ "Rosette.new!(12, -0.8, 4)"
end
```

- [ ] **Step 6: Run it to see it fail, then implement and register `Rosette`**

Run: `mix test test/girihelix_web/workbench/exhibits/rosette_test.exs`
Expected: FAIL, the module is undefined.

Implement `slug/0`, `title/0`, `summary/0`, `category/0`, `params/0`
(`n` 3..24 default 8, `q` -0.9..0.9 step 0.05 default 0.0, `s` 1..6 default 3),
`initial/1`, `steps/1`, `draw/2` and `reproduce/1` as the design's `rosette`
section specifies. Register it after `Star`.

- [ ] **Step 7: Run the tests and the registry property test**

Run: `mix test test/girihelix_web/workbench/`
Expected: PASS, including the registry property test over every exhibit at its
defaults and range extremes.

- [ ] **Step 8: Gates and commit**

Run `mix precommit.fast && mix dialyzer`, then:

```bash
git add lib/girihelix_web/workbench/exhibits/figures.ex lib/girihelix_web/workbench/exhibits/star.ex lib/girihelix_web/workbench/exhibits/rosette.ex lib/girihelix_web/workbench/registry.ex test/girihelix_web/workbench/exhibits/star_test.exs test/girihelix_web/workbench/exhibits/rosette_test.exs
git commit -m "feat: add the star and rosette workbench exhibits"
```

### Task 9: The `scale`, `connect` and `radial` exhibits

**Files:**

- Create: `lib/girihelix_web/workbench/exhibits/scale.ex`
- Create: `lib/girihelix_web/workbench/exhibits/connect.ex`
- Create: `lib/girihelix_web/workbench/exhibits/radial.ex`
- Modify: `lib/girihelix_web/workbench/registry.ex`
- Create: `test/girihelix_web/workbench/exhibits/scale_test.exs`
- Create: `test/girihelix_web/workbench/exhibits/connect_test.exs`
- Create: `test/girihelix_web/workbench/exhibits/radial_test.exs`

**Interfaces:**

- Consumes: `ScaleFigure`, `ConnectFigure`, `Figure`, `RadialFigure`,
  `Exhibits.Figures`.
- Produces:
  - `GirihelixWeb.Workbench.Exhibits.Scale`
  - `GirihelixWeb.Workbench.Exhibits.Connect`
  - `GirihelixWeb.Workbench.Exhibits.Radial`
  - Registry entries after `Rosette`, in the order `Scale`, `Connect`, `Radial`

The three exhibits share one child-parameter helper in
`Exhibits.Figures`: `child_params/1` returns the `child`, `n`, `q`, `d` and
`child_s` declarations, and `build_child/1` returns the child figure from a
typed params map. It is workbench code and may branch on the `child` enum.

- [ ] **Step 1: Write the failing scale exhibit test**

```elixir
test "the scale exhibit draws the child, the border and the extension" do
  params = Param.values(Scale.params(), :default)
  frames = Scale.steps(params) |> Steps.run!(Scale.initial(params))

  assert Enum.map(Scale.steps(params), & &1.id) ==
           [:clamp, :child, :scale, :clip, :extend, :endpoint]

  assert {:both, ops, rows} = Scale.draw(List.last(frames), params)
  assert ops != []
  assert Enum.any?(ops, &match?({:point, _, _, _}, &1))
  assert {"passthrough", _} = List.keyfind(rows, "passthrough", 0)
  assert Scale.reproduce(params) =~ "ScaleFigure.build_unit"
end

test "the scale exhibit draws frame zero before the child is built" do
  params = Param.values(Scale.params(), :default)
  first = Scale.steps(params) |> Steps.run!(Scale.initial(params)) |> hd()

  assert {:both, _ops, _rows} = Scale.draw(first, params)
end
```

- [ ] **Step 2: Run it to see it fail, then implement and register `Scale`**

Run: `mix test test/girihelix_web/workbench/exhibits/scale_test.exs`
Expected: FAIL, the module is undefined.

Implement with the parameters in the design's `scale` section, `initial/1`
calling `ScaleFigure.start(child, s)`, `steps/1` calling `ScaleFigure.steps/2`,
and the diagnostic overlays listed there. Register it.

- [ ] **Step 3: Write the failing connect exhibit test**

```elixir
test "the connect exhibit has no s parameter and reports the derived scale" do
  refute Enum.any?(Connect.params(), &(&1.name == :s))

  params = Param.values(Connect.params(), :default)
  last = Connect.steps(params) |> Steps.run!(Connect.initial(params)) |> List.last()

  assert {:both, _ops, rows} = Connect.draw(last, params)
  assert {"derived s", value} = List.keyfind(rows, "derived s", 0)
  assert String.to_float(value) > 1.0
  assert Connect.reproduce(params) =~ "ConnectFigure.new!"
end
```

- [ ] **Step 4: Run it to see it fail, then implement and register `Connect`**

Run: `mix test test/girihelix_web/workbench/exhibits/connect_test.exs`
Expected: FAIL, the module is undefined.

Implement the design's `connect` section. The exhibit's `steps/1` calls
`ConnectFigure.steps(child, connect.s)` and its `initial/1` calls
`ConnectFigure.start(child, connect.s)`, so the stored scale is what the panel
and the transport show. Register it.

- [ ] **Step 5: Write the failing radial exhibit test**

```elixir
test "the radial exhibit steps the ladder once and labels every copy" do
  params = Param.values(Radial.params(), :default)
  frames = Radial.steps(params) |> Steps.run!(Radial.initial(params))

  assert Enum.map(Radial.steps(params), & &1.id) == [:replicate]
  assert {:both, ops, rows} = Radial.draw(List.last(frames), params)
  assert Enum.count(ops, &match?({:label, _, "Tr" <> _, _}, &1)) == params.n
  assert {"transforms", _} = List.keyfind(rows, "transforms", 0)
  assert Radial.reproduce(params) =~ "RadialFigure.map"
end
```

- [ ] **Step 6: Run it to see it fail, then implement and register `Radial`**

Run: `mix test test/girihelix_web/workbench/exhibits/radial_test.exs`
Expected: FAIL, the module is undefined.

Implement the design's `radial` section, with a single `:replicate` step whose
run builds `Figure.map/1` and sets `map`. Register it after `Connect`.

- [ ] **Step 7: Run the whole workbench suite**

Run: `mix test test/girihelix_web/workbench/`
Expected: PASS. The registry property test now covers all five new exhibits at
their defaults and range extremes, and the LiveView tests render them.

- [ ] **Step 8: Gates and commit**

Run `mix precommit.fast && mix dialyzer`, then:

```bash
git add lib/girihelix_web/workbench/exhibits lib/girihelix_web/workbench/registry.ex test/girihelix_web/workbench/exhibits
git commit -m "feat: add the scale, connect and radial workbench exhibits"
```

### Task 10: Homogenisation pass

**Files:**

- `docs/superpowers/specs/2026-10-21-girihelix-figures-design.md`
- `docs/superpowers/specs/2026-10-16-girihelix-workbench-design.md`
- `docs/algorithm-analysis.md` (only if a behavioural fact belongs there)
- `docs/backlog.md`
- the modules from this plan

- [ ] **Step 1: Record the implementation decisions in the design**

Under the design's "Decisions taken", add anything the implementation settled
that the design did not name: the exact state keys an exhibit reads, the
`Exhibits.Figures` helper's final function names, and the crash parameters
found for Star. Change the status to "implemented 2026-10-21 (Plan 3)".

- [ ] **Step 2: Update the plan series**

In the workbench design's "Revised plan series", mark row 3 done, and change
the status line to "Plan 3 implemented 2026-10-21; Plans 4–7 remain." Update
the exhibit inventory only if an exhibit was renamed.

- [ ] **Step 3: Record the flaws at one named function each**

Confirm each of these has a test naming it, and add a one-line note in the
module doc of the function that owns it:

- Star's raw-`d` closure chord and its near-integral snap;
- Rosette's skipped crossing and the `(12, -0.8, 4)` trigger;
- ScaleFigure's tip fallback and endpoint coalescing;
- ConnectFigure's axis seam and its three `1.0` fallbacks.

Do not fix any of them.

- [ ] **Step 4: Triage the backlog**

Add entries for work Plan 3 discovers but does not do, for example a cached
unit if Connect's double build proves costly, or a constructor-level check for
Star's crash parameters if the studio needs to refuse them. Triage the carried
`Point.compare_to/2` entry: Plan 3 does not add the `Infer` caller, so record
that it rolls forward to the plan that does.

- [ ] **Step 5: Strip source narration**

Run:

```bash
grep -rniE "java|taprats|ported|reference tree|source's|extractFace|getTwin|buildUnit|getMap" lib/girihelix/engine/figures lib/girihelix_web/workbench/exhibits
```

Restate each hit as a decision about the port, not a recital of another system.
Keep the word "Taprats" only where a doc records a divergence.

- [ ] **Step 6: Lint and run the gates**

Run:

```bash
markdownlint-cli2 --config ~/.markdownlint-cli2.jsonc \
  docs/superpowers/specs/2026-10-21-girihelix-figures-design.md \
  docs/superpowers/specs/2026-10-16-girihelix-workbench-design.md \
  docs/backlog.md
```

Expected: 0 issues.

Run: `mix precommit`
Expected: `Total errors: 0`, the suite passes, and coverage does not fall.

- [ ] **Step 7: Commit**

```bash
git add docs/superpowers/specs docs/algorithm-analysis.md docs/backlog.md lib/girihelix/engine/figures lib/girihelix_web/workbench
git commit -m "docs: record the Plan 3 figure decisions"
```

## Task order and dependencies

Execute in this order:

1. Task 1 — no dependency.
2. Task 2 — needs Task 1.
3. Task 3 — needs Task 2.
4. Task 4 — needs Task 3 for its goldens.
5. Task 7 — needs Task 1; required by Tasks 5 and 6.
6. Task 5 — needs Tasks 4 and 7.
7. Task 6 — needs Task 5.
8. Task 8 — needs Tasks 2 and 4.
9. Task 9 — needs Tasks 5, 6 and 8's shared helper.
10. Task 10 — needs everything.

Tasks 4, 5, 6 and 8 can run in parallel only after their prerequisites; the
golden file is shared, so serialise any task that edits
`figures_golden_test.exs`.

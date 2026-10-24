# Render styles implementation plan (Plan 5)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn a constructed planar map into a styled drawing — `Plain`, `Filled` and `Outline` over the existing draw ops — coloured from a vendored Sanzo Wada palette, and expose it as one `:styles` workbench exhibit.

**Architecture:** Three engine modules under `lib/girihelix/engine/render/styles/`, a `Style` behaviour that dispatches by id and owns the shared background op, and a `Palette` module that indexes a vendored JSON dataset at compile time and maps a Wada combination to four colour roles. One workbench exhibit composes `Construct`'s step sequence with a terminal `:paint` step; the registry gains a `:styles` category.

**Tech Stack:** Elixir 1.20, ExUnit, the stdlib `JSON` module, the existing `PlanarMap`, `Faces`, `Bounds` and `Construct` engine, Phoenix LiveView exhibits. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-23-girihelix-render-styles-design.md`. Read it first; it fixes the intent, the three styles, the palette contract and the exhibit parameters. The authoritative source behaviour is the local, git-ignored `reference/porting-notes/rendering.md` and the Java under `reference/1.1.12/src/`.

## Global Constraints

- **Engine purity.** `lib/girihelix/engine/**` imports the standard library only. No Ash, Ecto, Phoenix or `GirihelixWeb`.
- **Hard rules.** No `if` or `cond`; branch in function heads and guards. Failing public functions return `{:error, reason}` with a `name!` twin that raises `ArgumentError`.
- **No new dependencies.** The palette dataset is vendored JSON decoded at compile time with the **stdlib `JSON`** module (available in Elixir 1.20), not Jason. Leave `Tilings.Catalogue`'s existing Jason decode alone; that backlog item is closed by this ruling, not by an edit.
- **Dataset facts (measured 2026-10-24).** The pinned `colors.json` holds **157 colours** and **348 combinations**, sized **1–5** colours, not the design's 171 and 3–4. Pin the file to commit `bedc528f85af521a36cedce91ea3398971139626`. Combination membership is derived by grouping colours on their `combinations` lists; the file has no combination records of its own.
- **Faithful first.** `Filled` draws white faces before black faces; `Outline` emits one six-point polygon per edge in the order below/vertex/above at each end; the miter uses `l = width / sin(θ)`. One deliberate divergence: the cusp guard tests `abs(sin θ) < 1.0e-7`, so a coincident-direction joint (θ ≈ 0) falls back to perpendicular offsets as well as the straight-through one (θ ≈ π). A non-finite coordinate is not drawable.
- **Ops are the only render surface.** Styles emit existing `Op.t()` values. `Polygon`, `Line` and option keys stay as Plan 2 defined them. Geometry is map space; `:width` is SVG units.
- **Defaults.** The styles exhibit defaults to tiling `:"8.5"`, figure `:rosette`, style `:filled`, palette `:"253"`. Tiling `4.5` is not a valid default here: with a rosette it builds 144 vertices and 144 edges, so it has one kept face and `Filled` paints a single flat region. `8.5` with a rosette gives 9 black and 8 white faces.
- **Gates.** The commit hook runs `mix precommit.fast`. Before the branch is pushed, `mix dialyzer` reports `Total errors: 0`, `mix format --check-formatted` passes, and no module exceeds 800 lines. Task 6 runs the full `mix precommit`.
- **Git.** Create `feat/render-styles` from `main`; the current `fix/always-list-check-origin` branch is unrelated. Run `git commit` as its own command. Commits are signed; on a 1Password error stop and ask the user to unlock.

## Review Focus

1. **An empty map at the paint step.** `figure: :none` leaves `Construct`'s map empty, so `Filled` returns `:no_faces` and `Plain`/`Outline` paint nothing. The exhibit must still draw non-empty ops and rows for that frame. Owner: Task 5.
2. **A one-colour palette combination.** Ten combinations hold a single colour, which the design's 3–4-colour assumption does not cover; every role must collapse to that hex without an index error. Owner: Tasks 1, 3 and 5.
3. **`Outline` at a degree-one vertex.** `before_and_after/3` names the same edge on a ring of one, so the port must take the `degree == 1` branch and place both cap points perpendicular to the edge. Owner: Task 4.
4. **`Outline` at a joint whose edges leave in the same direction.** `sin θ → 0` makes the miter infinite; the guard must return `nil` so the caller falls back rather than emitting Infinity into the SVG. Owner: Task 4.
5. **A raising star construction.** Tiling `3-8-12` in `:star` mode raises inside `Construct`; the paint step never runs, and every retained failure frame must still draw the construct's structure. Owner: Task 5.

---

### Task 1: Palette dataset and `Palette`

**Files:**

- Create: `priv/palettes/colors.json`
- Create: `priv/palettes/README.md`
- Create: `lib/girihelix/engine/render/palette.ex`
- Test: `test/girihelix/engine/render/palette_test.exs`
- Modify: `docs/superpowers/specs/2026-10-23-girihelix-render-styles-design.md` (dataset counts only)

**Interfaces:**

- Produces: `Girihelix.Engine.Render.Palette`
  - `@type colour :: %{index: pos_integer(), name: String.t(), slug: String.t(), hex: String.t()}`
  - `@type roles :: %{edge: String.t(), darker: String.t(), lighter: String.t(), background: String.t()}`
  - `count() :: pos_integer()`
  - `options() :: [atom()]` — `:"1"` through `:"348"`, the workbench enum
  - `combination(atom() | pos_integer()) :: {:ok, [colour()]} | {:error, :unknown_combination}`
  - `combination!(atom() | pos_integer()) :: [colour()]`
  - `roles(atom() | pos_integer()) :: {:ok, roles()} | {:error, :unknown_combination}`
  - `roles!(atom() | pos_integer()) :: roles()`

- [ ] **Step 1: Create the branch and commit the design doc**

```bash
git switch -c feat/render-styles main
git add docs/superpowers/specs/2026-10-23-girihelix-render-styles-design.md
git commit -m "docs: add the render styles design"
```

- [ ] **Step 2: Vendor the dataset at a pinned commit**

```bash
mkdir -p priv/palettes
curl -sSL -o priv/palettes/colors.json \
  https://raw.githubusercontent.com/dblodorn/sanzo-wada/bedc528f85af521a36cedce91ea3398971139626/apps/sanzo-wada-alpha/assets/colors.json
```

Verify the download is the expected data:

```bash
elixir -e 'c = JSON.decode!(File.read!("priv/palettes/colors.json"))["colors"]; IO.inspect({length(c), c |> Enum.flat_map(& &1["combinations"]) |> Enum.max()})'
```

Expected: `{157, 348}`.

Write `priv/palettes/README.md` with: the source repository `dblodorn/sanzo-wada`, the pinned commit above, the file's path in that repository, the measured counts (157 colours, 348 combinations sized 1–5), the note that the data is the source behind <https://sanzo-wada.dmbk.io>, and the full MIT licence text with `Copyright (c) 2024 Dain Blodorn`. Name Wada's 1918 and 1933 dictionaries as the ultimate origin.

- [ ] **Step 3: Write the failing tests**

```elixir
defmodule Girihelix.Engine.Render.PaletteTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Render.Palette

  test "the dataset holds 348 Wada combinations" do
    assert Palette.count() == 348
    assert length(Palette.options()) == 348
    assert hd(Palette.options()) == :"1"
    assert List.last(Palette.options()) == :"348"
  end

  test "a combination is its colours in dataset order" do
    assert {:ok, colours} = Palette.combination(:"176")
    assert Enum.map(colours, & &1.hex) == ["#ffb3f0", "#ffcfc4", "#80ffcc"]
    assert Enum.map(colours, & &1.name) == ["Hermosa Pink", "Seashell Pink", "Calamine BLue"]
    assert {:ok, ^colours} = Palette.combination(176)
  end

  test "an unknown combination is an error and the bang twin raises" do
    assert Palette.combination(349) == {:error, :unknown_combination}
    assert Palette.combination(:"0") == {:error, :unknown_combination}
    assert Palette.combination(:nope) == {:error, :unknown_combination}
    assert_raise ArgumentError, fn -> Palette.combination!(349) end
    assert_raise ArgumentError, fn -> Palette.roles!(349) end
  end

  test "roles order the four slots by relative luminance" do
    assert Palette.roles!(:"253") == %{
             edge: "#340059",
             darker: "#1b3644",
             lighter: "#ff7340",
             background: "#f2ff26"
           }
  end

  test "a two-colour combination keeps the light colour for both faces" do
    assert Palette.roles!(:"1") == %{
             edge: "#de4500",
             darker: "#29bdad",
             lighter: "#29bdad",
             background: "#29bdad"
           }
  end

  test "a three-colour combination uses all three" do
    assert Palette.roles!(:"176") == %{
             edge: "#ffb3f0",
             darker: "#ffcfc4",
             lighter: "#80ffcc",
             background: "#80ffcc"
           }
  end

  test "a one-colour combination paints every role the same colour" do
    same = "#328e13"

    assert Palette.roles!(:"5") == %{
             edge: same,
             darker: same,
             lighter: same,
             background: same
           }
  end
end
```

- [ ] **Step 4: Run the tests to see them fail**

Run: `mix test test/girihelix/engine/render/palette_test.exs`
Expected: FAIL, the module is undefined.

- [ ] **Step 5: Implement `Palette`**

Add `@external_resource "priv/palettes/colors.json"`. At compile time decode the file with `JSON.decode!/1` and keep the `"colors"` list; derive `@count` as the maximum combination id and `@combinations` as a map from id to that combination's colours in dataset order, each reduced to `index`, `name`, `slug` and `hex`. Derive `@options` as `:"1"` through `:"348"`.

`combination/1` accepts a positive integer in range or a digit atom. Convert an atom with `Integer.parse(Atom.to_string(atom))` and require an empty remainder and an in-range result; anything else is `{:error, :unknown_combination}`. `combination!/1` unwraps and raises.

`roles/1` sorts the combination's colours ascending by WCAG relative luminance, with `hex` as the tie-break, then maps the sorted list by its length:

- One colour: all four roles are that colour.
- Two colours `[dark, light]`: edge is `dark`; darker, lighter and background are `light`.
- Three colours `[dark, mid, light]`: edge `dark`, darker `mid`, lighter and background `light`.
- Four colours `[edge, dark, light, background]`: the four in order.
- Five or more: edge is the first, darker the second, lighter the second-to-last, background the last.

Relative luminance linearises each sRGB channel `c = channel / 255` as `c / 12.92` when `c <= 0.03928` and `((c + 0.055) / 1.055) ** 2.4` otherwise, then returns `0.2126r + 0.7152g + 0.0722b`. Document the rule and its failure mode in the module doc: combinations whose colours have near-identical luminance read muddy, and a one-colour combination paints flat; both are acceptable for v1.

- [ ] **Step 6: Amend the design's dataset facts**

In the spec, change "171 colours, 348 combinations" and "3–4 colours" (Palettes section and Decisions item 6) to the measured 157 and 1–5. Keep the rest of the design unchanged; Task 6 records the implementation decisions.

- [ ] **Step 7: Run the tests to see them pass**

Run: `mix test test/girihelix/engine/render/palette_test.exs`
Expected: PASS, 7 tests.

- [ ] **Step 8: Commit**

```bash
git add priv/palettes lib/girihelix/engine/render/palette.ex test/girihelix/engine/render/palette_test.exs docs/superpowers/specs/2026-10-23-girihelix-render-styles-design.md
git commit -m "feat: vendor the Wada palettes and add the palette module"
```

---

### Task 2: `Style` behaviour, background helper and `Plain`

**Files:**

- Create: `lib/girihelix/engine/render/style.ex`
- Create: `lib/girihelix/engine/render/styles/plain.ex`
- Test: `test/girihelix/engine/render/style_test.exs`
- Test: `test/girihelix/engine/render/styles/plain_test.exs`

**Interfaces:**

- Consumes: `Palette.roles/0` from Task 1.
- Produces:
  - `Girihelix.Engine.Render.Style`
    - `@type id :: :plain | :filled | :outline`
    - `@type reason :: :filling_conflict | :no_faces`
    - `@type result :: %{ops: [Op.t()], faces: non_neg_integer() | nil}`
    - `@callback paint(PlanarMap.t(), Palette.roles()) :: {:ok, result()} | {:error, reason()}`
    - `options() :: [id()]` — `[:plain, :filled, :outline]`
    - `paint(id(), PlanarMap.t(), Palette.roles()) :: {:ok, result()} | {:error, reason()}`
    - `background([Op.t()], Palette.roles()) :: [Op.t()]`
  - `Girihelix.Engine.Render.Styles.Plain`
    - `paint(PlanarMap.t(), Palette.roles()) :: {:ok, Style.result()}`

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule Girihelix.Engine.Render.StyleTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Render.Style

  defp roles do
    %{edge: "#111111", darker: "#222222", lighter: "#333333", background: "#eeeeee"}
  end

  test "options lists the three styles in control order" do
    assert Style.options() == [:plain, :filled, :outline]
  end

  test "background prepends a padded fill covering the drawing" do
    ops = [{:line, {0.0, 0.0}, {2.0, 0.0}, []}]
    [background | rest] = Style.background(ops, roles())

    assert {:polygon, [p1, p2, p3, p4], :fill, [fill: "#eeeeee"]} = background
    assert_close(p1, {-0.04, -0.04})
    assert_close(p2, {2.04, -0.04})
    assert_close(p3, {2.04, 0.04})
    assert_close(p4, {-0.04, 0.04})
    assert rest == ops
  end

  test "an empty drawing gains no background" do
    assert Style.background([], roles()) == []
  end

  test "paint dispatches by style id" do
    map = Girihelix.Engine.PlanarMap.new()
    assert {:ok, %{ops: [], faces: nil}} = Style.paint(:plain, map, roles())
  end

  defp assert_close({x, y}, {want_x, want_y}) do
    assert_in_delta x, want_x, 1.0e-12
    assert_in_delta y, want_y, 1.0e-12
  end
end
```

```elixir
defmodule Girihelix.Engine.Render.Styles.PlainTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Styles.Plain

  defp roles do
    %{edge: "#111111", darker: "#222222", lighter: "#333333", background: "#eeeeee"}
  end

  defp one_edge do
    {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
    {map, b} = PlanarMap.insert_vertex(map, Point.new(2.0, 0.0))
    PlanarMap.insert_edge!(map, a, b)
  end

  test "one line per edge in the edge colour, over a background" do
    map = one_edge()

    assert {:ok, %{ops: [background | lines], faces: nil}} = Plain.paint(map, roles())
    assert {:polygon, _, :fill, [fill: "#eeeeee"]} = background
    assert length(lines) == PlanarMap.num_edges(map)

    for {:line, _from, _to, opts} <- lines do
      assert opts[:stroke] == "#111111"
      assert opts[:width] == 1.5
    end
  end

  test "an empty map paints nothing" do
    assert Plain.paint(PlanarMap.new(), roles()) == {:ok, %{ops: [], faces: nil}}
  end
end
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `mix test test/girihelix/engine/render/style_test.exs test/girihelix/engine/render/styles/plain_test.exs`
Expected: FAIL, the modules are undefined.

- [ ] **Step 3: Implement `Style` and `Plain`**

`Style` declares the callback, `options/0`, `paint/3` with one clause per id, and `background/2`. `background/2` returns `[]` for `[]`; otherwise it takes `Bounds.of_ops/1` on the ops, pads the box by `0.02 * max(width, height)` on every side, and prepends a four-corner `{:polygon, points, :fill, [fill: hex]}`. Points run lower-left, lower-right, upper-right, upper-left.

`Plain` adds `@behaviour Girihelix.Engine.Render.Style`, sets `@edge_width 1.5`, and maps every edge to `{:line, from, to, [stroke: roles.edge, width: @edge_width]}` using `PlanarMap.endpoints!/2` and `PlanarMap.position!/2`. Its result is `%{ops: Style.background(ops, roles), faces: nil}`.

- [ ] **Step 4: Run the tests to see them pass**

Run: `mix test test/girihelix/engine/render/style_test.exs test/girihelix/engine/render/styles/plain_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/girihelix/engine/render/style.ex lib/girihelix/engine/render/styles/plain.ex test/girihelix/engine/render/style_test.exs test/girihelix/engine/render/styles/plain_test.exs
git commit -m "feat: add the style behaviour and the plain style"
```

---

### Task 3: `Filled`

**Files:**

- Create: `lib/girihelix/engine/render/styles/filled.ex`
- Test: `test/girihelix/engine/render/styles/filled_test.exs`

**Interfaces:**

- Consumes: `Faces.extract_faces/1`, `Style.result/0`, `Palette.roles!/1`.
- Produces: `Girihelix.Engine.Render.Styles.Filled.paint(PlanarMap.t(), Palette.roles()) :: {:ok, Style.result()} | {:error, Style.reason()}`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule Girihelix.Engine.Render.Styles.FilledTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Palette
  alias Girihelix.Engine.Render.Styles.Filled

  defp split_parallel do
    {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
    {map, b} = PlanarMap.insert_vertex(map, Point.new(2.0, 0.0))
    map = PlanarMap.insert_edge!(map, a, b)
    map = PlanarMap.insert_edge!(map, a, b)
    {map, _mid} = PlanarMap.insert_vertex(map, Point.new(1.0, 0.0))
    map
  end

  defp square_diagonal do
    {vertices, map} =
      Enum.map_reduce([{0.0, 0.0}, {4.0, 0.0}, {4.0, 3.0}, {0.0, 3.0}], PlanarMap.new(), fn {x, y}, map ->
        {map, vertex} = PlanarMap.insert_vertex(map, Point.new(x, y))
        {vertex, map}
      end)

    [a, b, c, d] = vertices

    Enum.reduce([{a, b}, {b, c}, {c, d}, {d, a}, {a, c}], map, fn {v1, v2}, map ->
      PlanarMap.insert_edge!(map, v1, v2)
    end)
  end

  test "white faces are light, black faces are dark, then the boundary is stroked" do
    map = split_parallel()

    assert {:ok, %{ops: [light, dark | boundary], faces: 2}} =
             Filled.paint(map, Palette.roles!(:"253"))

    assert {:polygon, _, :fill, [fill: "#ff7340"]} = light
    assert {:polygon, _, :fill, [fill: "#1b3644"]} = dark
    assert length(boundary) == PlanarMap.num_edges(map)

    for {:line, _from, _to, opts} <- boundary do
      assert opts[:stroke] == "#340059"
    end
  end

  test "a one-colour palette still fills and strokes" do
    assert {:ok, %{ops: ops, faces: 2}} = Filled.paint(split_parallel(), Palette.roles!(:"5"))
    fills = for {:polygon, _, :fill, [fill: hex]} <- ops, do: hex
    assert Enum.uniq(fills) == ["#328e13"]
  end

  test "an inconsistent colouring is an error tuple" do
    assert Filled.paint(square_diagonal(), Palette.roles!(:"253")) ==
             {:error, :filling_conflict}
  end

  test "a map with no faces is an error tuple" do
    assert Filled.paint(PlanarMap.new(), Palette.roles!(:"253")) == {:error, :no_faces}
  end
end
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `mix test test/girihelix/engine/render/styles/filled_test.exs`
Expected: FAIL, the module is undefined.

- [ ] **Step 3: Implement `Filled`**

Add `@behaviour Girihelix.Engine.Render.Style`. Match `Faces.extract_faces/1`: on `{:ok, %{black: black, white: white}}` build `white` face polygons in `roles.lighter` first, then `black` face polygons in `roles.darker`, then one boundary `{:line, from, to, [stroke: roles.edge, width: 1.0]}` per map edge. Each face polygon is `{:polygon, corner_points, :fill, [fill: hex]}`. Return `faces: length(black) + length(white)`. On `{:error, reason}` return the same error.

- [ ] **Step 4: Run the tests to see them pass**

Run: `mix test test/girihelix/engine/render/styles/filled_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/girihelix/engine/render/styles/filled.ex test/girihelix/engine/render/styles/filled_test.exs
git commit -m "feat: add the filled style over the face colouring"
```

---

### Task 4: `Outline`

**Files:**

- Create: `lib/girihelix/engine/render/styles/outline.ex`
- Test: `test/girihelix/engine/render/styles/outline_test.exs`

**Interfaces:**

- Consumes: `PlanarMap.ring!/2`, `PlanarMap.before_and_after!/3`, `PlanarMap.neighbour!/3`, `PlanarMap.endpoints!/2`, `Point.sweep/3`, `Point.perp/1`, `Point.convex_sum/3`, `Style.background/2`.
- Produces: `Girihelix.Engine.Render.Styles.Outline`
  - `paint(PlanarMap.t(), Palette.roles()) :: {:ok, Style.result()}`
  - `get_points(PlanarMap.t(), PlanarMap.edge(), PlanarMap.vertex(), PlanarMap.vertex()) :: {Point.t(), Point.t()}`
  - `join_point(Point.t(), Point.t(), Point.t(), number()) :: Point.t() | nil`

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule Girihelix.Engine.Render.Styles.OutlineTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Palette
  alias Girihelix.Engine.Render.Styles.Outline

  @width 0.05

  test "a dangling edge is one six-point ribbon over a background" do
    {map, [a, b]} = two_vertices()
    map = PlanarMap.insert_edge!(map, a, b)

    assert {:ok, %{ops: [background, ribbon], faces: nil}} =
             Outline.paint(map, Palette.roles!(:"253"))

    assert {:polygon, _, :fill, [fill: "#340059"]} = background
    assert {:polygon, points, :fill, [fill: "#340059"]} = ribbon
    assert length(points) == 6

    expected = [
      {2.0, -0.05},
      {2.0, 0.0},
      {2.0, 0.05},
      {0.0, 0.05},
      {0.0, 0.0},
      {0.0, -0.05}
    ]

    Enum.zip(points, expected)
    |> Enum.each(fn {point, want} -> assert_close(point, want) end)
  end

  test "a straight-through joint has no miter and falls back to the perpendicular" do
    {map, [a, b, c]} = three_collinear()
    map = map |> PlanarMap.insert_edge!(a, b) |> PlanarMap.insert_edge!(b, c)
    [edge | _] = PlanarMap.edges(map)

    {below, above} = Outline.get_points(map, edge, a, b)
    assert_close(below, {1.0, -@width})
    assert_close(above, {1.0, @width})
  end

  test "a right-angle joint mitres at the offset intersection" do
    assert_close(
      Outline.join_point(Point.new(0.0, 0.0), Point.new(1.0, 0.0), Point.new(0.0, 1.0), @width),
      {@width, @width}
    )
  end

  test "coincident-direction edges have no finite miter" do
    assert Outline.join_point(
             Point.new(0.0, 0.0),
             Point.new(1.0, 0.0),
             Point.new(2.0, 0.0),
             @width
           ) == nil
  end

  test "an empty map paints nothing" do
    assert Outline.paint(PlanarMap.new(), Palette.roles!(:"253")) ==
             {:ok, %{ops: [], faces: nil}}
  end

  defp two_vertices do
    {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
    {map, b} = PlanarMap.insert_vertex(map, Point.new(2.0, 0.0))
    {map, [a, b]}
  end

  defp three_collinear do
    Enum.map_reduce([{0.0, 0.0}, {1.0, 0.0}, {2.0, 0.0}], PlanarMap.new(), fn {x, y}, map ->
      {map, vertex} = PlanarMap.insert_vertex(map, Point.new(x, y))
      {vertex, map}
    end)
    |> then(fn {vertices, map} -> {map, vertices} end)
  end

  defp assert_close({x, y}, {want_x, want_y}) do
    assert_in_delta x, want_x, 1.0e-12
    assert_in_delta y, want_y, 1.0e-12
  end
end
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `mix test test/girihelix/engine/render/styles/outline_test.exs`
Expected: FAIL, the module is undefined.

- [ ] **Step 3: Implement `Outline`**

Add `@behaviour Girihelix.Engine.Render.Style`. Set `@width 0.05` and `@miter_tolerance 1.0e-7`.

`get_points(map, edge, from, to)` returns `{below, above}`:

- `pfrom` and `pto` are the two positions; `dir = normalize(pto - pfrom)`; `perp = Point.perp(dir)`.
- Degree one: `below = pto - perp * width`, `above = pto + perp * width`.
- Degree two: take `{before, _after} = before_and_after!(map, to, edge)` and the far endpoint's position; `jp = join_point(pto, pfrom, far, width)`. A `nil` join falls back to the perpendicular pair; otherwise `below = jp` and `above = 2 * pto - jp`.
- Degree three or more: `{before, after} = before_and_after!(map, to, edge)`; `below = join_point(pto, pfrom, position(after_far), width)` and `above = join_point(pto, position(before_far), pfrom, width)`, each falling back to its perpendicular point on `nil`.

`join_point(joint, a, b, width)` computes `theta = Point.sweep(joint, a, b)` and `s = :math.sin(theta)`. A private clause with the guard `s < @miter_tolerance and s > -@miter_tolerance` returns `nil`; the other clause returns `joint - (normalize(joint - a) + normalize(joint - b)) * (width / s)`.

`paint/2` maps each edge to one polygon: `[below@to, to, above@to, below@from, from, above@from]` where the first triple comes from `get_points(map, edge, v1, v2)` and the second from `get_points(map, edge, v2, v1)`, filling in `roles.edge`. Wrap with `Style.background/2` and return `faces: nil`.

- [ ] **Step 4: Run the tests to see them pass**

Run: `mix test test/girihelix/engine/render/styles/outline_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/girihelix/engine/render/styles/outline.ex test/girihelix/engine/render/styles/outline_test.exs
git commit -m "feat: add the mitred outline style"
```

---

### Task 5: The `:styles` exhibit and registry entry

**Files:**

- Create: `lib/girihelix_web/workbench/exhibits/styles.ex`
- Modify: `lib/girihelix_web/workbench/registry.ex`
- Test: `test/girihelix_web/workbench/exhibits/styles_test.exs`
- Modify: `test/girihelix_web/workbench/registry_test.exs`
- Modify: `docs/superpowers/specs/2026-10-23-girihelix-render-styles-design.md` (exhibit defaults)

**Interfaces:**

- Consumes: `Construct.start/3`, `Construct.steps/3`, `Construct.default_region/1`, `Style.paint/3`, `Palette.roles/1`, `Tilings.translation_ops/1`, `Tilings.cell_ops/1`, `Tilings.outline_ops/1`, `Figures.map_ops/1`, `Instancing.rosette_binder/1`, `Instancing.star_binder/1`.
- Produces: `GirihelixWeb.Workbench.Exhibits.Styles` implementing `GirihelixWeb.Workbench.Exhibit`, `slug/0 == "styles"`, `category/0 == :styles`; the registry exposes it last and `Registry.grouped/0` ends with `:styles`.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule GirihelixWeb.Workbench.Exhibits.StylesTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibits.Styles
  alias GirihelixWeb.Workbench.Param

  defp defaults, do: Param.values(Styles.params(), :default)

  defp last_frame(params) do
    params |> Styles.steps() |> Steps.run!(Styles.initial(params)) |> List.last()
  end

  test "identifies itself and declares the four parameters" do
    assert Styles.slug() == "styles"
    assert Styles.category() == :styles
    assert Styles.title() != ""
    assert Styles.summary() != ""

    assert [tiling, figure, style, palette] = Styles.params()
    assert {tiling.name, tiling.default} == {:tiling, :"8.5"}
    assert {figure.name, figure.options, figure.default} == {:figure, [:rosette, :star, :none], :rosette}
    assert {style.name, style.options, style.default} == {:style, [:plain, :filled, :outline], :filled}
    assert {palette.name, palette.default} == {:palette, :"253"}
    assert length(palette.options) == 348
  end

  test "the default run ends with a paint step and a painted drawing" do
    params = defaults()

    assert Enum.map(Styles.steps(params), & &1.id) == [:place, :bind, :units, :weld, :paint]

    assert {:both, ops, rows} = Styles.draw(last_frame(params), params)
    assert Enum.any?(ops, &match?({:polygon, _, :fill, _}, &1))
    assert {"style", "filled"} in rows
    assert {"palette", "Wada 253"} in rows
    assert {"faces", "17"} in rows
    assert {"failure", "none"} in rows
  end

  test "an unbound run paints nothing and still draws the tiling" do
    params = %{defaults() | figure: :none}
    frame = last_frame(params)

    assert {:both, [_ | _], rows} = Styles.draw(frame, params)
    assert {"faces", "n/a"} in rows
    assert {"failure", "no_faces"} in rows
  end

  test "a one-colour palette still paints" do
    params = %{defaults() | palette: :"5"}

    assert {:both, [_ | _], rows} = Styles.draw(last_frame(params), params)
    assert {"palette", "Wada 5"} in rows
  end

  test "a triangle tiling in star mode keeps every frame drawable" do
    params = %{defaults() | tiling: :"3-8-12", figure: :star}

    assert {:error, %Steps.Failure{frames: frames}} =
             Steps.run(Styles.steps(params), Styles.initial(params))

    assert frames != []

    for frame <- frames do
      assert {:both, [_ | _], [_ | _]} = Styles.draw(frame, params)
    end
  end

  test "reproduces the painted map with a fully qualified snippet" do
    assert Styles.reproduce(defaults()) ==
             "Girihelix.Engine.Render.Style.paint(:filled, " <>
               "Girihelix.Engine.Tilings.Construct.construct!(" <>
               "Girihelix.Engine.Tilings.Catalogue.load!(\"8.5\"), " <>
               "&GirihelixWeb.Workbench.Exhibits.Instancing.rosette_binder/1, " <>
               "Girihelix.Engine.Tilings.Construct.default_region(" <>
               "Girihelix.Engine.Tilings.Catalogue.load!(\"8.5\"))), " <>
               "Girihelix.Engine.Render.Palette.roles!(:\"253\"))"
  end
end
```

In `registry_test.exs`, change the expected category list to `[:geometry, :figures, :tilings, :styles]`.

- [ ] **Step 2: Run the tests to see them fail**

Run: `mix test test/girihelix_web/workbench/exhibits/styles_test.exs test/girihelix_web/workbench/registry_test.exs`
Expected: FAIL, the exhibit is undefined and the registry's grouped categories do not yet include `:styles`.

- [ ] **Step 3: Implement the exhibit**

`initial/1` builds `Construct.start(tiling, binder(figure), Construct.default_region(tiling))` and puts `paint: nil` into the state. `steps/1` is `Construct.steps(tiling, binder(figure), Construct.default_region(tiling)) ++ [paint_step(style, palette)]`.

`paint_step/2` is a `Steps.step(:paint, "paint", "...", fn state -> Map.put(state, :paint, paint_map(style, state.map, palette)) end)`. `paint_map/3` resolves `Palette.roles(palette)` and calls `Style.paint/3`; a palette error is stored as `{:error, reason}`.

`binder/1` returns `fn _feature -> nil end` for `:none` and the public `Instancing.rosette_binder/1` or `Instancing.star_binder/1` otherwise.

`draw/2` returns `{:both, ops, rows}`. Painted ops are used when `paint` is `{:ok, %{ops: [_ | _] = ops}}`; every other state falls back to the construct drawing, `Tilings.translation_ops(state.tiling) ++ Tilings.cell_ops(state.translations) ++ Tilings.outline_ops(state.tiling) ++ Figures.map_ops(state.map)`. The rows are exactly, in order: `tiling` (the name), `figure`, `style`, `palette` (`"Wada " <> number`), `faces` (the filled count or `n/a`), `vertices`, `edges`, `failure` (`none` or the reason).

`reproduce/1` returns the string asserted above, built from `inspect/1` on the style and palette atoms and the tiling name.

Register `Styles` last in `Registry`'s `@exhibits` after `Instancing`.

- [ ] **Step 4: Amend the design's exhibit defaults**

In the spec's "The exhibit" section, change the tiling default from `4.5` to `8.5`, and record the palette default `253`. Add one sentence: tiling `4.5` with a rosette has one kept face, so `Filled` paints one flat region; `8.5` produces 9 black and 8 white faces.

- [ ] **Step 5: Run the tests to see them pass**

Run: `mix test test/girihelix_web/workbench/exhibits/styles_test.exs test/girihelix_web/workbench/registry_test.exs test/girihelix_web/workbench/index_live_test.exs test/girihelix_web/workbench/exhibit_live_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/girihelix_web/workbench/exhibits/styles.ex lib/girihelix_web/workbench/registry.ex test/girihelix_web/workbench/exhibits/styles_test.exs test/girihelix_web/workbench/registry_test.exs docs/superpowers/specs/2026-10-23-girihelix-render-styles-design.md
git commit -m "feat: add the styles exhibit and the styles category"
```

---

### Task 6: Homogenisation, design record and full gate

**Files:**

- Modify: `lib/girihelix/engine/render/palette.ex`
- Modify: `lib/girihelix/engine/render/style.ex`
- Modify: `lib/girihelix/engine/render/styles/plain.ex`
- Modify: `lib/girihelix/engine/render/styles/filled.ex`
- Modify: `lib/girihelix/engine/render/styles/outline.ex`
- Modify: `lib/girihelix_web/workbench/exhibits/styles.ex`
- Modify: `docs/superpowers/specs/2026-10-23-girihelix-render-styles-design.md`
- Modify: `docs/backlog.md`

**Interfaces:**

- Consumes: every module from Tasks 1–5.
- Produces: no new interface; the branch is ready to push.

- [ ] **Step 1: Run the full gate**

Run: `mix precommit`
Expected: `mix format --check-formatted`, Credo, Sobelow, the full suite under coverage and `mix dialyzer` all pass, with `Total errors: 0`.

- [ ] **Step 2: Fix what the gate reports**

Fix findings in the touched modules only; rerun `mix precommit` until it is clean. Do not loosen a check.

- [ ] **Step 3: Homogenise the touched code**

Re-read the six modules against the project rules: no `if` or `cond`, comparisons in guards on separate clauses, failing public functions returning error tuples with bang twins, module docs describing behaviour rather than source narration, no module over 800 lines. Confirm `mix format` has not displaced section comments or reordered aliases.

- [ ] **Step 4: Record the implementation decisions in the design**

Set the spec's status to accepted, dated 2026-10-24, and replace "Left to the builder" with a short "Decisions taken at implementation" list: the module split (`Style` behaviour, `Styles.Plain/Filled/Outline`, `Palette`), the role-mapping rule and its muddy/flat failure modes, `Outline`'s six-point ribbon and `sin θ` guard, `Filled`'s white-then-black order plus a boundary stroke, the paint step living in the exhibit rather than `Construct`, and the `8.5`/`253` defaults.

- [ ] **Step 5: Triage the backlog**

Move the "Jason is compile-time-only in the engine" entry to Closed, recording the ruling: new engine data modules use the stdlib `JSON` module, and `Tilings.Catalogue` keeps Jason until it is next touched. Add follow-ups to Open: browsing palettes by base colour (the dataset supports it), a styled figure exhibit without a tiling, and palette labels in the controls (the enum currently renders the raw combination number).

- [ ] **Step 6: Ask the user to judge the result by eye**

The design's acceptance test is visual. Ask the user to open <http://localhost:4000/workbench/styles> in their dev server and compare the `Filled` 8.5 rosette against historical patterns and Taprats. Adjust the curated default palette or the boundary stroke width if they ask; rerun the affected tests.

- [ ] **Step 7: Commit**

```bash
git add lib/girihelix/engine/render lib/girihelix_web/workbench/exhibits/styles.ex docs/superpowers/specs/2026-10-23-girihelix-render-styles-design.md docs/backlog.md
git commit -m "chore: homogenise the render styles and record the decisions"
```

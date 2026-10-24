# Styles presentation implementation plan (Plan 5 follow-up)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the styles page readable as a tiling: a seamless finite patch showing two to three unit cells, every face island coloured, a toggleable per-tile-type overlay, pan and zoom on every canvas, and a swatch palette picker.

**Architecture:** `Faces` gains multi-island seeding. `Palette` maps a combination onto the roles a style declares, deriving missing tones. `Style` returns its background separately so the exhibit can compose background → tiles → figure. `Construct` gains an enlarged patch region, and the styles exhibit pins a content-centred viewport computed from the run's frames. A `CanvasZoom` JS hook serves every canvas, and `Param`/`Controls` gain a `:palette` type with an inline swatch list.

**Tech Stack:** Elixir 1.20, ExUnit, Phoenix LiveView, the existing SVG serializer and draw ops, plain JS in the esbuild bundle. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-24-girihelix-styles-presentation-design.md`. Read it first; it fixes the intent, the composition order and the decisions. Plan 5 (`feat/render-styles`) is the base; branch from it, or from `main` once it merges.

## Global Constraints

- **Engine purity.** `lib/girihelix/engine/**` is standard-library only. The JS hook lives in `assets/js/` and is registered in `app.js`.
- **Hard rules.** No `if` or `cond`; function heads and guards. Failing public functions return `{:error, reason}` with a `name!` twin that raises `ArgumentError`. Tagged-tuple `case` is fine.
- **No new dependencies.** The serializer's draw-op vocabulary is unchanged.
- **The face-colouring extension is deliberate.** Taprats seeds only the first face; girihelix seeds every island, each island's first face black. Record the decision and its reason in the module doc, not the source narration.
- **Palette roles are content-declared.** `Filled` asks for `edge, darker, lighter`; `Plain` and `Outline` ask for `edge, background`. Missing tones are derived by shifting HSL lightness with hue and saturation kept (`0.18` step, clamped to `[0.08, 0.92]`, direction flipped at a clamp). No colour is recycled.
- **Composition order.** Background → figure → translucent tile overlay (on top). The style returns `background` separately from `ops` so the composition is explicit; the overlay is translucent so the design stays readable through the tiles.
- **Patch and frame.** The patch spans `cells = 2` (a 5×5 grid of lattice translations). The viewport shows `2.0` unit cells vertically, centred on the final frame's content bounds, at the canvas aspect `0.75`, nominal width `1000.0`.
- **Canvas.** One `CanvasZoom` hook on every canvas; the SVG root is `overflow-visible` and the wrapper clips. No inline scripts.
- **Gates.** The commit hook runs `mix precommit.fast`. Before the branch is pushed, `mix precommit` passes with `mix dialyzer` reporting `Total errors: 0`, and no module exceeds 800 lines.
- **Git.** Create `feat/styles-presentation` from `feat/render-styles` (or from `main` after Plan 5 merges, rebasing). Run `git commit` as its own command; commits are signed via 1Password — on a signing error, stop and ask.

## Review Focus

1. **A one-colour combination on `Filled`.** Both faces are derived from the single colour; they must be distinct and in luminance order. Owner: Task 2.
2. **A one-colour combination on `Plain`/`Outline`.** The background is derived from the edge colour and must differ from it. Owner: Task 2.
3. **Frame zero with the tile overlay on.** `state.translations` is empty, so the overlay must fall back to one identity lattice translation and still draw. Owner: Task 3.
4. **A failed run when the viewport is pinned.** The last retained frame has no paint; the viewport must come from the map or structure bounds without re-running the construction or raising. Owner: Task 4.
5. **The largest catalogue tiling at the enlarged patch.** `Girih Star` at 5×5 cells multiplies construction and face work; measure it before adopting three visible cells, and keep the registry suite acceptable. Owner: Tasks 4 and 7.

## Setup

Before Task 1, create the branch and commit the documents:

```bash
git switch -c feat/styles-presentation feat/render-styles
git add docs/superpowers/specs/2026-10-24-girihelix-styles-presentation-design.md docs/superpowers/plans/2026-10-24-girihelix-styles-presentation.md
git commit -m "docs: add the styles presentation design and plan"
```

If Plan 5 has merged by then, branch from `main` instead and rebase this branch onto it. Every task's commit is made on this branch.

---

### Task 1: `Faces` colours every island

**Files:**

- Modify: `lib/girihelix/engine/faces.ex`
- Test: `test/girihelix/engine/faces_test.exs`
- Modify if counts change: `test/girihelix/engine/faces_golden_test.exs`

**Interfaces:**

- Produces: no public API change. `extract_faces/1` colours every separate face-adjacency island; each island's first discovered face is black. `{:error, :filling_conflict}` still means a conflict was seen.

- [ ] **Step 1: Write the failing test**

Add to `faces_test.exs`, using its existing `build/2` helper:

```elixir
test "every disconnected island is coloured" do
  map =
    build([{0.0, 0.0}, {2.0, 0.0}, {0.0, 10.0}, {2.0, 10.0}], [
      {0, 1},
      {0, 1},
      {2, 3},
      {2, 3}
    ])

  {map, _mid} = PlanarMap.insert_vertex(map, Point.new(1.0, 0.0))
  {map, _mid} = PlanarMap.insert_vertex(map, Point.new(1.0, 10.0))

  assert {:ok, %{black: black, white: white}} = Faces.extract_faces(map)
  assert length(black) == 2
  assert length(white) == 2
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `mix test test/girihelix/engine/faces_test.exs`
Expected: FAIL — only the first island is seeded, so the result has one black and one white face.

- [ ] **Step 3: Seed every island**

In `Faces.colour/1`, after the first component drains, walk the kept `order` and, for each face still `:undone`, seed it `:processing`, push it and `drain/1` again. Stop on a recorded failure. Do not reseed a face that has become `:black` or `:white`.

The shape is:

```elixir
defp colour(%{order: [seed | _]} = state) do
  state |> seed_component(seed) |> colour_remaining()
end

defp seed_component(state, id) do
  %{state | stack: [id]} |> put_state(id, :processing) |> drain()
end

defp colour_remaining(%{failure: reason} = state) when not is_nil(reason), do: state
defp colour_remaining(%{order: order} = state), do: Enum.reduce(order, state, &colour_if_undone/2)

defp colour_if_undone(id, state) do
  case state.infos[id].state do
    :undone -> seed_component(state, id)
    _coloured -> state
  end
end
```

- [ ] **Step 4: Run the face tests**

Run: `mix test test/girihelix/engine/faces_test.exs test/girihelix/engine/faces_golden_test.exs`
Expected: PASS. If a golden count changes, update that fixture to the new count and note in the report that the change is the multi-island rule.

- [ ] **Step 5: Update the module doc**

In the "Colouring" section, state that every separate island is seeded and that each island's first face is black, because faces meeting only at vertices share no edge. Record the reason: a flower tiling otherwise leaves all but one rosette uncoloured.

- [ ] **Step 6: Commit**

```bash
git add lib/girihelix/engine/faces.ex test/girihelix/engine/faces_test.exs test/girihelix/engine/faces_golden_test.exs
git commit -m "feat: colour every separate face island"
```

---

### Task 2: Content-declared palette roles, derived tones, separate background

**Files:**

- Modify: `lib/girihelix/engine/render/palette.ex`
- Modify: `lib/girihelix/engine/render/style.ex`
- Modify: `lib/girihelix/engine/render/styles/plain.ex`
- Modify: `lib/girihelix/engine/render/styles/filled.ex`
- Modify: `lib/girihelix/engine/render/styles/outline.ex`
- Modify: `lib/girihelix_web/workbench/exhibits/styles.ex`
- Tests: `test/girihelix/engine/render/palette_test.exs`, `test/girihelix/engine/render/style_test.exs`, `test/girihelix/engine/render/styles/plain_test.exs`, `test/girihelix/engine/render/styles/filled_test.exs`, `test/girihelix/engine/render/styles/outline_test.exs`, `test/girihelix_web/workbench/exhibits/styles_test.exs`

**Interfaces:**

- Consumes: `Palette.combination/1` from Plan 5.
- Produces:
  - `Palette.roles(combination, roles) :: {:ok, %{atom() => hex}} | {:error, :unknown_combination | :unknown_role}`
  - `Palette.roles!(combination, roles) :: %{atom() => hex}`
  - `Style.roles(:plain | :filled | :outline) :: [atom()]`
  - `Style.background([Op.t()], roles) :: Op.t() | nil`
  - `Style.result :: %{background: Op.t() | nil, ops: [Op.t()], faces: non_neg_integer() | nil}`

- [ ] **Step 1: Write the failing tests**

Add to `palette_test.exs`:

```elixir
test "roles are the ones the content asks for" do
  assert Palette.roles!(:"253", [:edge, :darker, :lighter]) == %{
           edge: "#340059",
           darker: "#1b3644",
           lighter: "#f2ff26"
         }

  assert Palette.roles!(:"253", [:edge, :background]) == %{
           edge: "#340059",
           background: "#f2ff26"
         }
end

test "a two-colour combination derives its second face" do
  assert Palette.roles!(:"1", [:edge, :darker, :lighter]) == %{
           edge: "#de4500",
           darker: "#197268",
           lighter: "#29bdad"
         }
end

test "a one-colour combination derives both faces and its background" do
  assert Palette.roles!(:"5", [:edge, :darker, :lighter]) == %{
           edge: "#328e13",
           darker: "#153d08",
           lighter: "#4fdf1e"
         }

  assert Palette.roles!(:"5", [:edge, :background]) == %{
           edge: "#328e13",
           background: "#4fdf1e"
         }
end

test "an unknown role is an error tuple" do
  assert Palette.roles(:"253", [:edge, :sparkle]) == {:error, :unknown_role}
end
```

Add to `style_test.exs`:

```elixir
test "each style declares the roles it needs" do
  assert Style.roles(:plain) == [:edge, :background]
  assert Style.roles(:filled) == [:edge, :darker, :lighter]
  assert Style.roles(:outline) == [:edge, :background]
end

test "the background is returned apart from the geometry" do
  roles = %{edge: "#111111", background: "#eeeeee"}

  {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
  {map, b} = PlanarMap.insert_vertex(map, Point.new(2.0, 0.0))
  map = PlanarMap.insert_edge!(map, a, b)

  assert {:ok, %{background: {:polygon, _, :fill, [fill: "#eeeeee"]}, ops: ops, faces: nil}} =
           Plain.paint(map, roles)

  assert Enum.all?(ops, &match?({:line, _, _, _}, &1))
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix/engine/render/palette_test.exs test/girihelix/engine/render/style_test.exs`
Expected: FAIL — `roles/2` and `Style.roles/1` do not exist; the style result has no `background`.

- [ ] **Step 3: Implement the role mapping and derivation**

In `Palette`:

- Sort the combination's colours ascending by luminance with `hex` as the tie-break.
- `:edge` takes the darkest colour.
- `:background` takes the lightest remaining colour; when no colour remains, derive it from the edge toward lighter.
- `:darker` and `:lighter` take the most separated pair among the remaining colours, assigned by luminance order; one remaining colour becomes `lighter` and the other face is derived toward darker; no remaining colour derives both faces from the edge (`darker` toward darker, `lighter` toward lighter).
- Any role outside `[:edge, :background, :darker, :lighter]` returns `{:error, :unknown_role}`.
- Derivation: convert hex to HSL, shift lightness by `0.18`, clamp to `[0.08, 0.92]`; if the clamp leaves the lightness unchanged, shift the other way; convert back to lowercase `#rrggbb`.

In `Style`: add `roles/1` with one clause per id; change `result` to carry `background`; change `background/2` to return the polygon op (or `nil`) instead of a prefixed list. `Plain` and `Outline` return the background separately and their geometry in `ops`; `Filled` returns `background: nil`.

In the exhibit's `paint_step`, resolve `Palette.roles(params.palette, Style.roles(params.style))` and store `{:error, reason}` as before. In `picture/1`, compose `List.wrap(background) ++ ops` so the background still paints.

- [ ] **Step 4: Run the render and exhibit tests, update expected colours**

Run: `mix test test/girihelix/engine/render test/girihelix_web/workbench/exhibits/styles_test.exs`

Every Plan 5 call to `roles!/1` becomes `roles!/2` with the style's role list. The 253 test expectations change because `Filled` now uses the most separated pair, not the adjacent one:

- `Filled` with 253: edge `#340059`, darker `#1b3644`, lighter `#f2ff26`.
- `Outline` with 253: edge `#340059`, background `#f2ff26`.
- `Plain` with 253: edge `#340059`, background `#f2ff26`.
- The one-colour `:"5"` expectations are the derived values above. Those hexes come from an independent HSL computation; if the Elixir implementation differs in one channel because of rounding, pin the implementation's value and note the difference in the report rather than bending the implementation.

- [ ] **Step 5: Run the full suite**

Run: `mix test`
Expected: PASS, with the updated colour expectations.

- [ ] **Step 6: Commit**

```bash
git add lib/girihelix/engine/render lib/girihelix_web/workbench/exhibits/styles.ex test/girihelix/engine/render test/girihelix_web/workbench/exhibits/styles_test.exs
git commit -m "feat: assign palette roles by content and derive missing tones"
```

---

### Task 3: Tile overlay and the `tiles` toggle

**Files:**

- Modify: `lib/girihelix_web/workbench/exhibits/tilings.ex`
- Modify: `lib/girihelix_web/workbench/exhibits/styles.ex`
- Modify: `lib/girihelix_web/workbench/components/controls.ex`
- Tests: `test/girihelix_web/workbench/exhibits/tilings_test.exs` (create if absent), `test/girihelix_web/workbench/exhibits/styles_test.exs`, `test/girihelix_web/workbench/components/controls_test.exs`

**Interfaces:**

- Produces:
  - `Tilings.tile_ops(Tiling.t(), [Transform.t()]) :: [Op.t()]` — two ops per placement per lattice translation: a faint fill and a faint stroke.
  - `Styles.params/0` gains `%Param{name: :tiles, type: :boolean, default: false}`.
  - A boolean control renders a checkbox plus a hidden `"false"` input.

- [ ] **Step 1: Write the failing tests**

Add to a tiling or exhibit test:

```elixir
test "tile ops cover every placement at every translation with a tint per type" do
  tiling = Girihelix.Engine.Tilings.Catalogue.load!("8.5")
  translations = [Transform.identity(), Transform.translate(10.0, 0.0)]
  ops = Tilings.tile_ops(tiling, translations)

  assert length(ops) == 2 * length(tiling.placements) * 2

  fills =
    for {:polygon, _, :fill, [fill: hex, opacity: 0.12]} <- ops, do: hex

  assert length(Enum.uniq(fills)) == min(length(tiling.features), 5)
  assert Enum.any?(ops, &match?({:polygon, _, :stroke, _}, &1))
end

test "frame zero uses the identity translation" do
  tiling = Girihelix.Engine.Tilings.Catalogue.load!("8.5")
  assert Tilings.tile_ops(tiling, []) == Tilings.tile_ops(tiling, [Transform.identity()])
end
```

Add to `styles_test.exs`:

```elixir
test "the tile overlay is off by default and sits over the figure" do
  params = defaults()
  assert params.tiles == false

  off = last_frame(params)
  {:both, off_ops, _rows} = Styles.draw(off, params)
  refute Enum.any?(off_ops, &match?({:polygon, _, :fill, [fill: "#2563eb", opacity: 0.12]}, &1))

  on_params = %{params | tiles: true}
  on = last_frame(on_params)
  {:both, on_ops, _rows} = Styles.draw(on, on_params)
  assert Enum.any?(on_ops, &match?({:polygon, _, :fill, [fill: "#2563eb", opacity: 0.12]}, &1))
  assert Enum.any?(on_ops, &match?({:polygon, _, :fill, [fill: "#1b3644"]}, &1))
end
```

Also assert the order: with `style: :plain, tiles: true`, the first op is the background, the `:line` figure ops follow, and the tile fill/stroke pairs come last.

Add to `controls_test.exs`:

```elixir
test "a boolean renders a checkbox that sends false when cleared" do
  param = %Param{name: :tiles, type: :boolean, default: false, doc: "overlay"}
  html = render_component(&controls/1, params: [param], values: %{tiles: false})

  assert html =~ ~s(type="checkbox")
  assert html =~ ~s(type="hidden" name="tiles" value="false")
  refute html =~ ~s(checked)
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix_web/workbench/exhibits test/girihelix_web/workbench/components/controls_test.exs`
Expected: FAIL — `Tilings.tile_ops/2` is undefined, `tiles` is not a parameter, and the boolean control is a select.

- [ ] **Step 3: Implement the overlay and the toggle**

`Tilings.tile_ops/2`:

- `@tile_tints ["#2563eb", "#d97706", "#0d9488", "#db2777", "#7c3aed"]`, `@tile_fill_opacity 0.12`, `@tile_stroke_opacity 0.5`, `@tile_stroke_width 0.75`.
- Lattice is the given `translations`, or `[Transform.identity()]` when the list is empty.
- For each lattice translation and each `%PlacedFeature{}` in `tiling.placements`, compose `Transform.compose(translation, placement.transform)` so the placement runs first, transform the feature's `Feature.points/1`, and emit a fill `{:polygon, points, :fill, [fill: tint, opacity: 0.12]}` and a stroke `{:polygon, points, :stroke, [stroke: tint, width: 0.75, opacity: 0.5]}`.
- Tint: `Enum.at(@tile_tints, rem(placement.feature_id, length(@tile_tints)))`.

`Styles`:

- Add the `tiles` parameter after `palette`.
- `draw/2` composes `List.wrap(background) ++ geometry ++ overlay`, where `overlay` is `Tilings.tile_ops(state.tiling, state.translations)` when `params.tiles` is true and `[]` otherwise. The overlay is emitted after the figure in every frame, including the structure fallback, as a translucent layer on top.

`Controls`: replace the boolean select with a hidden `"false"` input followed by a checkbox with `value="true"` and `checked={@value}`; update the existing boolean test.

- [ ] **Step 4: Run the tests to see them pass**

Run: `mix test test/girihelix_web/workbench/exhibits test/girihelix_web/workbench/components/controls_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/girihelix_web/workbench/exhibits/tilings.ex lib/girihelix_web/workbench/exhibits/styles.ex lib/girihelix_web/workbench/components/controls.ex test/girihelix_web/workbench/exhibits test/girihelix_web/workbench/components/controls_test.exs
git commit -m "feat: add the tile overlay and its toggle"
```

---

### Task 4: Enlarged patch, pinned viewport, seam test, overflow

**Files:**

- Modify: `lib/girihelix/engine/tilings/construct.ex`
- Modify: `lib/girihelix_web/workbench/exhibit.ex`
- Modify: `lib/girihelix_web/workbench/exhibit_live.ex`
- Modify the six exhibits that implement `viewport/1`: `star.ex`, `radial.ex`, `connect.ex`, `scale.ex`, `rosette.ex`, `planar_map.ex`
- Modify: `lib/girihelix_web/workbench/exhibits/styles.ex`
- Modify: `lib/girihelix_web/workbench/components/canvas.ex`
- Tests: `test/girihelix/engine/tilings/construct_test.exs`, `test/girihelix_web/workbench/exhibits/styles_test.exs`, `test/girihelix_web/workbench/exhibit_live_test.exs`, `test/girihelix_web/workbench/components/canvas_test.exs`

**Interfaces:**

- Produces:
  - `Construct.patch_region(Tiling.t(), pos_integer()) :: [Point.t()]` — the bounding rectangle of the unit cell repeated over `m, n` in `-cells..cells`, with the same `0.01` margin as `default_region/1`, corners counter-clockwise.
  - `Exhibit` callback `viewport(params, frames)`; `viewport/1` is removed.
  - `Styles.viewport(params, frames) :: Viewport.t()` — width `2.0 * cell / 0.75` where `cell = max(|t1|, |t2|)`, centred on the final frame's content bounds.
  - The canvas SVG root carries `overflow-visible`; the canvas wrapper clips.

- [ ] **Step 1: Write the failing tests**

Add to `construct_test.exs`:

```elixir
test "the patch region covers a square grid of cells" do
  tiling = Catalogue.load!("8.5")
  region = Construct.patch_region(tiling, 2)
  assert length(region) == 4

  margin = 0.01 * max(Point.mag(tiling.t1), Point.mag(tiling.t2))

  expected =
    for m <- -2..2,
        n <- -2..2,
        p <- [Point.origin(), tiling.t1, Point.add(tiling.t1, tiling.t2), tiling.t2],
        do: Point.add(Point.add(Point.scale(tiling.t1, m), Point.scale(tiling.t2, n)), p)

  xs = Enum.map(expected, & &1.x)
  ys = Enum.map(expected, & &1.y)
  region_xs = Enum.map(region, & &1.x)
  region_ys = Enum.map(region, & &1.y)

  assert_in_delta Enum.min(region_xs), Enum.min(xs) - margin, 1.0e-9
  assert_in_delta Enum.max(region_xs), Enum.max(xs) + margin, 1.0e-9
  assert_in_delta Enum.min(region_ys), Enum.min(ys) - margin, 1.0e-9
  assert_in_delta Enum.max(region_ys), Enum.max(ys) + margin, 1.0e-9
end
```

Add to `styles_test.exs`:

```elixir
test "the viewport shows two cells and is centred on the content" do
  params = defaults()
  frames = Steps.run!(Styles.steps(params), Styles.initial(params))
  viewport = Styles.viewport(params, frames)
  state = List.last(frames).state
  cell = max(Point.mag(state.tiling.t1), Point.mag(state.tiling.t2))

  assert_in_delta viewport.width, 2.0 * cell / 0.75, 1.0e-9
  assert_in_delta viewport.scale, 1000.0 / viewport.width, 1.0e-9
end

test "the windowed interior is periodic in both lattice directions" do
  for tiling <- [:"8.5", :"6.5 flower"] do
    params = %{defaults() | tiling: tiling}
    frames = Steps.run!(Styles.steps(params), Styles.initial(params))
    state = List.last(frames).state
    viewport = Styles.viewport(params, frames)
    map = state.map

    positions =
      map
      |> PlanarMap.vertices()
      |> Enum.map(&rounded_point(PlanarMap.position!(map, &1)))
      |> MapSet.new()

    window = {viewport.left, viewport.top - viewport.width * 0.75, viewport.left + viewport.width, viewport.top}

    inside =
      Enum.filter(positions, fn {x, y} ->
        {min_x, min_y, max_x, max_y} = window
        x > min_x and x < max_x and y > min_y and y < max_y
      end)

    assert inside != []

    for point <- inside, axis <- [state.tiling.t1, state.tiling.t2] do
      target = rounded_point({elem(point, 0) + axis.x, elem(point, 1) + axis.y})
      assert MapSet.member?(positions, target)
    end
  end
end

defp rounded_point(%Point{x: x, y: y}), do: {Float.round(x, 6), Float.round(y, 6)}
defp rounded_point({x, y}), do: {Float.round(x, 6), Float.round(y, 6)}
```

Add `PlanarMap`, `Point` and `Viewport` aliases to the test module.

Add a failure-frame case:

```elixir
test "a failed run still pins a viewport" do
  params = %{defaults() | tiling: :"3-8-12", figure: :star}

  assert {:error, %Steps.Failure{frames: frames}} =
           Steps.run(Styles.steps(params), Styles.initial(params))

  assert %Viewport{} = Styles.viewport(params, frames)
end
```

The exact window bounds and the seam rounding are the test's contract; if a tiling's fringe makes a point miss, widen the patch or shrink the window, not the assertion.

Add to `canvas_test.exs` an assertion that the rendered SVG root includes `overflow-visible`, and to `exhibit_live_test.exs` an assertion that a pinned viewport is used for the styles exhibit.

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix/engine/tilings/construct_test.exs test/girihelix_web/workbench/exhibits/styles_test.exs test/girihelix_web/workbench/components/canvas_test.exs`
Expected: FAIL — `patch_region/2` and `viewport/2` do not exist; the SVG root has no overflow class.

- [ ] **Step 3: Implement the patch, the viewport and the overflow**

- `Construct.patch_region/2`: build the extreme points as in the test, take their bounding box, add the margin, and return the four corners counter-clockwise using the same helper as `default_region/1`.
- `Exhibit`: declare `@callback viewport(params, frames) :: :fit | Viewport.t()` and `@optional_callbacks viewport: 2`; update the module doc.
- `ExhibitLive`: `exports_viewport?/1` checks arity `2`; `pinned_viewport` calls `exhibit.viewport(values, frames)`. Thread `frames` through the `viewport/3` helper.
- Update the six existing `viewport/1` implementations to `viewport(params, _frames)`.
- `Styles`: `@patch_cells 2`, `@visible_cells 2.0`, `@canvas_aspect 0.75`, `@nominal_width 1000.0`. `initial/1` and `steps/1` use `Construct.patch_region(tiling, @patch_cells)`. `viewport/2` takes the last frame's state, computes `cell`, `width`, and the content centre from the **constructed map's vertex bounds** when the map has vertices, otherwise from the structure ops' bounds — never from the painted ops, because those include the tile overlay when it is on and would expand the window to the whole patch. If no bounds exist, return `Viewport.fit(nil)`.
- `Canvas`: change `@svg_class` to `"w-full h-auto overflow-visible"` and add `overflow-hidden` to the canvas wrappers.

- [ ] **Step 4: Run the tests to see them pass**

Run: `mix test test/girihelix/engine/tilings/construct_test.exs test/girihelix_web/workbench`
Expected: PASS. Tune `@visible_cells` only if the seam test fails for a tiling; do not loosen the seam assertion.

- [ ] **Step 5: Measure the largest tilings**

Run a focused timing for `Girih Star` and `7.6` at the 5×5 patch, and time `mix test test/girihelix_web/workbench/registry_test.exs`. Record the numbers in the report. If the registry suite becomes unacceptably slow, keep two visible cells and note three as a follow-up.

- [ ] **Step 6: Commit**

```bash
git add lib/girihelix/engine/tilings/construct.ex lib/girihelix_web/workbench test/girihelix/engine/tilings/construct_test.exs
git commit -m "feat: pin a seamless patch viewport and allow panning past it"
```

---

### Task 5: `CanvasZoom` hook on every canvas

**Files:**

- Create: `assets/js/canvas_zoom.js`
- Modify: `assets/js/app.js`
- Modify: `lib/girihelix_web/workbench/components/canvas.ex`
- Test: `test/girihelix_web/workbench/components/canvas_test.exs`

**Interfaces:**

- Produces: hook `CanvasZoom`, attached to the `id="canvas"` wrapper on every canvas. The wrapper contains an inner `[data-zoom-content]` element, and buttons with `data-zoom="in" | "out" | "reset"`.

- [ ] **Step 1: Write the failing component test**

```elixir
test "the canvas carries the zoom hook and its controls" do
  html = render_canvas(...)
  assert html =~ ~s(phx-hook="CanvasZoom")
  assert html =~ ~s(data-zoom-content)
  assert html =~ ~s(data-zoom="in")
  assert html =~ ~s(data-zoom="out")
  assert html =~ ~s(data-zoom="reset")
end
```

`render_canvas/1` stands for the existing rendering helper in that test file; use it the way the other tests do.

- [ ] **Step 2: Run it to see it fail**

Run: `mix test test/girihelix_web/workbench/components/canvas_test.exs`
Expected: FAIL — no hook attributes.

- [ ] **Step 3: Implement the hook and the markup**

`assets/js/canvas_zoom.js`:

```js
const MIN_SCALE = 0.6
const MAX_SCALE = 8.0

export const CanvasZoom = {
  mounted() {
    this.content = this.el.querySelector("[data-zoom-content]")
    this.scale = 1
    this.x = 0
    this.y = 0
    this.pointers = new Map()
    this.el.style.touchAction = "none"
    this.el.addEventListener("pointerdown", e => this.down(e))
    this.el.addEventListener("pointermove", e => this.move(e))
    this.el.addEventListener("pointerup", e => this.up(e))
    this.el.addEventListener("pointercancel", e => this.up(e))
    this.el.addEventListener("wheel", e => this.wheel(e), {passive: false})
    for (const button of this.el.querySelectorAll("[data-zoom]")) {
      button.addEventListener("click", () => this.button(button.dataset.zoom))
    }
    this.apply()
  },
  destroyed() { this.el.style.touchAction = "" },
  down(e) {
    if (e.target.closest("[data-zoom]")) return
    this.el.setPointerCapture(e.pointerId)
    this.pointers.set(e.pointerId, {x: e.clientX, y: e.clientY})
  },
  move(e) {
    const previous = this.pointers.get(e.pointerId)
    if (!previous) return
    const next = {x: e.clientX, y: e.clientY}
    this.pointers.set(e.pointerId, next)
    if (this.pointers.size === 1) {
      this.x += next.x - previous.x
      this.y += next.y - previous.y
    } else {
      const [a, b] = [...this.pointers.values()]
      const distance = Math.hypot(a.x - b.x, a.y - b.y)
      if (this.lastDistance) {
        const rect = this.el.getBoundingClientRect()
        this.zoomAt((a.x + b.x) / 2, (a.y + b.y) / 2, rect, distance / this.lastDistance)
      }
      this.lastDistance = distance
    }
    this.apply()
  },
  up(e) {
    this.pointers.delete(e.pointerId)
    if (this.pointers.size < 2) this.lastDistance = 0
  },
  wheel(e) {
    if (!(e.ctrlKey || e.metaKey)) return
    e.preventDefault()
    const rect = this.el.getBoundingClientRect()
    this.zoomAt(e.clientX, e.clientY, rect, Math.exp(-e.deltaY * 0.002))
  },
  zoomAt(clientX, clientY, rect, factor) {
    const next = Math.min(MAX_SCALE, Math.max(MIN_SCALE, this.scale * factor))
    const applied = next / this.scale
    const px = clientX - rect.left - this.x
    const py = clientY - rect.top - this.y
    this.x -= px * (applied - 1)
    this.y -= py * (applied - 1)
    this.scale = next
  },
  button(action) {
    const rect = this.el.getBoundingClientRect()
    if (action === "in") this.zoomAt(rect.left + rect.width / 2, rect.top + rect.height / 2, rect, 1.25)
    if (action === "out") this.zoomAt(rect.left + rect.width / 2, rect.top + rect.height / 2, rect, 0.8)
    if (action === "reset") { this.scale = 1; this.x = 0; this.y = 0 }
    this.apply()
  },
  apply() {
    if (!this.content) return
    this.content.style.transformOrigin = "0 0"
    this.content.style.transform = `translate(${this.x}px, ${this.y}px) scale(${this.scale})`
  }
}
```

Register it in `app.js` as `hooks: {RailDrawer, CanvasZoom, ...colocatedHooks}`.

In `Canvas`, wrap the SVG in `<div data-zoom-content>` inside the `#canvas` wrapper, add `phx-hook="CanvasZoom"` and `overflow-hidden relative` to the wrapper, and render the three buttons in an absolutely positioned corner group.

- [ ] **Step 4: Run the component tests**

Run: `mix test test/girihelix_web/workbench/components/canvas_test.exs`
Expected: PASS.

- [ ] **Step 5: Check in the browser**

Ask the user to check drag, pinch/ctrl-wheel, and reset on an exhibit. Note in the report that this is manual evidence.

- [ ] **Step 6: Commit**

```bash
git add assets/js/canvas_zoom.js assets/js/app.js lib/girihelix_web/workbench/components/canvas.ex test/girihelix_web/workbench/components/canvas_test.exs
git commit -m "feat: add pan and zoom to every workbench canvas"
```

---

### Task 6: Palette parameter type and swatch picker

**Files:**

- Modify: `lib/girihelix_web/workbench/param.ex`
- Modify: `lib/girihelix_web/workbench/components/controls.ex`
- Modify: `lib/girihelix_web/workbench/exhibits/styles.ex`
- Tests: `test/girihelix_web/workbench/param_test.exs`, `test/girihelix_web/workbench/components/controls_test.exs`, `test/girihelix_web/workbench/exhibits/styles_test.exs`

**Interfaces:**

- Produces: `Param.type :: :integer | :float | :boolean | :enum | :palette`; a `:palette` decodes and encodes like `:enum`. The styles exhibit declares `palette` with `type: :palette`.

- [ ] **Step 1: Write the failing tests**

```elixir
test "a palette parameter round-trips like an enum" do
  param = %Param{name: :palette, type: :palette, options: [:"1", :"253", :"348"], default: :"253"}
  values = Param.decode([param], %{"palette" => "348"})
  assert values.palette == :"348"
  assert Param.encode([param], values) == %{"palette" => "348"}
  assert Param.values([param], :first) == %{palette: :"1"}
end

test "the palette control renders a swatch row per combination" do
  param = %Param{name: :palette, type: :palette, options: [:"1", :"253"], default: :"253"}
  html = render_component(&controls/1, params: [param], values: %{palette: :"253"})
  assert html =~ ~s(type="radio")
  assert html =~ "background-color: #de4500"
  assert html =~ "background-color: #340059"
  assert html =~ ~s(checked)
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix_web/workbench/param_test.exs test/girihelix_web/workbench/components/controls_test.exs`
Expected: FAIL — `:palette` is not a valid type and the control has no palette clause.

- [ ] **Step 3: Implement the type and the picker**

In `Param`: add `:palette` to the type union and to `parse/2` (delegate to `parse_enum/2`), `encode_value/2` and `extreme/2` (same clauses as `:enum`). Update the module doc.

In `Controls`: add a `control(%{param: %Param{type: :palette}})` clause that renders a `<fieldset>` with a `<legend>` from `control_label/1`, then a `max-h-72 overflow-y-auto` list of radio rows. Each row shows the combination number and one span per `Palette.combination(option)` colour:

```heex
<span class="h-3 w-3 rounded-sm" style={"background-color: #{hex}"}></span>
```

The radio's `name` is the parameter name and its value is `to_string(option)`; the selected option carries `checked`. Alias `Girihelix.Engine.Render.Palette` in the component.

In `Styles`, change the palette parameter's type from `:enum` to `:palette`.

- [ ] **Step 4: Run the tests to see them pass**

Run: `mix test test/girihelix_web/workbench/param_test.exs test/girihelix_web/workbench/components/controls_test.exs test/girihelix_web/workbench/exhibits/styles_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/girihelix_web/workbench/param.ex lib/girihelix_web/workbench/components/controls.ex lib/girihelix_web/workbench/exhibits/styles.ex test/girihelix_web/workbench
git commit -m "feat: pick palettes from swatch rows"
```

---

### Task 7: Homogenisation, documents, full gate

**Files:**

- Modify the modules touched by Tasks 1–6
- Modify: `docs/superpowers/specs/2026-10-24-girihelix-styles-presentation-design.md`
- Modify: `docs/backlog.md`

**Interfaces:**

- Consumes: every prior task.
- Produces: the branch ready to push.

- [ ] **Step 1: Run the full gate**

Run: `mix precommit`
Expected: format, Credo, Sobelow, the suite under coverage and `mix dialyzer` all pass with `Total errors: 0`.

- [ ] **Step 2: Fix what the gate reports**

Fix findings in the touched modules only; rerun until clean. Do not loosen a check.

- [ ] **Step 3: Homogenise**

Re-read every touched module against the project rules: no `if`/`cond`, guards on separate clauses, error tuples with bang twins, module docs describing behaviour rather than source narration, no module over 800 lines. Check that `mix format` has not displaced section comments or reordered aliases.

- [ ] **Step 4: Update the documents**

Set the design's status to accepted, dated 2026-10-24, and record the implementation decisions that differ from the draft: the final visible-cell choice from the timing measurement, the derived-tone constants, the overlay tints, and the viewport formula. Add backlog items only for real deferrals, such as a three-cell window if two shipped, and palette search.

- [ ] **Step 5: Measure and record**

Run the timing measurement from Task 4 Step 5 again after the final changes, and record the registry-suite time in the report.

- [ ] **Step 6: Ask the user to judge the result**

Ask the user to open `/workbench/styles` and check the seamless fill, the tile overlay, pan/zoom and the palette picker. Adjust the overlay tints or the visible-cell count if they ask; rerun the affected tests.

- [ ] **Step 7: Commit**

```bash
git add lib test assets/js docs/superpowers/specs/2026-10-24-girihelix-styles-presentation-design.md docs/backlog.md
git commit -m "chore: homogenise the styles presentation and record the decisions"
```

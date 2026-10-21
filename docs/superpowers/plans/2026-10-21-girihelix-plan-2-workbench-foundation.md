# Workbench foundation implementation plan (Plan 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the workbench foundation: a closed draw-op vocabulary and SVG
serializer, a viewport, a declarative exhibit framework with eight geometry
exhibits, and `/workbench` with canvas, transport, source and reproduce panes
whose state lives in the URL.

**Architecture:** Three layers, one direction of dependency. Engine modules
(`Girihelix.Engine.Render.*`) produce and serialize draw ops with the standard
library only. Web modules (`GirihelixWeb.Workbench.*`) define the exhibit
behaviour, parameter decoding, the registry and the panes. LiveViews at
`/workbench` and `/workbench/:slug` read the engine's `Steps` frames and render
them; the URL is the whole state.

**Tech Stack:** Elixir 1.20.3, Phoenix 1.8, LiveView 1.2, ExUnit, Tailwind and
daisyUI. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-16-girihelix-workbench-design.md`.
Plan 2 is the design's plan-series row 2 and its Plan 2 exhibit inventory. Read
the design in full first; the plan argues from it.

## Global Constraints

- **Engine purity.** `lib/girihelix/engine/**` imports the standard library
  only. `test/girihelix/engine/architecture_test.exs` already enforces no Ash,
  Ecto, Phoenix or `GirihelixWeb` reference.
- **The source pane reads `lib/` only.** Never `reference/`; its licences do
  not permit serving it.
- **No inline `<script>`.** The only JavaScript change is a listener in
  `assets/js/app.js`.
- **The draw-op vocabulary is closed.** The serializer raises on an unknown op
  and on an option the op does not accept.
- **URL is the state.** Parameter and frame changes go through `handle_params`
  and `push_patch`. Absence of `frame` means the last frame.
- **A run is capped at 200 frames** through `Steps.run/3`'s `:max_frames`.
- **Hard rules.** No `if` or `cond`; branch in function heads and guards. A
  failing public function returns `{:error, reason}` and has a `name!` twin.
  A `case` matching `{:ok, _}` / `{:error, _}` is pattern matching, not a
  conditional.
- **Gates.** `mix dialyzer` reports `Total errors: 0` before every commit. No
  module may exceed 800 lines.
- **Tooling.** Lint Markdown with
  `markdownlint-cli2 --config ~/.markdownlint-cli2.jsonc`. `mix format` runs
  Styler; check `# --` section comments after formatting. If a 1Password
  signing error occurs on commit, stop and ask the user. Never start or stop
  the dev server on port 4000.

## Review Focus

1. **A drawing with no geometry.** An empty op list, or a frame before anything
   is built, must render an empty SVG with the default viewport rather than
   raising. Owner: Tasks 1 and 12.
2. **An out-of-range or non-numeric URL parameter.** It must clamp or fall back
   to the default, never crash. Owner: Task 3.
3. **A step that raises.** Coincident segment endpoints must render the failure
   state with the frames that did build, not a 500. Owner: Task 15.
4. **A source file outside `lib/` or missing on disk.** The source pane must say
   it is unavailable and the exhibit must still work. Owner: Task 14.
5. **An intermediate frame with an incomplete state.** `FillRegion` before the
   scan and `Faces` before colouring must draw without raising. Owner:
   Tasks 10, 11 and the registry property test in Task 4.

---

### Task 1: Draw ops, bounds and the viewport

**Files:**

- Create: `lib/girihelix/engine/render/op.ex`
- Create: `lib/girihelix/engine/render/bounds.ex`
- Create: `lib/girihelix/engine/render/viewport.ex`
- Create: `test/girihelix/engine/render/op_test.exs`
- Create: `test/girihelix/engine/render/bounds_test.exs`
- Create: `test/girihelix/engine/render/viewport_test.exs`

**Interfaces:**

- `Girihelix.Engine.Render.Op`
  - `@type point :: {number(), number()}` — map space, y-up.
  - `@type opts :: keyword()` — a point's radius and a label's font size are in
    SVG units, not map units, so markers keep their screen size as the viewport
    changes.
  - `@type t :: {:line, point(), point(), opts()} | {:polygon, [point()], :fill | :stroke, opts()} | {:point, point(), number(), opts()} | {:label, point(), String.t(), opts()} | {:guide, point(), point(), opts()}`
  - `known?(term()) :: boolean()`
  - `points(t()) :: [point()]` — the op's positional points; raises
    `ArgumentError` for an unknown op.
- `Girihelix.Engine.Render.Bounds`
  - `@type t :: {number(), number(), number(), number()}` —
    `{min_x, min_y, max_x, max_y}` in map space.
  - `of_ops([Op.t()]) :: t() | nil` — `nil` when no op has a point.
  - `pad(t(), number()) :: t()`
- `Girihelix.Engine.Render.Viewport`
  - `@enforce_keys [:left, :top, :width, :scale]`
  - `@type t :: %__MODULE__{left: float(), top: float(), width: float(), scale: float()}`
  - `fit(Bounds.t() | nil, keyword()) :: t()` — options `:padding` (fraction of
    the larger extent, default `0.1`), `:aspect` (height/width, default `0.75`),
    `:scale` (default `1.0`). `nil` bounds give
    `%Viewport{left: -1.0, top: 1.0, width: 2.0, scale: 1.0}`.
  - `project(t(), Op.point()) :: {float(), float()}` — SVG coordinates,
    `{(x - left) * scale, (top - y) * scale}`.
  - `view_box(t(), number()) :: {float(), float(), float(), float()}` —
    `{0.0, 0.0, width * scale, width * aspect * scale}`.

- [ ] **Step 1: Write the failing op tests**

```elixir
test "known?/1 accepts the five ops and rejects anything else" do
  assert Op.known?({:line, {0.0, 0.0}, {1.0, 1.0}, []})
  assert Op.known?({:polygon, [{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}], :fill, []})
  assert Op.known?({:point, {2.0, 3.0}, 0.5, []})
  assert Op.known?({:label, {2.0, 3.0}, "hi", []})
  assert Op.known?({:guide, {0.0, 0.0}, {1.0, 1.0}, []})
  refute Op.known?({:arc, {0.0, 0.0}, {1.0, 1.0}, []})
  refute Op.known?(:nope)
end

test "points/1 returns every positional point" do
  assert Op.points({:line, {0.0, 0.0}, {1.0, 1.0}, []}) == [{0.0, 0.0}, {1.0, 1.0}]
  assert Op.points({:guide, {0.0, 0.0}, {1.0, 1.0}, []}) == [{0.0, 0.0}, {1.0, 1.0}]
  assert Op.points({:polygon, [{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}], :stroke, []}) ==
           [{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}]

  assert Op.points({:point, {2.0, 3.0}, 0.5, []}) == [{2.0, 3.0}]
  assert Op.points({:label, {2.0, 3.0}, "hi", []}) == [{2.0, 3.0}]
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix/engine/render/op_test.exs`
Expected: FAIL, `Girihelix.Engine.Render.Op` is undefined.

- [ ] **Step 3: Write the failing bounds and viewport tests**

```elixir
test "of_ops/1 spans every positional point and is nil without one" do
  assert Bounds.of_ops([]) == nil
  assert Bounds.of_ops([{:label, {1.0, 1.0}, "x", []}]) == {1.0, 1.0, 1.0, 1.0}

  assert Bounds.of_ops([{:line, {0.0, 0.0}, {4.0, 3.0}, []}]) ==
           {0.0, 0.0, 4.0, 3.0}

  assert Bounds.of_ops([
           {:line, {0.0, 0.0}, {4.0, 0.0}, []},
           {:point, {-1.0, 2.0}, 0.5, []}
         ]) == {-1.0, 0.0, 4.0, 2.0}
end

test "pad/2 grows every side" do
  assert Bounds.pad({0.0, 0.0, 4.0, 3.0}, 1.0) == {-1.0, -1.0, 5.0, 4.0}
end

test "fit/2 frames bounds with padding and aspect" do
  # padding 0, square aspect: the bounds are the view.
  assert Viewport.fit({0.0, 0.0, 10.0, 10.0}, padding: 0.0, aspect: 1.0) ==
           %Viewport{left: 0.0, top: 10.0, width: 10.0, scale: 1.0}

  # padding 0.1 of the larger extent: 12 x 12.
  assert Viewport.fit({0.0, 0.0, 10.0, 10.0}, aspect: 1.0) ==
           %Viewport{left: -1.0, top: 11.0, width: 12.0, scale: 1.0}

  # A wide aspect widens the view and re-centres the content in x.
  assert Viewport.fit({0.0, 0.0, 10.0, 10.0}, padding: 0.0, aspect: 0.5) ==
           %Viewport{left: -5.0, top: 10.0, width: 20.0, scale: 1.0}
end

test "fit/2 handles nil and degenerate bounds" do
  assert Viewport.fit(nil) == %Viewport{left: -1.0, top: 1.0, width: 2.0, scale: 1.0}

  # A single point gets a 2 x 2 box centred on it.
  assert Viewport.fit({1.0, 2.0, 1.0, 2.0}, padding: 0.0, aspect: 1.0) ==
           %Viewport{left: 0.0, top: 3.0, width: 2.0, scale: 1.0}
end

test "project/2 flips y and view_box/2 carries the aspect" do
  vp = %Viewport{left: 0.0, top: 10.0, width: 10.0, scale: 2.0}

  assert Viewport.project(vp, {0.0, 0.0}) == {0.0, 20.0}
  assert Viewport.project(vp, {10.0, 10.0}) == {20.0, 0.0}
  assert Viewport.view_box(vp, 0.75) == {0.0, 0.0, 20.0, 15.0}
end
```

- [ ] **Step 4: Run them to see them fail**

Run: `mix test test/girihelix/engine/render/bounds_test.exs test/girihelix/engine/render/viewport_test.exs`
Expected: FAIL, the modules are undefined.

- [ ] **Step 5: Implement `Op`, `Bounds` and `Viewport`**

`Op` validates the five tuple shapes; `points/1` raises
`ArgumentError, "unknown draw op"` otherwise. `Bounds.of_ops/1` flat-maps
`Op.points/1`. `Viewport.fit/2` pads by `max(width, height) * padding`, takes
`view_width = max(padded_width, padded_height / aspect)`, centres the content in
the view, and sets `top = centre_y + view_width * aspect / 2`. A degenerate
bound with zero width and height uses a 2.0 by 2.0 box.

- [ ] **Step 6: Run the tests to see them pass**

Run: `mix test test/girihelix/engine/render/`
Expected: PASS.

- [ ] **Step 7: Gates and commit**

Run `mix precommit.fast && mix dialyzer` (`Total errors: 0`), then:

```bash
git add lib/girihelix/engine/render test/girihelix/engine/render
git commit -m "feat: add the draw-op vocabulary, bounds and viewport"
```

### Task 2: The SVG serializer

**Files:**

- Create: `lib/girihelix/engine/render/svg.ex`
- Create: `test/girihelix/engine/render/svg_test.exs`

**Interfaces:**

- `Girihelix.Engine.Render.Svg.render(ops :: [Op.t()], viewport :: Viewport.t(), opts :: keyword()) :: String.t()`
  - `opts`: `:aspect` (default `0.75`), `:class` (default `nil`).
  - Root: `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0.0 0.0 W H">`
    with `class="…"` when given.
  - `{:line, from, to, opts}` → `<line x1 y1 x2 y2 stroke stroke-width>`.
    Defaults: `stroke: "currentColor"`, `width: 1.0`.
  - `{:guide, …}` → the line shape with default `dash: "4 4"`.
  - `{:polygon, points, :fill, opts}` → `<polygon points="x,y x,y …" fill>`;
    default `fill: "currentColor"`, `stroke: "none"`. For `:stroke`, default
    `fill: "none"`, `stroke: "currentColor"`. `width` defaults to `1.0`.
  - `{:point, at, radius, opts}` → `<circle cx cy r fill>`, default fill
    `"currentColor"`.
  - `{:label, at, text, opts}` → `<text x y fill font-size>`, defaults fill
    `"currentColor"`, size `12.0`; the text is XML-escaped.
  - Allowed options per op: line/guide `:stroke, :width, :dash, :opacity`;
    polygon all five; point `:fill, :stroke, :width, :opacity`; label
    `:fill, :opacity`. An unknown op or option raises `ArgumentError`.
  - Numbers render through `Float.round(value, 4) |> to_string()`.

- [ ] **Step 1: Write the failing tests**

```elixir
test "renders every op with its defaults" do
  vp = %Viewport{left: 0.0, top: 10.0, width: 10.0, scale: 1.0}

  svg =
    Svg.render(
      [
        {:line, {0.0, 0.0}, {10.0, 10.0}, []},
        {:polygon, [{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}], :fill, []},
        {:point, {1.0, 2.0}, 0.5, []},
        {:label, {0.0, 0.0}, "a < b", []},
        {:guide, {0.0, 0.0}, {1.0, 1.0}, []}
      ],
      vp
    )

  assert svg =~ ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0.0 0.0 10.0 7.5">)
  assert svg =~ ~s(<line x1="0.0" y1="10.0" x2="10.0" y2="0.0" stroke="currentColor" stroke-width="1.0")
  assert svg =~ ~s(<polygon points="0.0,10.0 1.0,10.0 0.0,9.0" fill="currentColor" stroke="none")
  assert svg =~ ~s(<circle cx="1.0" cy="8.0" r="0.5" fill="currentColor")
  assert svg =~ "a &lt; b"
  assert svg =~ ~s(stroke-dasharray="4 4")
end

test "options override the defaults" do
  vp = %Viewport{left: 0.0, top: 0.0, width: 1.0, scale: 1.0}

  svg = Svg.render([{:line, {0.0, 0.0}, {1.0, 0.0}, stroke: "red", width: 3.0, opacity: 0.5}], vp)

  assert svg =~ ~s(stroke="red")
  assert svg =~ ~s(stroke-width="3.0")
  assert svg =~ ~s(opacity="0.5")
end

test "an empty op list still renders a root with the class" do
  vp = %Viewport{left: 0.0, top: 0.0, width: 1.0, scale: 1.0}
  assert Svg.render([], vp, class: "w-full") =~ ~s(class="w-full")
end

test "an unknown op or option raises" do
  vp = %Viewport{left: 0.0, top: 0.0, width: 1.0, scale: 1.0}

  assert_raise ArgumentError, ~r/unknown draw op/, fn ->
    Svg.render([{:arc, {0.0, 0.0}, {1.0, 0.0}, []}], vp)
  end

  assert_raise ArgumentError, ~r/unknown draw option/, fn ->
    Svg.render([{:line, {0.0, 0.0}, {1.0, 0.0}, colour: "red"}], vp)
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix/engine/render/svg_test.exs`
Expected: FAIL, `Svg` is undefined.

- [ ] **Step 3: Implement `Svg`**

Build the root and one element per op. Escape `&`, `<`, `>`, `"` and `'` in
labels. Raise `ArgumentError, "unknown draw op: …"` and
`ArgumentError, "unknown draw option: …"`.

- [ ] **Step 4: Run them to see them pass**

Run: `mix test test/girihelix/engine/render/svg_test.exs`
Expected: PASS.

- [ ] **Step 5: Gates and commit**

Commit message: `feat: serialize draw ops to SVG`.

### Task 3: The parameter type and URL decoding

**Files:**

- Create: `lib/girihelix_web/workbench/param.ex`
- Create: `test/girihelix_web/workbench/param_test.exs`

**Interfaces:**

- `#GirihelixWeb.Workbench.Param{}` with fields `:name` (atom), `:type`
  (`:integer | :float | :boolean | :enum`), `:default`, `:doc`, `:range`
  (an integer `Range.t()` or nil — Elixir 1.20.3 ranges reject float bounds,
  so a `:float` param uses an integer range and a float `:step`, and its
  decoded values are coerced to floats), `:step` (number or nil), `:options`
  (`[atom]` for `:enum`, nil otherwise).
- `decode([Param.t()], map()) :: %{atom() => integer() | float() | boolean() | atom()}`
  — string-keyed input; unknown keys are ignored; missing or invalid values
  fall back to the default; numeric values clamp to `range.first..range.last`.
- `encode([Param.t()], %{atom() => term()}) :: %{String.t() => String.t()}`
- `values([Param.t()], :default | :first | :last) :: %{atom() => term()}` — the
  defaults, every param at its range first, or every param at its range last
  (an enum's first/last option, a boolean's `false`/`true`).

- [ ] **Step 1: Write the failing tests**

```elixir
@params [
  %Param{name: :n, type: :integer, range: 3..24, default: 8, doc: "order"},
  %Param{name: :d, type: :float, range: 1..10, step: 0.1, default: 3.0, doc: "skip"},
  %Param{name: :on, type: :boolean, default: true, doc: "toggle"},
  %Param{name: :shape, type: :enum, options: [:square, :triangle], default: :square, doc: "shape"}
]

test "decode/2 falls back to defaults" do
  assert Param.decode(@params, %{}) == %{n: 8, d: 3.0, on: true, shape: :square}
end

test "decode/2 clamps numbers and rejects garbage" do
  assert Param.decode(@params, %{"n" => "99", "d" => "-4.0"})[:n] == 24
  assert Param.decode(@params, %{"n" => "99", "d" => "-4.0"})[:d] == 1.0
  assert Param.decode(@params, %{"n" => "x", "d" => "x"})[:n] == 8
  assert Param.decode(@params, %{"n" => "x", "d" => "x"})[:d] == 3.0
end

test "decode/2 reads booleans and enums" do
  assert Param.decode(@params, %{"on" => "false"})[:on] == false
  assert Param.decode(@params, %{"on" => "nonsense"})[:on] == true
  assert Param.decode(@params, %{"shape" => "triangle"})[:shape] == :triangle
  assert Param.decode(@params, %{"shape" => "hexagon"})[:shape] == :square
end

test "encode/2 round-trips through decode/2" do
  values = %{n: 12, d: 4.5, on: false, shape: :triangle}
  encoded = Param.encode(@params, values)

  assert encoded == %{"n" => "12", "d" => "4.5", "on" => "false", "shape" => "triangle"}
  assert Param.decode(@params, encoded) == values
end

test "values/2 gives the defaults and both extremes" do
  assert Param.values(@params, :default) == %{n: 8, d: 3.0, on: true, shape: :square}
  assert Param.values(@params, :first) == %{n: 3, d: 1.0, on: false, shape: :square}
  assert Param.values(@params, :last) == %{n: 24, d: 10.0, on: true, shape: :triangle}
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix_web/workbench/param_test.exs`
Expected: FAIL, `Param` is undefined.

- [ ] **Step 3: Implement `Param`**

Decode with per-type clauses; clamp numerics with `min`/`max` against
`range.first`/`range.last`. No `if`/`cond`.

- [ ] **Step 4: Run them to see them pass**

Run: `mix test test/girihelix_web/workbench/param_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

Commit message: `feat: add declarative workbench parameters`.

### Task 4: Exhibit behaviour, registry and the Loose exhibit

**Files:**

- Create: `lib/girihelix_web/workbench/exhibit.ex`
- Create: `lib/girihelix_web/workbench/registry.ex`
- Create: `lib/girihelix_web/workbench/exhibits/loose.ex`
- Create: `test/girihelix_web/workbench/registry_test.exs`
- Create: `test/girihelix_web/workbench/exhibits/loose_test.exs`

**Interfaces:**

- `GirihelixWeb.Workbench.Exhibit`
  - `@type drawing :: {:canvas, [Op.t()]} | {:panel, [{String.t(), String.t()}]} | {:both, [Op.t()], [{String.t(), String.t()}]}`
  - Callbacks: `slug/0`, `title/0`, `summary/0`, `category/0` (atom),
    `params/0`, `initial(params :: map()) :: term()`,
    `steps(params :: map()) :: [Steps.Step.t()]`,
    `draw(frame :: Steps.Frame.t(), params :: map()) :: drawing()`,
    `reproduce(params :: map()) :: String.t()`,
    `viewport(params :: map()) :: :fit | Viewport.t()` (optional).
- `GirihelixWeb.Workbench.Registry`
  - `exhibits() :: [module()]`
  - `grouped() :: [{atom(), [module()]}]` — non-empty categories in first-seen
    order.
  - `get(slug :: String.t()) :: {:ok, module()} | {:error, :unknown_exhibit}`
- `GirihelixWeb.Workbench.Exhibits.Loose`
  - slug `"loose"`, category `:geometry`, no params.
  - `steps/1` is one `:build` step whose run is identity; `initial/1` is `%{}`.
  - `draw/2` is `{:panel, rows}` with rows:
    - `{"tol/0", "1.0e-7"}`
    - `{"tol2/0", "1.0e-10"}`
    - `{"equals(1.0, 1.0 + 1.0e-8)", "true"}`
    - `{"near(1.0e-8, 1.0e-7)", "true"}`
    - `{"near two points 1.0e-6 apart, tolerance 1.0e-10", "true"}` — the
      squared-distance trap: the squared distance is `1.0e-12`, below the
      tolerance, so points much further apart than the tolerance suggests are
      "near".

- [ ] **Step 1: Write the failing registry and exhibit tests**

```elixir
test "the registry has unique slugs and one non-empty group" do
  slugs = Enum.map(Registry.exhibits(), & &1.slug())
  assert slugs == Enum.uniq(slugs)
  assert Registry.grouped() |> Enum.map(&elem(&1, 0)) == [:geometry]
  assert {:ok, GirihelixWeb.Workbench.Exhibits.Loose} = Registry.get("loose")
  assert Registry.get("nope") == {:error, :unknown_exhibit}
end

test "every exhibit draws at its defaults and extremes" do
  for exhibit <- Registry.exhibits(),
      values <- variants(exhibit) do
    run = Steps.run(exhibit.steps(values), exhibit.initial(values), max_frames: 200)

    case run do
      {:ok, frames} ->
        assert frames != []

        for frame <- frames do
          assert_drawing(exhibit.draw(frame, values))
        end

      {:error, %Steps.Failure{step: %Steps.Step{}}} ->
        :ok
    end
  end
end

defp variants(exhibit) do
  params = exhibit.params()
  defaults = Param.values(params, :default)

  [defaults] ++
    for param <- params,
        mode <- [:first, :last],
        do: Map.put(defaults, param.name, Param.values([param], mode)[param.name])
end

defp assert_drawing({:canvas, ops}), do: assert(ops != [])
defp assert_drawing({:panel, rows}), do: assert(rows != [])
defp assert_drawing({:both, ops, rows}), do: assert(ops != [] and rows != [])
```

Also assert the Loose rows exactly.

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix_web/workbench/`
Expected: FAIL, the modules are undefined.

- [ ] **Step 3: Implement the behaviour, registry and Loose**

Declare the callbacks and `@optional_callbacks viewport: 1`. The registry holds
`@exhibits [Loose]` and derives categories from `category/0`. Adding an exhibit
is one module plus one line in `@exhibits`; the framework itself does not
change.

- [ ] **Step 4: Run them to see them pass**

Run: `mix test test/girihelix_web/workbench/`
Expected: PASS.

- [ ] **Step 5: Commit**

Commit message: `feat: add the exhibit behaviour, registry and Loose exhibit`.

### Task 5: The Point exhibit

**Files:**

- Create: `lib/girihelix_web/workbench/exhibits/point.ex`
- Modify: `lib/girihelix_web/workbench/registry.ex`
- Create: `test/girihelix_web/workbench/exhibits/point_test.exs`

**Interfaces:**

- Params: `x` and `y`, floats in `-5..5`, step `0.1`, defaults `3.0` and
  `4.0`.
- `initial/1` returns the params map; `steps/1` is one `:build` identity step.
- `draw/2` is `{:both, ops, rows}`:
  - ops: the origin as a point marker, a line from the origin to `(x, y)`, and
    the point `(x, y)` as a larger marker.
  - rows: `{"x", "3.0"}`, `{"y", "4.0"}`, `{"mag", "5.0"}`, `{"mag2", "25.0"}`,
    `{"angle", "0.9272952180016122"}`, `{"perp", "-4.0, 3.0"}`.
- `reproduce/1` returns the fully qualified, pasteable
  `"Girihelix.Engine.Geometry.Point.new(3.0, 4.0)"` at the defaults. Every
  exhibit's snippet is fully qualified for the same reason: a fresh
  `iex -S mix` has no `Point` alias.

- [ ] **Step 1: Write the failing test**

```elixir
test "at the defaults it draws the point and reports its measures" do
  values = Param.values(Exhibit.params(), :default)
  frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
  assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

  assert Enum.any?(ops, &match?({:point, {3.0, 4.0}, _, _}, &1))
  assert Enum.any?(ops, &match?({:line, {0.0, 0.0}, {3.0, 4.0}, _}, &1))
  assert {"mag", "5.0"} in rows
  assert {"mag2", "25.0"} in rows
  assert Exhibit.reproduce(values) == "Girihelix.Engine.Geometry.Point.new(3.0, 4.0)"
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `mix test test/girihelix_web/workbench/exhibits/point_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement and register the exhibit**

Add it to `@exhibits`.

- [ ] **Step 4: Run the exhibit and registry tests**

Run: `mix test test/girihelix_web/workbench/`
Expected: PASS.

- [ ] **Step 5: Commit**

Commit message: `feat: add the Point workbench exhibit`.

### Task 6: The Transform exhibit

**Files:**

- Create: `lib/girihelix_web/workbench/exhibits/transform.ex`
- Modify: `lib/girihelix_web/workbench/registry.ex`
- Create: `test/girihelix_web/workbench/exhibits/transform_test.exs`

**Interfaces:**

- Params: `a`, `b`, `c`, `d`, `e`, `f` (floats in `-2..2`, step `0.1`;
  defaults `1.0, 0.0, 1.0, 0.0, 1.0, 0.0`) and `shape` (enum
  `[:square, :triangle]`, default `:square`).
- The shape is the unit square `(0,0), (1,0), (1,1), (0,1)` or the triangle
  `(0,0), (1,0), (0,1)`.
- `draw/2` is `{:both, ops, rows}`:
  - ops: the source shape as `{:guide, …}` lines, the transformed shape as a
    `{:polygon, points, :stroke, []}`, and its vertices as point markers.
  - rows: the six scalars, `{"determinant", "1.0"}`, `{"flips", "false"}`.
- `reproduce/1` returns the fully qualified
  `"Girihelix.Engine.Geometry.Transform.new(1.0, 0.0, 1.0, 0.0, 1.0, 0.0)"`.

- [ ] **Step 1: Write the failing test**

```elixir
test "at the defaults it translates the unit square" do
  values = Param.values(Exhibit.params(), :default)
  frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
  assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

  assert Enum.any?(
           ops,
           &match?({:polygon, [{1.0, 0.0}, {2.0, 0.0}, {2.0, 1.0}, {1.0, 1.0}], :stroke, _}, &1)
         )
  assert {"determinant", "1.0"} in rows
  assert {"flips", "false"} in rows
end
```

The default transform is `new(1.0, 0.0, 1.0, 0.0, 1.0, 0.0)`, which maps
`(x, y)` to `(x + 1, y)`.

- [ ] **Step 2: Run it to see it fail**

Run: `mix test test/girihelix_web/workbench/exhibits/transform_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement and register**

- [ ] **Step 4: Run the exhibit and registry tests**

Expected: PASS.

- [ ] **Step 5: Commit**

Commit message: `feat: add the Transform workbench exhibit`.

### Task 7: The Intersect exhibit

**Files:**

- Create: `lib/girihelix_web/workbench/exhibits/intersect.ex`
- Modify: `lib/girihelix_web/workbench/registry.ex`
- Create: `test/girihelix_web/workbench/exhibits/intersect_test.exs`

**Interfaces:**

- Params: `x1, y1, x2, y2, x3, y3, x4, y4`, floats in `-5..5`, step `0.1`,
  defaults `0.0, 0.0, 4.0, 0.0, 1.0, -2.0, 1.0, 2.0`.
- `initial/1` is the params map. The single `:build` step calls
  `Segment.new!/2` for both segments (raising `ArgumentError` on coincident
  endpoints), then computes the parameter pair and the intersection, and
  returns a map `%{first: segment, second: segment, params: {s, t} | nil, intersection: Point.t() | nil, true_intersection: Point.t() | nil}`.
- `draw/2` is `{:both, ops, rows}`:
  - ops: both segments as lines, their endpoints as points, and the
    intersection as a larger point marker when present.
  - rows: `{"params", "{0.25, 0.5}"}`, `{"intersection", "1.0, 0.0"}`,
    `{"true intersection", "1.0, 0.0"}`.
- `reproduce/1` returns a fully qualified, pasteable snippet calling
  `Girihelix.Engine.Geometry.Segment.new` and
  `Girihelix.Engine.Geometry.Intersect.get_intersection`.

- [ ] **Step 1: Write the failing tests**

```elixir
test "at the defaults the segments cross at (1.0, 0.0)" do
  values = Param.values(Exhibit.params(), :default)
  frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
  assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

  assert Enum.any?(ops, &match?({:point, {1.0, 0.0}, _, _}, &1))
  assert {"params", "{0.25, 0.5}"} in rows
  assert {"intersection", "1.0, 0.0"} in rows
end

test "coincident endpoints are a failure state, not a crash" do
  values = Map.merge(Param.values(Exhibit.params(), :default), %{x2: 0.0, y2: 0.0})
  assert {:error, %Steps.Failure{step: %Steps.Step{id: :build}}} =
           Steps.run(Exhibit.steps(values), Exhibit.initial(values))
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix_web/workbench/exhibits/intersect_test.exs`
Expected: FAIL.

- [ ] **Step 3: Implement and register**

- [ ] **Step 4: Run the exhibit and registry tests**

Expected: PASS.

- [ ] **Step 5: Commit**

Commit message: `feat: add the Intersect workbench exhibit`.

### Task 8: The Polygon exhibit

**Files:**

- Create: `lib/girihelix_web/workbench/exhibits/polygon.ex`
- Modify: `lib/girihelix_web/workbench/registry.ex`
- Create: `test/girihelix_web/workbench/exhibits/polygon_test.exs`

**Interfaces:**

- Params: `shape` (enum `[:square, :triangle, :star]`, default `:square`),
  `probe_x` and `probe_y` (floats `-2..2`, step `0.1`, defaults `0.5`).
- Shapes: unit square `(0,0), (1,0), (1,1), (0,1)`; triangle
  `(0,0), (1,0), (0,1)`; a five-point star centred at `(0.5, 0.5)` with outer
  radius `0.5` and inner radius `0.2` (generate the ten points with
  `Point.new` and `:math.cos/sin`).
- `draw/2` is `{:both, ops, rows}`: the polygon as `{:polygon, points, :fill, [
  fill: "currentColor", opacity: 0.15]}`, its vertices as points, the probe as a
  point marker; rows `{"vertices", "4"}`, `{"area", "1.0"}`,
  `{"arc length", "4.0"}`, `{"contains probe", "true"}`.
- `reproduce/1` returns a fully qualified, pasteable snippet naming
  `Girihelix.Engine.Geometry.Polygon.new!`.

- [ ] **Step 1: Write the failing test**

```elixir
test "the default unit square reports its measures" do
  values = Param.values(Exhibit.params(), :default)
  frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
  assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

  assert Enum.any?(
           ops,
           &match?({:polygon, [{0.0, 0.0}, {1.0, 0.0}, {1.0, 1.0}, {0.0, 1.0}], :fill, _}, &1)
         )
  assert {"vertices", "4"} in rows
  assert {"area", "1.0"} in rows
  assert {"arc length", "4.0"} in rows
  assert {"contains probe", "true"} in rows
end
```

- [ ] **Step 2: Run it to see it fail**

Expected: FAIL.

- [ ] **Step 3: Implement and register**

- [ ] **Step 4: Run the exhibit and registry tests**

Expected: PASS.

- [ ] **Step 5: Commit**

Commit message: `feat: add the Polygon workbench exhibit`.

### Task 9: The PlanarMap exhibit

**Files:**

- Create: `lib/girihelix_web/workbench/exhibits/planar_map.ex`
- Modify: `lib/girihelix_web/workbench/registry.ex`
- Create: `test/girihelix_web/workbench/exhibits/planar_map_test.exs`

**Interfaces:**

- Params: `scenario` (enum `[:weld_squares, :replicate_ladder]`, default
  `:weld_squares`).
- A public `scenario(name) :: {PlanarMap.t(), PlanarMap.t() | nil}` builds the
  pair:
  - `:weld_squares` — receiver unit square `(0,0)…(1,1)`, other unit square
    offset by `(0.5, 0.5)`.
  - `:replicate_ladder` — an empty receiver, and a three-vertex spoke
    `(0,0), (1,0), (1.5,0.3)`; no other map.
- `initial/1`:
  - `:weld_squares` → `PlanarMap.weld_start(receiver, other)`.
  - `:replicate_ladder` → `PlanarMap.replicate_start(receiver)`.
- `steps/1`:
  - `:weld_squares` → `PlanarMap.weld_steps()`.
  - `:replicate_ladder` → `PlanarMap.replicate_steps(unit, rotations)`, with
    six rotations at multiples of `pi/3`.
- `viewport/1` is pinned: `Viewport.fit({-2.0, -2.0, 2.0, 2.0}, padding: 0.0)`.
- `draw/2` is `{:both, ops, rows}`:
  - ops: the receiver's edges as lines and its vertices as points; the other
    map's edges as guides when present; crossings as point markers.
  - rows: `{"receiver vertices", …}`, `{"receiver edges", …}`,
    `{"crossings", …}`, `{"verify", "ok" | "…"}`.
- `reproduce/1` returns
  `"GirihelixWeb.Workbench.Exhibits.PlanarMap.scenario(:weld_squares)"`.

- [ ] **Step 1: Write the failing tests**

```elixir
test "the default weld scenario shows both maps and its crossing count" do
  values = Param.values(Exhibit.params(), :default)
  frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
  assert {:ok, _} = Map.fetch(List.last(frames).state, :receiver)

  assert {:both, ops, rows} = Exhibit.draw(hd(frames), values)
  assert ops != []
  assert {"receiver vertices", "4"} in rows
end

test "the replicate scenario reaches six spokes" do
  values = %{Param.values(Exhibit.params(), :default) | scenario: :replicate_ladder}
  frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
  assert {:both, _ops, rows} = Exhibit.draw(List.last(frames), values)
  assert {"receiver edges", "12"} in rows
end
```

- [ ] **Step 2: Run them to see them fail**

Expected: FAIL.

- [ ] **Step 3: Implement and register**

`draw/2` reads `frame.state` and must work at frame zero and on intermediate
states.

- [ ] **Step 4: Run the exhibit and registry tests**

Expected: PASS.

- [ ] **Step 5: Commit**

Commit message: `feat: add the PlanarMap workbench exhibit`.

### Task 10: The Faces exhibit

**Files:**

- Create: `lib/girihelix_web/workbench/exhibits/faces.ex`
- Modify: `lib/girihelix_web/workbench/registry.ex`
- Create: `test/girihelix_web/workbench/exhibits/faces_test.exs`

**Interfaces:**

- Params: `scenario` (enum
  `[:split_parallel, :dangling, :figure_eight, :two_corner, :square_diagonal,
  :grid]`, default `:split_parallel`).
- A public `scenario(name) :: PlanarMap.t()` builds each map with
  `insert_vertex/2` and `insert_edge!/3`:
  - `:split_parallel` — two vertices joined twice, then the midpoint inserted.
  - `:dangling` — the triangle `(0,0), (2,0), (1,2)` plus a dangling edge from
    `(1,2)` to `(3,2)`.
  - `:figure_eight` — two unit-side squares meeting at `(0,0)`.
  - `:two_corner` — two vertices joined by two parallel edges.
  - `:square_diagonal` — the square `(0,0), (4,0), (4,3), (0,3)` plus its
    diagonal.
  - `:grid` — the 3×3 grid of the Plan 1c golden.
- `initial/1` is `Faces.start(scenario)`; `steps/1` is `Faces.steps()`.
- `draw/2` is `{:both, ops, rows}`:
  - ops: the map's edges as lines; each kept face with state `:black` or
    `:white` as a `{:polygon, points, :fill, [fill: colour, opacity: 0.25]}`
    op, where the colour is `"black"` or `"white"`; every discovered face's
    vertices as points.
  - rows: `{"discovered", …}`, `{"kept", …}`, `{"black", …}`, `{"white", …}`,
    `{"failure", "none" | "filling_conflict" | "no_faces"}`.
- `reproduce/1` returns
  `"Girihelix.Engine.Faces.extract_faces(GirihelixWeb.Workbench.Exhibits.Faces.scenario(:split_parallel))"`.

- [ ] **Step 1: Write the failing tests**

```elixir
test "the default scenario colours two faces" do
  values = Param.values(Exhibit.params(), :default)
  frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
  assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

  assert Enum.any?(ops, &match?({:polygon, _, :fill, [{:fill, "black"} | _]}, &1))
  assert Enum.any?(ops, &match?({:polygon, _, :fill, [{:fill, "white"} | _]}, &1))
  assert {"black", "1"} in rows
  assert {"white", "1"} in rows
end

test "the square with a diagonal reports the filling conflict in the panel" do
  values = %{Param.values(Exhibit.params(), :default) | scenario: :square_diagonal}
  {:ok, frames} = Steps.run(Exhibit.steps(values), Exhibit.initial(values))
  assert {:both, _ops, rows} = Exhibit.draw(List.last(frames), values)
  assert {"failure", "filling_conflict"} in rows
end
```

- [ ] **Step 2: Run them to see them fail**

Expected: FAIL.

- [ ] **Step 3: Implement and register**

`draw/2` reads `frame.state` (`map`, `infos`, `order`, `failure`) and must work
before colouring and on a failed state.

- [ ] **Step 4: Run the exhibit and registry tests**

Expected: PASS.

- [ ] **Step 5: Commit**

Commit message: `feat: add the Faces workbench exhibit`.

### Task 11: The FillRegion exhibit

**Files:**

- Create: `lib/girihelix_web/workbench/exhibits/fill_region.ex`
- Modify: `lib/girihelix_web/workbench/registry.ex`
- Create: `test/girihelix_web/workbench/exhibits/fill_region_test.exs`

**Interfaces:**

- Params: `width`, `height` (floats `1..10`, step `0.5`, defaults `4.0`
  and `3.0`); `t1x`, `t1y`, `t2x`, `t2y` (floats `-2..2`, step `0.1`,
  defaults `1.0, 0.0, 0.0, 1.0`).
- The region is `(0,0), (width,0), (width,height), (0,height)`.
- `initial/1` is `FillRegion.start(region, t1, t2)`; `steps/1` is
  `FillRegion.steps()`.
- `draw/2` is `{:both, ops, rows}`:
  - ops: the region as a polygon stroke; the two translation vectors from the
    origin as guides; each `{row_offset, {xmin, xmax}}` in `state.rows` as a
    horizontal guide at `y = iymin + offset`; when the frame's step id is
    `:scan_rows` and the state has no failure, each emitted cell as
    `{:polygon, corners, :fill, [fill: "currentColor", opacity: 0.15]}`, where
    `origin = t1 * T1 + t2 * T2` and the corners are `origin`, `origin + T1`,
    `origin + T1 + T2`, `origin + T2`.
  - rows: `{"rows", …}`, `{"cells", …}`, `{"failure", "none" | …"}`.
- `reproduce/1` returns a fully qualified snippet calling
  `Girihelix.Engine.FillRegion.fill` with the four region corners and the two
  vectors.

- [ ] **Step 1: Write the failing tests**

```elixir
test "the default unit basis fills twenty cells" do
  values = Param.values(Exhibit.params(), :default)
  frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
  assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

  cells = Enum.filter(ops, &match?({:polygon, _, :fill, _}, &1))
  assert length(cells) == 20
  assert {"cells", "20"} in rows
end

test "an intermediate frame draws only the region and its rows" do
  values = Param.values(Exhibit.params(), :default)
  {:ok, frames} = Steps.run(Exhibit.steps(values), Exhibit.initial(values))
  assert {:both, ops, rows} = Exhibit.draw(Enum.at(frames, 1), values)
  assert Enum.any?(ops, &match?({:polygon, _, :stroke, _}, &1))
  assert {"cells", "0"} in rows
end
```

- [ ] **Step 2: Run them to see them fail**

Expected: FAIL.

- [ ] **Step 3: Implement and register**

- [ ] **Step 4: Run the exhibit and registry tests**

Expected: PASS.

- [ ] **Step 5: Commit**

Commit message: `feat: add the FillRegion workbench exhibit`.

### Task 12: The Canvas and Transport components

**Files:**

- Create: `lib/girihelix_web/workbench/components/canvas.ex`
- Create: `lib/girihelix_web/workbench/components/transport.ex`
- Create: `test/girihelix_web/workbench/components/canvas_test.exs`
- Create: `test/girihelix_web/workbench/components/transport_test.exs`

**Interfaces:**

- `GirihelixWeb.Workbench.Components.Canvas.canvas/1`
  - attrs: `:drawing` (required), `:viewport` (required), `:aspect` (float,
    default `0.75`).
  - `{:canvas, ops}` → the SVG from `Svg.render(ops, viewport, aspect: aspect,
    class: "w-full h-auto")` inside a wrapper with `id="canvas"`.
  - `{:panel, rows}` → a two-column table with `id="panel"`.
  - `{:both, ops, rows}` → both, side by side.
- `GirihelixWeb.Workbench.Components.Transport.transport/1`
  - attrs: `:index` (integer), `:count` (integer), `:step` (a `%Step{}` or nil),
    `:failure` (a `%Failure{}` or nil).
  - Buttons with `phx-click="go"` and `phx-value-to` of `"first"`, `"prev"`,
    `"next"`, `"last"`; a `type="range"` input named `"frame"` with
    `phx-change="go"`, `min="0"`, `max={count - 1}`, `value={index}`.
  - The current step's label and doc, or "Parameters" for frame zero.
  - When `failure` is set, a banner beginning `Step failed:` with the failing
    step's label and the exception message.

The component tests use `ExUnit.Case, async: true` and import
`Phoenix.LiveViewTest` for `render_component/2`.

- [ ] **Step 1: Write the failing component tests**

```elixir
test "canvas renders an SVG for a canvas drawing" do
  vp = %Viewport{left: 0.0, top: 1.0, width: 2.0, scale: 1.0}

  html =
    render_component(&Canvas.canvas/1,
      drawing: {:canvas, [{:line, {0.0, 0.0}, {1.0, 1.0}, []}]},
      viewport: vp
    )

  assert html =~ ~s(id="canvas")
  assert html =~ "<svg"

  # An empty drawing still renders a root rather than raising.
  html = render_component(&Canvas.canvas/1, drawing: {:canvas, []}, viewport: nil)
  assert html =~ "<svg"
end

test "canvas renders a panel and a both drawing" do
  html = render_component(&Canvas.canvas/1, drawing: {:panel, [{"a", "1"}]}, viewport: nil)
  assert html =~ "a"
  assert html =~ "1"

  html =
    render_component(&Canvas.canvas/1,
      drawing: {:both, [{:point, {0.0, 0.0}, 1.0, []}], [{"b", "2"}]},
      viewport: %Viewport{left: 0.0, top: 0.0, width: 1.0, scale: 1.0}
    )

  assert html =~ "<svg"
  assert html =~ "b"
end

test "transport shows the controls and the current step" do
  step = %Steps.Step{id: :build, label: "build", doc: "Build it.", run: & &1, source: {"lib/x.ex", 1}}

  html = render_component(&Transport.transport/1, index: 1, count: 3, step: step, failure: nil)
  assert html =~ ~s(phx-value-to="next")
  assert html =~ "build"
  assert html =~ "Build it."
  assert html =~ ~s(max="2")
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix_web/workbench/components/`
Expected: FAIL, the modules are undefined. `render_component/2` comes from
`Phoenix.LiveViewTest`; import it in the test module.

- [ ] **Step 3: Implement the components**

- [ ] **Step 4: Run them to see them pass**

Expected: PASS.

- [ ] **Step 5: Commit**

Commit message: `feat: add the canvas and transport components`.

### Task 13: Controls, source pane and reproduce pane

**Files:**

- Create: `lib/girihelix_web/workbench/components/controls.ex`
- Create: `lib/girihelix_web/workbench/components/source_pane.ex`
- Create: `lib/girihelix_web/workbench/components/reproduce_pane.ex`
- Modify: `assets/js/app.js`
- Create: `test/girihelix_web/workbench/components/controls_test.exs`
- Create: `test/girihelix_web/workbench/components/source_pane_test.exs`
- Create: `test/girihelix_web/workbench/components/reproduce_pane_test.exs`

**Interfaces:**

- `Controls.controls/1`
  - attrs: `:params` (`[Param.t()]`), `:values` (map).
  - A `<form phx-change="params" phx-debounce="200">` with one control per
    param, named by the param's name:
    - integer/float: `<input type="range" name={name} min={range.first}
      max={range.last} step={step} value={value}>` and a `<span>` with the
      value. A plain input is used because `CoreComponents.input/1` does not
      accept `type="range"`.
    - boolean: `<.input type="select" options={[{"true", "true"}, {"false",
      "false"}]}>`.
    - enum: `<.input type="select" options={Enum.map(options, &{to_string(&1),
      to_string(&1)})}>`.
- `SourcePane.source_pane/1`
  - attrs: `:source` (`{:ok, map}` or `{:error, :no_step | :unavailable}`).
  - `{:ok, %{path, first, last, context_first, context_last, lines}}` renders
    the context lines with line numbers; lines in `first..last` carry
    `class="bg-warning/30"`; a header shows `path:first`.
  - `{:error, :no_step}` says "Parameters, before any step."
  - `{:error, :unavailable}` says "Source unavailable."
- `ReproducePane.reproduce_pane/1`
  - attrs: `:snippet` (string), `:index` (integer).
  - renders the snippet in a `<pre id="reproduce">`, the text "frame {index}",
    and a `<button data-copy={snippet} phx-click={JS.dispatch("phx:copy")}>`.
- `app.js` gains:
  `window.addEventListener("phx:copy", e => { if (e.target.dataset.copy) navigator.clipboard.writeText(e.target.dataset.copy) })`.

- [ ] **Step 1: Write the failing tests**

```elixir
test "controls render a range per number and a select per enum" do
  params = [
    %Param{name: :n, type: :integer, range: 3..24, step: 1, default: 8, doc: "order"},
    %Param{name: :shape, type: :enum, options: [:square, :triangle], default: :square, doc: "shape"}
  ]

  html = render_component(&Controls.controls/1, params: params, values: %{n: 8, shape: :square})
  assert html =~ ~s(type="range")
  assert html =~ ~s(name="n")
  assert html =~ ~s(min="3")
  assert html =~ ~s(phx-change="params")
  assert html =~ ~s(name="shape")
end

test "the source pane marks the active range and handles both errors" do
  source =
    {:ok,
     %{path: "lib/x.ex", first: 2, last: 3, context_first: 1, context_last: 4,
       lines: [{1, "one"}, {2, "two"}, {3, "three"}, {4, "four"}]}}

  html = render_component(&SourcePane.source_pane/1, source: source)
  assert html =~ "lib/x.ex:2"
  assert html =~ "three"
  assert html =~ "bg-warning/30"

  assert render_component(&SourcePane.source_pane/1, source: {:error, :no_step}) =~
           "Parameters, before any step"

  assert render_component(&SourcePane.source_pane/1, source: {:error, :unavailable}) =~
           "Source unavailable"
end

test "the reproduce pane shows the snippet and a copy button" do
  html = render_component(&ReproducePane.reproduce_pane/1, snippet: "Point.new(1.0, 2.0)", index: 3)
  assert html =~ "Point.new(1.0, 2.0)"
  assert html =~ "frame 3"
  # The snippet contains `)`, so the sigil uses `|` delimiters.
  assert html =~ ~s|data-copy="Point.new(1.0, 2.0)"|
end
```

- [ ] **Step 2: Run them to see them fail**

Expected: FAIL.

- [ ] **Step 3: Implement the components and the app.js listener**

- [ ] **Step 4: Run the tests and the asset build**

Run: `mix test test/girihelix_web/workbench/components/`
Expected: PASS.

Run: `mix assets.build`
Expected: exit 0.

- [ ] **Step 5: Commit**

Commit message: `feat: add workbench controls, source and reproduce panes`.

### Task 14: The source resolver

**Files:**

- Create: `lib/girihelix_web/workbench/source.ex`
- Create: `test/girihelix_web/workbench/source_test.exs`

**Interfaces:**

- `GirihelixWeb.Workbench.Source.resolve(step :: Steps.Step.t() | nil) :: {:ok, source()} | {:error, :no_step | :unavailable}`
  - `@type source :: %{path: String.t(), first: pos_integer(), last: pos_integer(), context_first: pos_integer(), context_last: pos_integer(), lines: [{pos_integer(), String.t()}]}`
  - `nil` → `{:error, :no_step}`.
  - A path not starting with `"lib/"` → `{:error, :unavailable}`.
  - A read failure → `{:error, :unavailable}`.
  - `first` is the captured line; `last` is found by counting parentheses
    from `first` until the balance returns to zero, ignoring `#` comments and
    `"` strings with backslash escapes, capped at 50 lines. If the balance
    never returns, `last = first`.
  - `context_first = max(1, first - 2)` and
    `context_last = min(line_count, last + 2)`; `lines` holds the whole file as
    `{number, text}`.

- [ ] **Step 1: Write the failing tests**

```elixir
test "an engine step resolves to its file and call range" do
  step = hd(Faces.steps())

  assert {:ok, source} = Source.resolve(step)
  assert source.path == "lib/girihelix/engine/faces.ex"
  assert source.first == elem(step.source, 1)

  text = source.lines |> Enum.map(&elem(&1, 1)) |> Enum.slice((source.first - 1)..(source.last - 1))
  assert Enum.join(text, "\n") =~ "discover faces"
end

test "a multi-line step call resolves past its first line" do
  step = hd(PlanarMap.weld_steps())
  assert {:ok, source} = Source.resolve(step)
  assert source.last > source.first
end

test "nil, a missing file and a path outside lib are errors" do
  assert Source.resolve(nil) == {:error, :no_step}

  outside = %Steps.Step{id: :x, label: "x", doc: "x", run: & &1, source: {"reference/1.1.12/x.java", 1}}
  assert Source.resolve(outside) == {:error, :unavailable}

  missing = %Steps.Step{id: :x, label: "x", doc: "x", run: & &1, source: {"lib/nope.ex", 1}}
  assert Source.resolve(missing) == {:error, :unavailable}
end
```

- [ ] **Step 2: Run them to see them fail**

Expected: FAIL.

- [ ] **Step 3: Implement `Source`**

Read the file with `File.read/1`; walk the lines with a small reducer that
tracks the parenthesis balance and whether it is inside a string or a comment.

- [ ] **Step 4: Run them to see them pass**

Expected: PASS.

- [ ] **Step 5: Commit**

Commit message: `feat: resolve a step's source range`.

### Task 15: The LiveViews, the router and the 404

**Files:**

- Create: `lib/girihelix_web/workbench/index_live.ex`
- Create: `lib/girihelix_web/workbench/exhibit_live.ex`
- Create: `lib/girihelix_web/workbench/not_found.ex`
- Modify: `lib/girihelix_web/router.ex`
- Create: `test/girihelix_web/workbench/index_live_test.exs`
- Create: `test/girihelix_web/workbench/exhibit_live_test.exs`

**Interfaces:**

- Routes:

  ```elixir
  live "/workbench", Workbench.IndexLive
  live "/workbench/:slug", Workbench.ExhibitLive
  ```

- `GirihelixWeb.Workbench.NotFound` is an exception whose `Plug.Exception`
  status is `404`.
- `IndexLive` assigns `groups: Registry.grouped()` and renders each category
  with links to `~p"/workbench/#{exhibit.slug()}"`, its title and summary.
- `ExhibitLive.handle_params/3`:
  - `Registry.get(slug)` or raise `NotFound`.
  - `values = Param.decode(params, url_params)`.
  - `run = Steps.run(exhibit.steps(values), exhibit.initial(values), max_frames: 200)`.
  - `count` is the frame count; a failure's frames are its `frames`.
  - The index is `url_params["frame"]` when present and parseable, clamped to
    `0..count - 1`; otherwise `count - 1`. With a failure and no frames, there is
    no index.
  - `drawing` is `exhibit.draw(frame, values)` for the current frame, or `nil`.
  - The viewport is the exhibit's pinned viewport when it exports
    `viewport/1` and returns a `%Viewport{}`, otherwise
    `Viewport.fit(Bounds.of_ops(ops))` from the drawing's canvas ops. A panel
    drawing has no ops, so it gets `Viewport.fit(nil)`; the canvas ignores it.
  - `source` is `Source.resolve(step)`, where `step` is the current frame's
    step, or the failure's step when there is no current frame.
  - Assigned: `:exhibit, :values, :param_defs, :index, :count, :step, :failure,
    :drawing, :viewport, :source, :snippet, :page_title`.
- Events:
  - `handle_event("go", %{"to" => to}, socket)` with `"first"`, `"prev"`,
    `"next"`, `"last"`; `handle_event("go", %{"frame" => frame}, socket)` for
    the scrub slider. Both clamp and `push_patch`.
  - `handle_event("params", params, socket)` decodes the form values and
    `push_patch`es without a `frame` key, so the last frame is shown.
  - The patch query is `Param.encode/2` plus `frame` when an index is known.

Both test modules use `GirihelixWeb.ConnCase, async: true` and
`import Phoenix.LiveViewTest`.

- [ ] **Step 1: Write the failing index test**

```elixir
test "the index lists every exhibit", %{conn: conn} do
  {:ok, view, html} = live(conn, "/workbench")

  assert html =~ "Workbench"
  assert html =~ "loose"
  assert html =~ ~p"/workbench/faces"
  assert render(view) =~ "Geometry"
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `mix test test/girihelix_web/workbench/index_live_test.exs`
Expected: FAIL, no route.

- [ ] **Step 3: Write the failing exhibit tests**

```elixir
test "an exhibit mounts with all four panes", %{conn: conn} do
  {:ok, _view, html} = live(conn, "/workbench/point")

  assert html =~ "<svg"
  assert html =~ "Point"
  assert html =~ ~s(id="panel")
  assert html =~ ~s(id="reproduce")
  assert html =~ "Girihelix.Engine.Geometry.Point.new(3.0, 4.0)"
end

test "the default frame is the last one, and the transport moves through it", %{conn: conn} do
  {:ok, view, html} = live(conn, "/workbench/faces")
  assert html =~ "collect colours"

  html = render_click(view, "go", %{"to" => "first"})
  assert html =~ "Parameters"

  html = render_click(view, "go", %{"to" => "next"})
  assert html =~ "discover faces"

  html = render_click(view, "go", %{"to" => "last"})
  assert html =~ "collect colours"
end

test "the URL clamps a parameter and carries the frame", %{conn: conn} do
  {:ok, _view, html} = live(conn, "/workbench/point?x=99.0&y=4.0")
  assert html =~ ~s(value="5.0")

  {:ok, view, _html} = live(conn, "/workbench/faces?frame=3")
  assert render(view) =~ "collect colours"
end

test "a parameter change resets to the last frame", %{conn: conn} do
  {:ok, view, _html} = live(conn, "/workbench/point")

  html = render_change(view, "params", %{"x" => "2.0", "y" => "4.0"})
  assert html =~ "Girihelix.Engine.Geometry.Point.new(2.0, 4.0)"
end

test "a raising step renders the failure", %{conn: conn} do
  {:ok, _view, html} =
    live(conn, "/workbench/intersect?x1=0.0&y1=0.0&x2=0.0&y2=0.0")

  assert html =~ "failed"
  assert html =~ "build"
end

test "an unknown slug is a 404", %{conn: conn} do
  assert_raise GirihelixWeb.Workbench.NotFound, fn -> live(conn, "/workbench/nope") end
end
```

- [ ] **Step 4: Run them to see them fail**

Run: `mix test test/girihelix_web/workbench/exhibit_live_test.exs`
Expected: FAIL, no route.

- [ ] **Step 5: Implement the LiveViews, the exception and the routes**

Use `use GirihelixWeb, :live_view`. Render `<Layouts.app flash={@flash}>` with
the panes. The transport and controls send the events above.

- [ ] **Step 6: Run the tests to see them pass**

Run: `mix test test/girihelix_web/workbench/`
Expected: PASS.

- [ ] **Step 7: Commit**

Commit message: `feat: add the workbench index and exhibit LiveViews`.

### Task 16: Homogenisation pass

**Files:**

- `docs/superpowers/specs/2026-10-16-girihelix-workbench-design.md`
- `docs/algorithm-analysis.md` (only if a behavioural fact moved out of a
  module doc)
- `docs/backlog.md`
- the modules from this plan

- [ ] **Step 1: Record the implementation decisions in the design**

Add a "Plan 2 implementation decisions" section recording:

- the `initial/1` callback, because the Plan 1c algorithms already own their
  start states;
- draw-op coordinates as `{x, y}` tuples in map space;
- the source pane uses plain monospace with the active range marked, so
  `makeup` is not a dependency;
- the copy button dispatches `phx:copy` to a listener in `app.js`;
- the 200-frame cap and the "absence of `frame` means last" rule.

- [ ] **Step 2: Update the design status and the plan series**

Set the design's status to "Plan 2 implemented 2026-10-21; Plans 3–7 remain."
Mark the plan-series row 2 as done.

- [ ] **Step 3: Record deferred work in the backlog**

Add entries for:

- syntax highlighting in the source pane (makeup), deferred;
- per-exhibit pinned viewports beyond the PlanarMap exhibit, if any exhibit
  still jitters.

- [ ] **Step 4: Strip source narration from the new modules**

Run:

```bash
grep -rniE "java|taprats|ported|reference tree|source's|extractFace|handleVertex|getTwin" lib/girihelix/engine/render lib/girihelix_web/workbench
```

Restate each hit as a decision about the workbench, not a recital of another
system.

- [ ] **Step 5: Lint and run the gates**

Run:
`markdownlint-cli2 --config ~/.markdownlint-cli2.jsonc docs/superpowers/specs/2026-10-16-girihelix-workbench-design.md docs/backlog.md`
Expected: 0 issues.

Run: `mix precommit`
Expected: `Total errors: 0`, suite passes, coverage does not fall.

- [ ] **Step 6: Commit**

Commit message: `docs: record the Plan 2 workbench decisions`.

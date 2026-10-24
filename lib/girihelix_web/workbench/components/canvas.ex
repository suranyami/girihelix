defmodule GirihelixWeb.Workbench.Components.Canvas do
  @moduledoc """
  Draws one frame: the picture, the panel of numbers, or the picture half of a
  frame that has both.

  The picture is the engine's serialized SVG, placed verbatim inside a wrapper
  with `id="canvas"`; the panel is a two-column table with `id="panel"`. A
  `:both` drawing's panel is drawn by the public `panel/1`, not beside the
  picture: the exhibit page places it under the controls in its right column, so
  `canvas/1` renders only the picture for that drawing. A `:panel` drawing has
  no picture, so `canvas/1` draws the panel itself. The wrapper is a fixed id
  rather than a unique one because a page shows one exhibit at a time, and the
  transport and the source pane address the canvas by that name.

  **The picture is height-capped.** The SVG is `h-auto` with
  `max-h-[70vh]`, so a tall aspect cannot push the page past one screen; the
  viewBox preserves its proportions inside the shorter box.

  **A missing viewport is the empty view.** The brief's callers pass `nil` for a
  panel and for an empty canvas; the serializer still needs a viewport to build
  its root, so `nil` becomes `Viewport.fit(nil)` — the fixed square centred on
  the origin. Panels never reach the serializer, so their viewport is ignored.

  **Overflow is split.** The SVG root does not clip (`overflow-visible`), so a
  pinned viewport can be panned past and the drawing's fringe stays in the
  document; the wrapper clips (`overflow-hidden`), so the picture keeps the
  layout's own bounds.
  """

  use GirihelixWeb, :html

  alias Girihelix.Engine.Render.Svg
  alias Girihelix.Engine.Render.Viewport
  alias Phoenix.LiveView.Rendered

  @default_aspect 0.75
  # The SVG root must not clip: a pinned viewport shows less than the drawing
  # holds, and the fringe beyond it is what panning reveals. The wrapper keeps
  # the layout's own bounds and does clip.
  @svg_class "w-full h-auto max-h-[70vh] overflow-visible"

  attr :drawing, :any,
    required: true,
    doc: "The exhibit's drawing: `{:canvas, ops}`, `{:panel, rows}` or `{:both, ops, rows}`."

  attr :viewport, :any,
    required: true,
    doc: "The frame's viewport, or `nil` for the fixed empty view."

  attr :aspect, :float,
    default: @default_aspect,
    doc: "Height divided by width; pass the aspect the viewport was fitted with."

  @spec canvas(map()) :: Rendered.t()
  def canvas(%{drawing: {:canvas, ops}} = assigns) do
    assigns = assign(assigns, :ops, ops)

    ~H"""
    <.zoomable_canvas
      class="relative w-full overflow-hidden"
      ops={@ops}
      viewport={@viewport}
      aspect={@aspect}
    />
    """
  end

  def canvas(%{drawing: {:panel, rows}} = assigns) do
    assigns = assign(assigns, :rows, rows)

    ~H"""
    <.panel rows={@rows} />
    """
  end

  # A `:both` drawing's rows belong to `panel/1`; the page decides where that
  # sits, so the picture here is the same as a canvas-only drawing's.
  def canvas(%{drawing: {:both, ops, _rows}} = assigns) do
    assigns = assign(assigns, :ops, ops)

    ~H"""
    <.zoomable_canvas
      class="relative w-full overflow-hidden"
      ops={@ops}
      viewport={@viewport}
      aspect={@aspect}
    />
    """
  end

  attr :class, :string, required: true
  attr :ops, :list, required: true
  attr :viewport, :any, required: true
  attr :aspect, :float, required: true

  # The `CanvasZoom` hook transforms the inner wrapper and clips at the outer
  # one, so a pan past the pinned viewport reveals the SVG's fringe without
  # moving the page. The controls sit inside the hook element (their clicks are
  # wired by it) but outside the transformed content (so they never scale or
  # move).
  defp zoomable_canvas(assigns) do
    ~H"""
    <div id="canvas" phx-hook="CanvasZoom" class={@class}>
      <div data-zoom-content>
        <.svg_view ops={@ops} viewport={@viewport} aspect={@aspect} />
      </div>
      <div class="absolute top-2 right-2 flex gap-1">
        <button type="button" data-zoom="in" class="btn btn-xs btn-square" aria-label="Zoom in">
          +
        </button>
        <button type="button" data-zoom="out" class="btn btn-xs btn-square" aria-label="Zoom out">
          −
        </button>
        <button type="button" data-zoom="reset" class="btn btn-xs btn-square" aria-label="Reset zoom">
          ⟳
        </button>
      </div>
    </div>
    """
  end

  attr :ops, :list, required: true
  attr :viewport, :any, required: true
  attr :aspect, :float, required: true

  defp svg_view(assigns) do
    svg = render_svg(assigns.ops, assigns.viewport, assigns.aspect)
    assigns = assign(assigns, :svg, markup(svg))

    ~H"""
    {@svg}
    """
  end

  attr :rows, :list, required: true, doc: "The label/value rows of a `:both` or `:panel` drawing."

  @doc """
  The panel of numbers, as a two-column table.

  Public because a `:both` drawing's rows are placed by the page — under the
  controls rather than beside the picture.
  """
  @spec panel(map()) :: Rendered.t()
  def panel(assigns) do
    ~H"""
    <table id="panel" class="table table-sm w-auto">
      <tbody>
        <tr :for={{label, value} <- @rows}>
          <th scope="row">{label}</th>
          <td>{value}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  # The controller's ruling: a nil viewport is the empty view, never a nil
  # argument to the serializer.
  defp render_svg(ops, nil, aspect), do: render_svg(ops, Viewport.fit(nil), aspect)

  defp render_svg(ops, %Viewport{} = viewport, aspect), do: Svg.render(ops, viewport, aspect: aspect, class: @svg_class)

  # `Svg.render/3` is the only producer of this string. It escapes the label
  # text (`Svg.escape/1`) and the root class, and emits fixed element names,
  # numbers and attribute names otherwise. Op option values — `:fill`,
  # `:stroke`, `:dash` — are written into attributes without escaping, but every
  # value the workbench passes is an authored constant, never user input. The
  # string is therefore safe markup here, so it is tagged the way
  # `Phoenix.HTML.raw/1` tags its argument and interpolated as markup rather
  # than escaped a second time.
  defp markup(svg), do: {:safe, svg}
end

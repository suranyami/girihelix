defmodule GirihelixWeb.Workbench.Components.Canvas do
  @moduledoc """
  Draws one frame: the picture, the panel of numbers, or both side by side.

  The picture is the engine's serialized SVG, placed verbatim inside a wrapper
  with `id="canvas"`; the panel is a two-column table with `id="panel"`. A
  `:both` drawing renders both, with the same ids, in a responsive two-column
  grid. The wrapper is a fixed id rather than a unique one because a page shows
  one exhibit at a time, and the transport and the source pane address the
  canvas by that name.

  **A missing viewport is the empty view.** The brief's callers pass `nil` for a
  panel and for an empty canvas; the serializer still needs a viewport to build
  its root, so `nil` becomes `Viewport.fit(nil)` — the fixed square centred on
  the origin. Panels never reach the serializer, so their viewport is ignored.
  """

  use GirihelixWeb, :html

  alias Girihelix.Engine.Render.Svg
  alias Girihelix.Engine.Render.Viewport

  @default_aspect 0.75
  @svg_class "w-full h-auto"

  attr :drawing, :any,
    required: true,
    doc: "The exhibit's drawing: `{:canvas, ops}`, `{:panel, rows}` or `{:both, ops, rows}`."

  attr :viewport, :any,
    required: true,
    doc: "The frame's viewport, or `nil` for the fixed empty view."

  attr :aspect, :float,
    default: @default_aspect,
    doc: "Height divided by width; pass the aspect the viewport was fitted with."

  @spec canvas(map()) :: Phoenix.LiveView.Rendered.t()
  def canvas(%{drawing: {:canvas, ops}} = assigns) do
    assigns = assign(assigns, :ops, ops)

    ~H"""
    <div id="canvas" class="w-full">
      <.svg_view ops={@ops} viewport={@viewport} aspect={@aspect} />
    </div>
    """
  end

  def canvas(%{drawing: {:panel, rows}} = assigns) do
    assigns = assign(assigns, :rows, rows)

    ~H"""
    <.panel_view rows={@rows} />
    """
  end

  def canvas(%{drawing: {:both, ops, rows}} = assigns) do
    assigns = assign(assigns, ops: ops, rows: rows)

    ~H"""
    <div class="grid gap-6 md:grid-cols-2 md:items-start">
      <div id="canvas" class="w-full">
        <.svg_view ops={@ops} viewport={@viewport} aspect={@aspect} />
      </div>
      <.panel_view rows={@rows} />
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

  attr :rows, :list, required: true

  defp panel_view(assigns) do
    ~H"""
    <table id="panel" class="table table-sm">
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

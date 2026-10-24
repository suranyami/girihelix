defmodule Girihelix.Engine.Render.Styles.Plain do
  @moduledoc """
  The plain style: every edge as one line in the edge colour.

  It draws the map's skeleton and fills no faces. The width is fixed in SVG
  units, so a stroke keeps its weight as the viewport changes. The lines sit on
  the shared background, and the background's colour is the only role used
  beyond the edge's.
  """

  @behaviour Girihelix.Engine.Render.Style

  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Palette
  alias Girihelix.Engine.Render.Style

  @edge_width 1.5

  @impl true
  @spec paint(PlanarMap.t(), Palette.roles()) :: {:ok, Style.result()}
  def paint(map, %{edge: stroke} = roles) do
    ops =
      map
      |> PlanarMap.edges()
      |> Enum.map(&line(map, &1, stroke))

    {:ok, %{background: Style.background(ops, roles), ops: ops, faces: nil}}
  end

  defp line(map, edge, stroke) do
    {v1, v2} = PlanarMap.endpoints!(map, edge)

    {:line, position(map, v1), position(map, v2), [stroke: stroke, width: @edge_width]}
  end

  defp position(map, vertex), do: map |> PlanarMap.position!(vertex) |> Style.pair()
end

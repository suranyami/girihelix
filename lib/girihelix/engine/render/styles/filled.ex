defmodule Girihelix.Engine.Render.Styles.Filled do
  @moduledoc """
  The filled style: every two-coloured face as a fill, then the boundary.

  `Faces.extract_faces/1` colours the faces black or white so that neighbours
  differ. White faces are painted first in the lighter colour, then black faces
  in the darker one, and finally every map edge is stroked once in the edge
  colour. The fill and boundary op orders are the renderer's faithfulness
  contract, so they are kept exactly.

  The face count is the number of faces the colouring returned, white plus
  black. A map the colouring cannot two-colour, or one with no faces at all,
  returns that reason as an error tuple instead of a partial painting.
  """

  @behaviour Girihelix.Engine.Render.Style

  alias Girihelix.Engine.Faces
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Palette
  alias Girihelix.Engine.Render.Style

  @edge_width 1.0

  @impl true
  @spec paint(PlanarMap.t(), Palette.roles()) :: {:ok, Style.result()} | {:error, Style.reason()}
  def paint(map, roles) do
    map
    |> Faces.extract_faces()
    |> painted(map, roles)
  end

  defp painted({:ok, %{black: black, white: white}}, map, roles) do
    ops =
      polygons(white, roles.lighter) ++
        polygons(black, roles.darker) ++
        boundary(map, roles.edge)

    {:ok, %{background: nil, ops: ops, faces: length(black) + length(white)}}
  end

  defp painted({:error, reason}, _map, _roles), do: {:error, reason}

  defp polygons(faces, hex), do: Enum.map(faces, &polygon(&1, hex))

  defp polygon(face, hex) do
    {:polygon, Enum.map(face, &Style.pair/1), :fill, [fill: hex]}
  end

  defp boundary(map, stroke) do
    map
    |> PlanarMap.edges()
    |> Enum.map(&line(map, &1, stroke))
  end

  defp line(map, edge, stroke) do
    {v1, v2} = PlanarMap.endpoints!(map, edge)

    {:line, position(map, v1), position(map, v2), [stroke: stroke, width: @edge_width]}
  end

  defp position(map, vertex), do: map |> PlanarMap.position!(vertex) |> Style.pair()
end

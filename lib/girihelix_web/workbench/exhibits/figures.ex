defmodule GirihelixWeb.Workbench.Exhibits.Figures do
  @moduledoc """
  The drawing ops and panel rows the figure exhibits share.

  A figure exhibit draws two maps at once: the **whole figure**, replicated
  under the symmetry ladder, and the **unit** the ladder copies. Sharing one
  edge walker means every exhibit draws both the same way, in map edge order:
  `map_ops/1` strokes the whole figure and `unit_ops/1` overlays the unit
  heavier so the two read together.

  `vertex_ops/2` marks a map's vertices at the design's default radius. Its
  options style construction vertices instead: `radius: 3.0` and
  `opts: [opacity: 0.6]` mark a point that is not a final vertex.

  `rows_for/1` reports the counts and the verification verdict. A `nil` map is
  a frame before `:assemble`: there is nothing to count or verify yet, so its
  rows are honest placeholders rather than a zero that would read as a result.

  This is workbench code, not engine code: it uses `PlanarMap`'s public API and
  the draw ops, never the map's internals.
  """

  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Op
  alias GirihelixWeb.Workbench.Exhibits.Format

  @default_vertex_radius 4.0

  @doc "One line per map edge, in edge order."
  @spec map_ops(PlanarMap.t()) :: [Op.t()]
  def map_ops(map), do: edge_ops(map, [])

  @doc "The unit's edges as heavier lines over the whole figure."
  @spec unit_ops(PlanarMap.t()) :: [Op.t()]
  def unit_ops(map), do: edge_ops(map, width: 2.0)

  @doc """
  One marker per map vertex.

  Options:

    * `:radius` — the marker radius in SVG units; default `#{@default_vertex_radius}`.
    * `:opts` — the draw op's options; default `[]`.
  """
  @spec vertex_ops(PlanarMap.t(), keyword()) :: [Op.t()]
  def vertex_ops(map, opts \\ []) do
    radius = Keyword.get(opts, :radius, @default_vertex_radius)
    style = Keyword.get(opts, :opts, [])

    Enum.map(PlanarMap.vertices(map), fn vertex ->
      {:point, map |> PlanarMap.position!(vertex) |> Format.pair(), radius, style}
    end)
  end

  @doc """
  The shared `vertices`, `edges` and `verify` rows.

  `nil` is a frame that has not assembled a map yet.
  """
  @spec rows_for(PlanarMap.t() | nil) :: [{String.t(), String.t()}]
  def rows_for(nil), do: [{"vertices", "0"}, {"edges", "0"}, {"verify", "n/a"}]

  def rows_for(map) do
    [
      {"vertices", Integer.to_string(PlanarMap.num_vertices(map))},
      {"edges", Integer.to_string(PlanarMap.num_edges(map))},
      {"verify", verdict(PlanarMap.verify(map))}
    ]
  end

  defp edge_ops(map, opts) do
    Enum.map(PlanarMap.edges(map), fn edge ->
      {from, to} = PlanarMap.endpoints!(map, edge)

      {:line, map |> PlanarMap.position!(from) |> Format.pair(), map |> PlanarMap.position!(to) |> Format.pair(), opts}
    end)
  end

  defp verdict(:ok), do: "ok"
  defp verdict({:error, _problems}), do: "failed"
end

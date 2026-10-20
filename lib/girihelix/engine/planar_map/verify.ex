defmodule Girihelix.Engine.PlanarMap.Verify do
  @moduledoc """
  Finds the ways a `PlanarMap` can be malformed. A test aid: it reports every
  problem it finds and never raises.

  Problems are listed edges first, in edge order, then the sortedness checks:

  - `{:trivial_edge, edge}`: both ends are the same vertex.
  - `{:missing_endpoint, edge}`: an end is not a vertex of the map.
  - `{:not_in_ring, edge}`: an end's ring has no edge to the other end.
  - `{:parallel_edge, edge}`: an end's ring reaches the other end by a
    different edge. It is reported once for each end that finds it.
  - `{:edges_unsorted, index}`: the edge at `index` has a minimum `x` more than
    `1.0e-7` below its predecessor's.
  - `{:duplicate_vertices, index}` or `{:vertices_unsorted, index}`: the vertex
    at `index` compares equal to, or below, its predecessor.
  """

  alias Girihelix.Engine.Geometry.Loose
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.PlanarMap.Order

  @tol Loose.tol()

  @type problem ::
          {:trivial_edge | :missing_endpoint | :not_in_ring | :parallel_edge, PlanarMap.edge()}
          | {:edges_unsorted | :duplicate_vertices | :vertices_unsorted, non_neg_integer()}

  @doc "Every problem in the map, or `[]`."
  @spec problems(PlanarMap.t()) :: [problem()]
  def problems(map) do
    vertices = PlanarMap.vertices(map)
    known = MapSet.new(vertices)
    edges = PlanarMap.edges(map)

    Enum.flat_map(edges, &edge_problems(map, known, &1)) ++
      edge_order_problems(map, edges) ++ vertex_order_problems(map, vertices)
  end

  defp edge_problems(map, known, edge) do
    {v1, v2} = PlanarMap.endpoints!(map, edge)

    trivial(edge, v1, v2) ++ membership(map, known, edge, v1, v2)
  end

  defp trivial(edge, v, v), do: [{:trivial_edge, edge}]
  defp trivial(_edge, _v1, _v2), do: []

  defp membership(map, known, edge, v1, v2),
    do: present(map, edge, v1, v2, MapSet.member?(known, v1), MapSet.member?(known, v2))

  defp present(map, edge, v1, v2, true, true),
    do: ring_problem(PlanarMap.neighbour!(map, v1, v2), edge) ++ ring_problem(PlanarMap.neighbour!(map, v2, v1), edge)

  defp present(_map, edge, _v1, _v2, _first, _second), do: [{:missing_endpoint, edge}]

  defp ring_problem(nil, edge), do: [{:not_in_ring, edge}]
  defp ring_problem(edge, edge), do: []
  defp ring_problem(_other, edge), do: [{:parallel_edge, edge}]

  defp edge_order_problems(map, edges) do
    edges
    |> Enum.map(&min_x(map, &1))
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {[a, b], index} -> edge_pair(a, b, index) end)
  end

  defp edge_pair(a, b, index) when a > b + @tol, do: [{:edges_unsorted, index}]
  defp edge_pair(_a, _b, _index), do: []

  defp min_x(map, edge) do
    {v1, v2} = PlanarMap.endpoints!(map, edge)
    min(x_of(map, v1), x_of(map, v2))
  end

  defp x_of(map, vertex), do: map |> PlanarMap.position!(vertex) |> Map.fetch!(:x)

  defp vertex_order_problems(map, vertices) do
    vertices
    |> Enum.map(&PlanarMap.position!(map, &1))
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {[a, b], index} -> vertex_pair(Order.compare_points(a, b), index) end)
  end

  defp vertex_pair(:lt, _index), do: []
  defp vertex_pair(:eq, index), do: [{:duplicate_vertices, index}]
  defp vertex_pair(:gt, index), do: [{:vertices_unsorted, index}]
end

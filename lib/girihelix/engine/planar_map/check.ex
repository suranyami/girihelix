defmodule Girihelix.Engine.PlanarMap.Check do
  @moduledoc """
  Whether a new edge between two vertices of a `PlanarMap` would meet the map
  anywhere other than at its own two end vertices.

  An edge meets the map improperly when it:

  - joins a vertex to itself, or repeats an existing edge;
  - properly crosses an existing edge it shares no end with;
  - has an end lying on an existing edge, which is a T-junction or an overlap;
  - passes through another vertex of the map.

  Positions are compared with the geometry's `1.0e-7` tolerance.
  """

  alias Girihelix.Engine.Geometry.Intersect
  alias Girihelix.Engine.Geometry.Loose
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Segment
  alias Girihelix.Engine.PlanarMap

  @doc """
  True when an edge from `v1` to `v2` would meet the map other than at those two
  vertices. Both must be vertices of `map`.
  """
  @spec crosses?(PlanarMap.t(), PlanarMap.vertex(), PlanarMap.vertex()) :: boolean()
  def crosses?(_map, v, v), do: true

  def crosses?(map, v1, v2) do
    new = {v1, PlanarMap.position!(map, v1), v2, PlanarMap.position!(map, v2)}

    Enum.any?(PlanarMap.edges(map), &meets_edge?(map, new, &1)) or
      Enum.any?(PlanarMap.vertices(map), &on_new_segment?(map, new, &1))
  end

  defp meets_edge?(map, {v1, p1, v2, p2}, edge) do
    {a, b} = PlanarMap.endpoints!(map, edge)
    pa = PlanarMap.position!(map, a)
    pb = PlanarMap.position!(map, b)

    same_edge?({a, b}, {v1, v2}) or
      end_inside?(v1, p1, a, b, pa, pb) or
      end_inside?(v2, p2, a, b, pa, pb) or
      properly_crosses?([v1, v2], [a, b], {p1, p2}, {pa, pb})
  end

  defp same_edge?({a, b}, {a, b}), do: true
  defp same_edge?({a, b}, {b, a}), do: true
  defp same_edge?(_edge, _new), do: false

  defp end_inside?(vertex, _point, a, b, _pa, _pb) when vertex == a or vertex == b, do: false
  defp end_inside?(_vertex, point, _a, _b, pa, pb), do: on_segment?(point, pa, pb)

  defp on_new_segment?(_map, {v1, _p1, v2, _p2}, vertex) when vertex == v1 or vertex == v2, do: false

  defp on_new_segment?(map, {_v1, p1, _v2, p2}, vertex), do: on_segment?(PlanarMap.position!(map, vertex), p1, p2)

  defp on_segment?(point, from, to), do: Loose.zero(Point.dist_to_line(point, from, to))

  defp properly_crosses?(new_ends, old_ends, {p1, p2}, {pa, pb}),
    do: disjoint?(new_ends, old_ends) and intersects?(Segment.new(p1, p2), Segment.new(pa, pb))

  defp disjoint?(new_ends, old_ends), do: Enum.all?(new_ends, &(&1 not in old_ends))

  defp intersects?({:ok, new}, {:ok, old}), do: Intersect.get_intersection(new, old) != nil
  defp intersects?(_new, _old), do: false
end

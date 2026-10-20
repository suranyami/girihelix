defmodule Girihelix.Engine.PlanarMap.Split do
  @moduledoc """
  Deciding which edge, if any, a newly placed vertex lands on and so must split.

  Both functions take plain points. The map applies the split itself.
  """

  alias Girihelix.Engine.Geometry.Loose
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap.Order

  @doc """
  Whether `point` lies on the segment `a`-`b` and clear of both ends: within
  `1.0e-7` of the segment, and no nearer than `1.0e-7` to either end.
  """
  @spec splittable?(Point.t(), Point.t(), Point.t()) :: boolean()
  def splittable?(point, a, b) do
    Loose.zero(Point.dist_to_line(point, a, b)) and not Loose.zero(Point.dist(point, a)) and
      not Loose.zero(Point.dist(point, b))
  end

  @doc """
  The first edge `point` splits, or `nil`.

  The edges must be in the map's edge order, by minimum x. The walk stops at the
  first edge whose minimum x lies beyond `point`'s x, so it never sees the edges
  after that one.
  """
  @spec first_splittable([{edge, Point.t(), Point.t()}], Point.t()) :: edge | nil
        when edge: term()
  def first_splittable([], _point), do: nil

  def first_splittable([{_edge, a, b} = head | rest], %Point{x: x} = point),
    do: step(Order.compare_min_x(min(a.x, b.x), x), head, rest, point)

  defp step(:gt, _head, _rest, _point), do: nil

  defp step(_not_gt, {edge, a, b}, rest, point), do: found(splittable?(point, a, b), edge, rest, point)

  defp found(true, edge, _rest, _point), do: edge
  defp found(false, _edge, rest, point), do: first_splittable(rest, point)
end

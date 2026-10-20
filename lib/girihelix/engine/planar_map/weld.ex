defmodule Girihelix.Engine.PlanarMap.Weld do
  @moduledoc """
  The plain-data halves of welding one planar map into another: finding where
  their edges cross, and merging their two vertex orders into one.

  Both functions take lists of points and handles. The map applies the result
  itself.
  """

  alias Girihelix.Engine.Geometry.Intersect
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Segment
  alias Girihelix.Engine.PlanarMap.Order

  @type edge_ends :: {Point.t(), Point.t()}
  @type plan_entry(v) :: {:mine, v} | {:same, v, v} | {:yours, v}

  @doc """
  Every point where an `other` edge crosses a `receiver` edge, as a point on the
  `other` edge.

  Both lists must be in edge order, by minimum x. For each `other` edge the walk
  over `receiver` stops at the first edge whose minimum x lies beyond the
  `other` edge's maximum x. Two edges that only share an endpoint do not cross,
  and parallel or overlapping edges never do. A point reached by several pairs
  appears once per pair, in the order found.
  """
  @spec crossings([edge_ends()], [edge_ends()]) :: [Point.t()]
  def crossings(other, receiver), do: Enum.flat_map(other, &edge_crossings(&1, receiver))

  defp edge_crossings({ep, eq} = edge, receiver), do: walk(receiver, edge, max(ep.x, eq.x), [])

  defp walk([], _edge, _max_x, acc), do: Enum.reverse(acc)

  defp walk([{cp, cq} = head | rest], edge, max_x, acc),
    do: walk_step(Order.compare_min_x(min(cp.x, cq.x), max_x), head, rest, edge, max_x, acc)

  defp walk_step(:gt, _head, _rest, _edge, _max_x, acc), do: Enum.reverse(acc)

  defp walk_step(_not_gt, head, rest, edge, max_x, acc), do: walk(rest, edge, max_x, keep(crossing(edge, head), acc))

  defp crossing({ep, eq}, {cp, cq}) do
    with {:ok, mine} <- Segment.new(ep, eq),
         {:ok, theirs} <- Segment.new(cp, cq) do
      Intersect.get_true_intersection(mine, theirs)
    else
      {:error, :coincident_points} -> nil
    end
  end

  defp keep(nil, acc), do: acc
  defp keep(point, acc), do: [point | acc]

  @doc """
  The merged vertex order of two sorted `{handle, position}` lists, walked once
  each.

  When the heads compare equal within the `1.0e-7` window the receiver's vertex
  stands for both, `{:same, mine, yours}`, and both lists advance. Otherwise the
  lesser head goes next, as `{:mine, v}` or `{:yours, v}`. Each `yours` vertex
  is compared only against the receiver vertex the walk has reached, so a vertex
  within the window of one already passed is not unified with it.
  """
  @spec merge_plan([{v, Point.t()}], [{v, Point.t()}]) :: [plan_entry(v)] when v: term()
  def merge_plan(mine, yours), do: merge(mine, yours, [])

  defp merge([], [], acc), do: Enum.reverse(acc)
  defp merge([], [{y, _pos} | yours], acc), do: merge([], yours, [{:yours, y} | acc])
  defp merge([{m, _pos} | mine], [], acc), do: merge(mine, [], [{:mine, m} | acc])

  defp merge([{_m, mpos} | _] = mine, [{_y, ypos} | _] = yours, acc),
    do: merge_step(Order.compare_points(mpos, ypos), mine, yours, acc)

  defp merge_step(:lt, [{m, _pos} | mine], yours, acc), do: merge(mine, yours, [{:mine, m} | acc])

  defp merge_step(:eq, [{m, _mp} | mine], [{y, _yp} | yours], acc), do: merge(mine, yours, [{:same, m, y} | acc])

  defp merge_step(:gt, mine, [{y, _pos} | yours], acc), do: merge(mine, yours, [{:yours, y} | acc])
end

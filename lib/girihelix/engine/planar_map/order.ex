defmodule Girihelix.Engine.PlanarMap.Order do
  @moduledoc """
  The sort orders and sorted-insertion rules of the planar map's vertex and
  edge lists. Plain-data helpers: they know nothing of the map struct.

  Two comparisons treat a difference of less than `1.0e-7` as no difference, and
  the window is fixed, not relative. Vertices compare by `x` and then `y`, each
  inside its own window, so two points are the same when they are within
  `1.0e-7` on both axes: a square, not a circle. Edges compare by their
  minimum `x`.

  Because the window is fixed, neither comparison is transitive. With keys
  `0.0`, `6.0e-8` and `1.2e-7`, the first equals the second and the second
  equals the third, yet the first is less than the third. Sorted order and
  insertion points are therefore only as good as the order the elements arrived
  in, and this is reproduced, not repaired.

  Insertion goes before the first element the new one is less than, and so
  after any run it equals. A lookup returns the first element it equals, not
  the nearest.
  """

  alias Girihelix.Engine.Geometry.Loose
  alias Girihelix.Engine.Geometry.Point

  @tol Loose.tol()

  @type comparison :: :lt | :eq | :gt

  @doc """
  Orders two points by `x`, then by `y`, each within a `1.0e-7` window.
  """
  @spec compare_points(Point.t(), Point.t()) :: comparison()
  def compare_points(%Point{x: ax, y: ay}, %Point{x: bx, y: by}), do: compare_points_by(order(ax - bx), ay - by)

  @doc """
  Orders two edge keys, the edges' minimum `x`, within a `1.0e-7` window.
  """
  @spec compare_min_x(float(), float()) :: comparison()
  def compare_min_x(a, b), do: order(a - b)

  @doc """
  Walks the sorted `{handle, point}` entries for `point`.

  Returns `{:found, handle}` for the first entry that compares equal, or
  `{:insert_at, index}` for the index of the first entry it is less than, or the
  list's length when it is greater than all of them.
  """
  @spec find_or_insert([{term(), Point.t()}], Point.t()) ::
          {:found, term()} | {:insert_at, non_neg_integer()}
  def find_or_insert(sorted, point), do: find_or_insert(sorted, point, 0)

  defp find_or_insert([], _point, index), do: {:insert_at, index}

  defp find_or_insert([{handle, at} | rest], point, index),
    do: find_step(compare_points(point, at), handle, rest, point, index)

  defp find_step(:eq, handle, _rest, _point, _index), do: {:found, handle}
  defp find_step(:lt, _handle, _rest, _point, index), do: {:insert_at, index}
  defp find_step(:gt, _handle, rest, point, index), do: find_or_insert(rest, point, index + 1)

  @doc """
  The index at which `key` goes into the sorted `keys`: that of the first key it
  is less than, or the list's length.
  """
  @spec edge_insert_index([float()], float()) :: non_neg_integer()
  def edge_insert_index(keys, key), do: edge_insert_index(keys, key, 0)

  defp edge_insert_index([], _key, index), do: index

  defp edge_insert_index([head | rest], key, index), do: edge_step(compare_min_x(key, head), rest, key, index)

  defp edge_step(:lt, _rest, _key, index), do: index
  defp edge_step(_not_lt, rest, key, index), do: edge_insert_index(rest, key, index + 1)

  @doc """
  Sorts `list` by `key_fun` under `compare`, keeping equal elements in their
  original order.
  """
  @spec sort([a], (a -> key), (key, key -> comparison())) :: [a] when a: term(), key: term()
  def sort(list, key_fun, compare), do: Enum.sort(list, fn a, b -> compare.(key_fun.(a), key_fun.(b)) != :gt end)

  defp compare_points_by(:eq, dy), do: order(dy)
  defp compare_points_by(other, _dy), do: other

  defp order(diff) when abs(diff) < @tol, do: :eq
  defp order(diff) when diff < 0.0, do: :lt
  defp order(_diff), do: :gt
end

defmodule Girihelix.Engine.PlanarMap.Ring do
  @moduledoc """
  A vertex's neighbours in counter-clockwise order, as a list of
  `{edge, angle}` that starts at the ring's head. Plain-data helpers: they know
  nothing of the map struct.

  An angle is a monotone stand-in for the real one, on `[0, 1)`: `0.0` along
  `+x`, `0.25` along `+y`, `0.5` along `-x`, `0.75` along `-y`. Only its order
  means anything.

  Three behaviours are deliberate. The head is not fixed: removing an entry makes
  that entry's predecessor the head. An angle equal to an existing one goes
  straight after the first equal entry met, so the order among equal angles
  depends on where the walk starts. And a direction of zero length has the angle
  `0.5`, not an error.

  `before_and_after/2` on a ring of one or two entries names the same edge on
  both sides.
  """

  alias Girihelix.Engine.Geometry.Point

  @type edge :: term()
  @type t :: [{edge(), float()}]

  @doc """
  The stand-in angle of the direction `(x, y)`, on `[0, 1)`. It orders directions
  as the real angle would.
  """
  @spec pseudo_atan2(float(), float()) :: float()
  def pseudo_atan2(x, y) when x > 0.0 and y >= 0.0, do: y * 0.25
  def pseudo_atan2(x, y) when x > 0.0, do: 1.0 + y * 0.25
  def pseudo_atan2(_x, y) when y > 0.0, do: 0.25 * (2.0 - y)
  def pseudo_atan2(_x, y), do: 0.5 - y * 0.25

  @doc """
  The angle of the direction from `from` toward `to`, from its normalized vector.
  """
  @spec angle(Point.t(), Point.t()) :: float()
  def angle(from, to) do
    %Point{x: x, y: y} = to |> Point.subtract(from) |> Point.normalize()
    pseudo_atan2(x, y)
  end

  @doc """
  Inserts `{edge, angle}` straight after the first neighbour whose arc, to the
  next neighbour, contains the angle. An empty ring becomes the single entry.

  Raises `ArgumentError` when no arc contains the angle, which cannot happen for
  a finite angle.
  """
  @spec insert(t(), {edge(), float()}) :: t()
  def insert([], entry), do: [entry]

  def insert([{_edge, head} | tail] = ring, {_new_edge, angle} = entry) do
    nexts = Enum.map(tail, &elem(&1, 1)) ++ [head]
    pairs = Enum.zip(Enum.map(ring, &elem(&1, 1)), nexts)

    insert_after(
      Enum.find_index(pairs, fn {cur, next} -> here?(cur, next, angle) end),
      ring,
      entry
    )
  end

  defp insert_after(nil, _ring, _entry), do: raise(ArgumentError, "no slot found in the ring for the angle")

  defp insert_after(index, ring, entry), do: List.insert_at(ring, index + 1, entry)

  defp here?(cur, next, angle) when next > cur, do: cur <= angle and angle <= next
  defp here?(cur, next, angle), do: cur <= angle or angle <= next

  @doc """
  Removes `edge`, and makes its predecessor the head. A ring without the edge is
  returned unchanged.
  """
  @spec remove(t(), edge()) :: t()
  def remove(ring, edge), do: remove_at(ring, Enum.find_index(ring, &(elem(&1, 0) == edge)))

  defp remove_at(ring, nil), do: ring
  defp remove_at([_only], 0), do: []

  defp remove_at(ring, index) do
    rest = List.delete_at(ring, index)
    {before, from_head} = Enum.split(rest, predecessor_index(index, length(rest)))
    from_head ++ before
  end

  defp predecessor_index(0, count), do: count - 1
  defp predecessor_index(index, _count), do: index - 1

  @doc """
  Renames `old_edge` to `new_edge`, keeping its place and angle.
  """
  @spec swap(t(), edge(), edge()) :: t()
  def swap(ring, old_edge, new_edge) do
    Enum.map(ring, &swap_entry(&1, old_edge, new_edge))
  end

  defp swap_entry({old_edge, angle}, old_edge, new_edge), do: {new_edge, angle}
  defp swap_entry(entry, _old_edge, _new_edge), do: entry

  @doc """
  The edges either side of `edge`, as `{before, after}`, or `nil` when the ring
  does not hold it.
  """
  @spec before_and_after(t(), edge()) :: {edge(), edge()} | nil
  def before_and_after(ring, edge), do: neighbours(ring, Enum.find_index(ring, &(elem(&1, 0) == edge)))

  defp neighbours(_ring, nil), do: nil

  defp neighbours(ring, index) do
    count = length(ring)
    {edge_at(ring, Integer.mod(index - 1, count)), edge_at(ring, Integer.mod(index + 1, count))}
  end

  defp edge_at(ring, index), do: ring |> Enum.at(index) |> elem(0)

  @doc """
  The edges in ring order, from the head.
  """
  @spec edges(t()) :: [edge()]
  def edges(ring), do: Enum.map(ring, &elem(&1, 0))

  @doc """
  The ring with every angle replaced by `angle_fun.(edge)`, in the same order.
  """
  @spec reangle(t(), (edge() -> float())) :: t()
  def reangle(ring, angle_fun), do: Enum.map(ring, fn {edge, _old} -> {edge, angle_fun.(edge)} end)
end

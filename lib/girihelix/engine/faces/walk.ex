defmodule Girihelix.Engine.Faces.Walk do
  @moduledoc """
  The geometric decisions of face discovery: which way a walk turns at a
  vertex, when it abandons a face, and whether a face runs clockwise.

  The map is read only through `Girihelix.Engine.PlanarMap`'s public API, and a
  face is a list of vertex handles in traversal order.
  """

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap

  @doc """
  Walks the face lying on one side of `edge`, starting at `from`.

  At each vertex the walk takes the edge before the one it arrived on in the
  ring's counter-clockwise order, which is the rightmost turn and keeps the
  face on one side. It records each vertex once and stops at the first return
  to `from`, so a walk that meets `from` again part-way through yields a
  partial face.

  Entering a vertex with fewer than two neighbours abandons the whole walk and
  returns `nil`; such a vertex cannot lie on a closed face.
  """
  @spec walk(PlanarMap.t(), PlanarMap.vertex(), PlanarMap.edge()) ::
          [PlanarMap.vertex()] | nil
  def walk(map, from, edge), do: continue([from], map, from, from, edge)

  defp continue(acc, map, from, cur, edge) do
    entered = other_end(map, cur, edge)
    degree = map |> PlanarMap.ring!(entered) |> length()
    cross(acc, map, from, entered, edge, degree)
  end

  defp cross(_acc, _map, _from, _entered, _edge, degree) when degree < 2, do: nil

  defp cross(acc, map, from, entered, edge, _degree) do
    {before, _after} = PlanarMap.before_and_after!(map, entered, edge)
    returned(entered, before, acc, map, from)
  end

  defp returned(from, _before, acc, _map, from), do: Enum.reverse(acc)

  defp returned(entered, before, acc, map, from), do: continue([entered | acc], map, from, entered, before)

  defp other_end(map, vertex, edge) do
    case PlanarMap.endpoints!(map, edge) do
      {^vertex, other} -> other
      {other, ^vertex} -> other
    end
  end

  @doc """
  Whether `points`, the corners of a face in traversal order, run clockwise.

  The test finds the rightmost corner — the lowest index on a tie — and takes
  the cross product of the edge arriving there with the edge leaving. A
  negative product means clockwise.

  There is no tolerance. A two-corner face, or an apex whose edges are
  collinear, has a zero product and is reported not clockwise, so such a face
  is kept rather than discarded as an outer contour.
  """
  @spec clockwise?([Point.t()]) :: boolean()
  def clockwise?([_ | _] = points) do
    count = length(points)
    index = rightmost(points)
    apex = Enum.at(points, index)
    before = Enum.at(points, rem(index + count - 1, count))
    after_point = Enum.at(points, rem(index + 1, count))

    Point.cross(Point.subtract(apex, before), Point.subtract(after_point, apex)) < 0.0
  end

  defp rightmost([first | rest]), do: scan(rest, 1, first.x, 0)

  defp scan([], _index, _max_x, best), do: best

  defp scan([%Point{x: x} | rest], index, max_x, _best) when x > max_x, do: scan(rest, index + 1, x, index)

  defp scan([_point | rest], index, max_x, best), do: scan(rest, index + 1, max_x, best)
end

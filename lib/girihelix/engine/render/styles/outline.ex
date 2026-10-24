defmodule Girihelix.Engine.Render.Styles.Outline do
  @moduledoc """
  The outline style: every edge as a mitred ribbon in the edge colour.

  Each edge becomes one six-point polygon — the offset points and the vertex at
  each end — filled in the edge colour over the shared background. Where two
  edges meet, the ribbon's corner is mitred so the two offsets meet at a point;
  where the miter would be unbounded, the corner falls back to a perpendicular
  offset. The ribbon's half-width is fixed in map units, matching Taprats, and
  it fills no faces.
  """

  @behaviour Girihelix.Engine.Render.Style

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Palette
  alias Girihelix.Engine.Render.Style

  @width 0.05
  @miter_tolerance 1.0e-7

  @impl true
  @spec paint(PlanarMap.t(), Palette.roles()) :: {:ok, Style.result()}
  def paint(map, %{edge: hex} = roles) do
    ops = map |> PlanarMap.edges() |> Enum.map(&ribbon(map, &1, hex))

    {:ok, %{ops: Style.background(ops, roles), faces: nil}}
  end

  defp ribbon(map, edge, hex) do
    {v1, v2} = PlanarMap.endpoints!(map, edge)
    {below_to, above_to} = get_points(map, edge, v1, v2)
    {below_from, above_from} = get_points(map, edge, v2, v1)

    points =
      Enum.map(
        [
          below_to,
          PlanarMap.position!(map, v2),
          above_to,
          below_from,
          PlanarMap.position!(map, v1),
          above_from
        ],
        &Style.pair/1
      )

    {:polygon, points, :fill, [fill: hex]}
  end

  @doc """
  The `{below, above}` offset points at `to` for `edge`, approached from `from`.

  A dangling end is capped by a perpendicular offset. A degree-two end is
  mitred against its only neighbour, and a degree-three-or-more end is mitred
  against the neighbours on either side of `edge`. A miter that would be
  unbounded falls back to the perpendicular offset.
  """
  @spec get_points(PlanarMap.t(), PlanarMap.edge(), PlanarMap.vertex(), PlanarMap.vertex()) ::
          {Point.t(), Point.t()}
  def get_points(map, edge, from, to) do
    pfrom = PlanarMap.position!(map, from)
    pto = PlanarMap.position!(map, to)
    perp = pto |> Point.subtract(pfrom) |> Point.normalize() |> Point.perp()

    offset(map, edge, to, pfrom, pto, perp, length(PlanarMap.ring!(map, to)))
  end

  defp offset(_map, _edge, _to, _pfrom, pto, perp, 1), do: perpendicular(pto, perp)

  defp offset(map, edge, to, pfrom, pto, perp, 2), do: bend(map, edge, to, pfrom, pto, perp)

  defp offset(map, edge, to, pfrom, pto, perp, degree) when degree >= 3, do: crossing(map, edge, to, pfrom, pto, perp)

  defp bend(map, edge, to, pfrom, pto, perp) do
    {before, _after} = PlanarMap.before_and_after!(map, to, edge)

    pto
    |> join_point(pfrom, far_position(map, before, to), @width)
    |> bend_pair(pto, perp)
  end

  defp bend_pair(nil, pto, perp), do: perpendicular(pto, perp)

  defp bend_pair(join, pto, _perp) do
    {join, Point.subtract(Point.scale(pto, 2.0), join)}
  end

  defp crossing(map, edge, to, pfrom, pto, perp) do
    {before, following} = PlanarMap.before_and_after!(map, to, edge)

    below =
      mitered(
        join_point(pto, pfrom, far_position(map, following, to), @width),
        Point.subtract(pto, Point.scale(perp, @width))
      )

    above =
      mitered(
        join_point(pto, far_position(map, before, to), pfrom, @width),
        Point.add(pto, Point.scale(perp, @width))
      )

    {below, above}
  end

  defp mitered(nil, fallback), do: fallback
  defp mitered(join, _fallback), do: join

  defp perpendicular(pto, perp) do
    {Point.subtract(pto, Point.scale(perp, @width)), Point.add(pto, Point.scale(perp, @width))}
  end

  defp far_position(map, edge, vertex), do: PlanarMap.position!(map, far_end(map, edge, vertex))

  defp far_end(map, edge, vertex) do
    {v1, v2} = PlanarMap.endpoints!(map, edge)

    other({v1, v2}, vertex)
  end

  defp other({vertex, far}, vertex), do: far
  defp other({far, _not_vertex}, _vertex), do: far

  @doc """
  The mitered join of two edges meeting at `joint`, or `nil` where the miter is
  unbounded.

  `a` and `b` are points on the two edges. A `nil` result means the two
  directions are collinear, so the corner has no finite intersection and the
  caller must fall back to a perpendicular offset.
  """
  @spec join_point(Point.t(), Point.t(), Point.t(), number()) :: Point.t() | nil
  def join_point(joint, a, b, width) do
    joint
    |> Point.sweep(a, b)
    |> :math.sin()
    |> miter(joint, a, b, width)
  end

  defp miter(s, _joint, _a, _b, _width) when s < @miter_tolerance and s > -@miter_tolerance, do: nil

  defp miter(s, joint, a, b, width) do
    directions =
      Point.add(
        Point.normalize(Point.subtract(joint, a)),
        Point.normalize(Point.subtract(joint, b))
      )

    Point.subtract(joint, Point.scale(directions, width / s))
  end
end

defmodule Girihelix.Engine.Figures.RadialFigure do
  @moduledoc """
  A figure with rotational symmetry: a unit, a symmetry order, and the
  replication that turns one into the other.

  This is a behaviour, not a struct. `n` is a field on each figure, and `don`
  and `tr` are pure functions of `n`, so storing them would create a second
  source of truth. A figure answers `n/1` and `build_unit/1`; everything else
  here is derived from those two.

  **The ladder starts at `tr(n)`, not at the identity.** `ladder(n)` is
  `Tr, Tr^2, ..., Tr^n`, so the unit is never placed untransformed. That matters
  because a real figure's unit is a wedge, not the whole figure: placing it
  under the identity as well would draw it twice, leaving a doubled seam. The
  last copy carries the rounding of `n` compositions, as the source does.

  `map/1` replicates the unit once under each transform of the ladder into an
  empty map. `PlanarMap.replicate!/3` coalesces vertices within its `1.0e-7`
  window and does not split edges, which is the source's `mergeSimpleMany`
  behaviour.
  """

  alias Girihelix.Engine.Figures.Rosette
  alias Girihelix.Engine.Figures.ScaleFigure
  alias Girihelix.Engine.Figures.Star
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.Engine.PlanarMap

  # Only the radial figures defined today may appear here: a typespec naming an
  # undefined struct warns, and warnings are errors in this project. Task 6 adds
  # `ConnectFigure` when its struct exists.
  @type t :: %Star{} | %Rosette{} | %ScaleFigure{}

  @doc "The figure's basic unit, before the `n`-fold replication."
  @callback build_unit(t()) :: PlanarMap.t()

  @doc "The figure's symmetry order, at least three."
  @callback n(t()) :: pos_integer()

  @doc "The fraction of a full turn one symmetry step takes: `1.0 / n`."
  @spec don(pos_integer()) :: float()
  def don(n), do: 1.0 / n

  @doc "The generator rotation `Tr`: a full turn divided into `n`."
  @spec tr(pos_integer()) :: Transform.t()
  def tr(n), do: Transform.rotate(2.0 * :math.pi() * don(n))

  @doc """
  The point at `frac` of a counter-clockwise turn from `(1, 0)`.

  `frac` is not normalised: negative and greater-than-one values turn in the
  other direction or more than once, as the caller asked.
  """
  @spec arc(float()) :: Point.t()
  def arc(frac) do
    angle = frac * 2.0 * :math.pi()
    Point.new(:math.cos(angle), :math.sin(angle))
  end

  @doc "The mirror of `point` in the x axis."
  @spec mirror(Point.t()) :: Point.t()
  def mirror(%Point{x: x, y: y}), do: Point.new(x, -y)

  @doc """
  Assembles a mirror-symmetric chain from `tip` and the ordered `points`.

  The map starts empty. It inserts `tip` first, then for each point in order:
  the point, its x-axis mirror as a **fresh** vertex, the top edge from the
  previous top vertex, and the bottom edge from the previous bottom vertex,
  carrying both handles forward. The first step's two edges therefore leave the
  tip **top then bottom**, which fixes the ring head and hence every later
  neighbour scan.

  Returns `{map, top, bottom}` with the last vertices of the two chains.
  """
  @spec mirrored_chain(Point.t(), [Point.t()]) ::
          {PlanarMap.t(), PlanarMap.vertex(), PlanarMap.vertex()}
  def mirrored_chain(%Point{} = tip, points) when is_list(points) do
    {map, vertex} = PlanarMap.insert_vertex(PlanarMap.new(), tip)
    {map, top, bottom} = Enum.reduce(points, {map, vertex, vertex}, &insert_mirrored/2)
    {map, top, bottom}
  end

  defp insert_mirrored(point, {map, top_prev, bottom_prev}) do
    {map, top} = PlanarMap.insert_vertex(map, point)
    {map, bottom} = PlanarMap.insert_vertex(map, mirror(point))
    map = PlanarMap.insert_edge!(map, top_prev, top)
    map = PlanarMap.insert_edge!(map, bottom_prev, bottom)
    {map, top, bottom}
  end

  @doc """
  The regular `n`-gon's corners, counter-clockwise from `(1, 0)`.

  The first corner is exact: `arc(0.0)` is `(1.0, 0.0)` with no rounding.
  """
  @spec unit_ngon(pos_integer()) :: [Point.t()]
  def unit_ngon(n), do: Enum.map(0..(n - 1), &arc(&1 * don(n)))

  @doc """
  The source's replication transforms: `Tr, Tr^2, ..., Tr^n`.

  Built by composing from a starting `Tr` and prepending each value, so the
  first entry is `Tr` and the identity is never among them.
  """
  @spec ladder(pos_integer()) :: [Transform.t()]
  def ladder(n) do
    step = tr(n)
    ladder(step, step, n, [])
  end

  defp ladder(_step, _current, 0, acc), do: Enum.reverse(acc)

  defp ladder(step, current, remaining, acc) do
    ladder(step, Transform.compose(current, step), remaining - 1, [current | acc])
  end

  @doc """
  The whole figure: the implementing module's unit replicated under the ladder.
  """
  @spec map(t()) :: PlanarMap.t()
  def map(%module{} = figure) do
    PlanarMap.replicate!(PlanarMap.new(), module.build_unit(figure), ladder(module.n(figure)))
  end
end

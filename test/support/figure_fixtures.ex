defmodule Girihelix.Engine.FigureFixtures.Square do
  @moduledoc """
  A test-only, four-fold figure whose unit is the diamond
  `(1, 0), (0, 1), (-1, 0), (0, -1)` with four edges.

  Its purpose is to exercise the replication ladder: rotating the diamond by a
  quarter turn maps its four vertices onto one another exactly, so a correct
  ladder coalesces every copy onto the same four vertices. It declares only
  `RadialFigure`, which carries both callbacks; declaring `Figure` as well
  would repeat `build_unit/1` and the compiler refuses that. `Figure` still
  dispatches to it, because a radial figure answers the same two functions.
  """

  @behaviour Girihelix.Engine.Figures.RadialFigure

  alias Girihelix.Engine.Figures.RadialFigure
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap

  defstruct []

  @impl RadialFigure
  def build_unit(_figure) do
    points = [
      Point.new(1.0, 0.0),
      Point.new(0.0, 1.0),
      Point.new(-1.0, 0.0),
      Point.new(0.0, -1.0)
    ]

    {map, first, last} = Enum.reduce(points, {PlanarMap.new(), nil, nil}, &add_vertex/2)
    PlanarMap.insert_edge!(map, last, first)
  end

  @impl RadialFigure
  def n(_figure), do: 4

  defp add_vertex(point, {map, nil, nil}) do
    {map, vertex} = PlanarMap.insert_vertex(map, point)
    {map, vertex, vertex}
  end

  defp add_vertex(point, {map, first, previous}) do
    {map, vertex} = PlanarMap.insert_vertex(map, point)
    {PlanarMap.insert_edge!(map, previous, vertex), first, vertex}
  end
end

defmodule Girihelix.Engine.Figures.RadialFigureTest do
  @moduledoc """
  The derived state of a radial figure: its angular primitives, the unit ngon,
  and the replication ladder.
  """

  use ExUnit.Case, async: true

  alias Girihelix.Engine.Figures.RadialFigure
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Transform

  test "don, tr, arc and mirror are the source's primitives" do
    assert RadialFigure.don(8) == 0.125
    assert RadialFigure.tr(8) == Transform.rotate(2.0 * :math.pi() / 8.0)
    assert RadialFigure.arc(0.0) == Point.new(1.0, 0.0)

    # Trigonometry at the quarter turns leaves rounding noise, so compare the
    # axes with a tolerance rather than exact equality.
    assert %Point{x: x0, y: y0} = RadialFigure.arc(0.5)
    assert_in_delta x0, -1.0, 1.0e-15
    assert_in_delta y0, 0.0, 1.0e-15

    assert %Point{x: x1, y: y1} = RadialFigure.arc(-0.25)
    assert_in_delta x1, 0.0, 1.0e-15
    assert_in_delta y1, -1.0, 1.0e-15

    assert RadialFigure.mirror(Point.new(0.3, 0.2)) == Point.new(0.3, -0.2)
  end

  test "ladder/1 is Tr through Tr^n, starting at Tr" do
    ladder = RadialFigure.ladder(4)
    assert length(ladder) == 4
    assert hd(ladder) == Transform.rotate(2.0 * :math.pi() / 4.0)

    # The last entry is Tr composed with itself n times: identity only up to
    # rounding, which is why the ladder must not start at the identity.
    last = List.last(ladder)
    assert_in_delta last.a, 1.0, 1.0e-12
    assert last.a != 1.0 or last.b != 0.0
  end

  test "unit_ngon/1 is counter-clockwise from (1, 0)" do
    [p0, p1, p2, p3] = RadialFigure.unit_ngon(4)

    assert p0 == Point.new(1.0, 0.0)
    assert_in_delta p1.x, 0.0, 1.0e-15
    assert_in_delta p1.y, 1.0, 1.0e-15
    assert_in_delta p2.x, -1.0, 1.0e-15
    assert_in_delta p2.y, 0.0, 1.0e-15
    assert_in_delta p3.x, 0.0, 1.0e-15
    assert_in_delta p3.y, -1.0, 1.0e-15
  end
end

defmodule Girihelix.Engine.Geometry.RectTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Rect
  alias Girihelix.Engine.Geometry.Transform

  test "the y-down accessors" do
    r = Rect.new(1.0, 10.0, 4.0, 3.0)
    assert {Rect.left(r), Rect.right(r), Rect.top(r), Rect.bottom(r)} == {1.0, 5.0, 10.0, 7.0}
    assert Rect.from_corners(Point.new(1.0, 10.0), Point.new(5.0, 7.0)) == r
    assert {Rect.width(r), Rect.height(r)} == {4.0, 3.0}
    assert Rect.center(r) == Point.new(3.0, 8.5)
    assert Rect.from_point(Point.new(1.0, 10.0), 4.0, 3.0) == r
  end

  test "union/2 spans both rects" do
    u = Rect.union(Rect.new(0.0, 10.0, 10.0, 10.0), Rect.new(5.0, 20.0, 10.0, 10.0))
    assert u == Rect.new(0.0, 20.0, 15.0, 20.0)
  end

  test "intersection/2 of overlapping, touching and disjoint rects" do
    a = Rect.new(0.0, 10.0, 10.0, 10.0)

    assert Rect.intersection(a, Rect.new(5.0, 15.0, 10.0, 10.0)) ==
             {:ok, Rect.new(5.0, 10.0, 5.0, 5.0)}

    # touching along x = 10: a zero-width rect, not :disjoint
    assert {:ok, %Rect{width: +0.0}} = Rect.intersection(a, Rect.new(10.0, 10.0, 5.0, 10.0))

    assert Rect.intersection(a, Rect.new(20.0, 10.0, 5.0, 5.0)) == {:error, :disjoint}
  end

  test "central_scale/2 scales about the centre" do
    # centre (2.0, 9.0), 8x4, top-left (2.0 - 4.0, 9.0 + 2.0)
    assert Rect.central_scale(Rect.new(0.0, 10.0, 4.0, 2.0), 2.0) ==
             Rect.new(-2.0, 11.0, 8.0, 4.0)

    assert Rect.center(Rect.central_scale(Rect.new(0.0, 10.0, 4.0, 2.0), 2.0)) ==
             Point.new(2.0, 9.0)
  end

  test "center_inside/2 maps the inner centre onto the outer centre and fits inside" do
    inner = Rect.new(0.0, 2.0, 4.0, 2.0)
    outer = Rect.new(10.0, 30.0, 20.0, 20.0)
    t = Rect.center_inside(inner, outer)

    assert Transform.apply_to(t, Rect.center(inner)) == Rect.center(outer)

    # The inner rect becomes 20x10 centred in the outer one: the smaller scale
    # wins, so it fits in both axes. Corners stay in the y-down sense.
    assert Transform.apply_to(t, Point.new(0.0, 2.0)) == Point.new(10.0, 25.0)
    assert Transform.apply_to(t, Point.new(4.0, 0.0)) == Point.new(30.0, 15.0)
  end
end

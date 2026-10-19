defmodule Girihelix.Engine.Geometry.SegmentTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Segment

  test "new/2 builds a segment from two distinct points" do
    assert {:ok, segment} = Segment.new(Point.new(1.0, 2.0), Point.new(3.0, 4.0))
    assert Segment.from(segment) == Point.new(1.0, 2.0)
    assert Segment.to(segment) == Point.new(3.0, 4.0)
  end

  test "new/2 refuses two equal points" do
    assert Segment.new(Point.new(1.0, 2.0), Point.new(1.0, 2.0)) == {:error, :coincident_points}
  end

  # Review Focus 1: 0.0 and -0.0 are not `===`, so a strict-equality guard would
  # accept a segment of length zero.
  test "new/2 refuses points that differ only in the sign of zero" do
    assert Segment.new(Point.new(0.0, 0.0), Point.new(-0.0, 0.0)) == {:error, :coincident_points}
  end

  # Review Focus 2: the points are distinct, but their squared distance is 0.0,
  # which is the divisor every Segment consumer relies on being positive.
  test "new/2 refuses distinct points whose squared distance underflows" do
    assert Segment.new(Point.origin(), Point.new(1.0e-170, 0.0)) == {:error, :coincident_points}
  end

  test "new/2 accepts a short segment whose squared length is still positive" do
    assert {:ok, _segment} = Segment.new(Point.origin(), Point.new(1.0e-150, 0.0))
  end

  test "new!/2 returns the segment or raises" do
    assert Segment.from(Segment.new!(Point.origin(), Point.unit_x())) == Point.origin()

    assert_raise ArgumentError, ~r/coincident_points/, fn ->
      Segment.new!(Point.origin(), Point.origin())
    end
  end
end

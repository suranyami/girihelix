defmodule Girihelix.Engine.PlanarMap.SplitTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap.Split

  test "splittable?/3 needs the point on the segment and clear of both ends" do
    a = Point.new(0.0, 0.0)
    b = Point.new(2.0, 0.0)

    assert Split.splittable?(Point.new(1.0, 0.0), a, b)
    assert Split.splittable?(Point.new(1.5e-7, 0.0), a, b)
    refute Split.splittable?(Point.new(1.0, 2.0e-7), a, b)
    refute Split.splittable?(Point.new(3.0, 0.0), a, b)
    refute Split.splittable?(Point.new(5.0e-8, 0.0), a, b)
  end

  test "first_splittable/2 stops at the first edge starting beyond the point" do
    later = {:later, Point.new(4.0, 0.0), Point.new(6.0, 0.0)}
    hidden = {:hidden, Point.new(0.0, 0.0), Point.new(2.0, 0.0)}

    assert Split.first_splittable([hidden, later], Point.new(1.0, 0.0)) == :hidden
    # The edge order is what licenses stopping early, so an edge after the cut-off is never seen.
    assert Split.first_splittable([later, hidden], Point.new(1.0, 0.0)) == nil
  end
end

defmodule Girihelix.Engine.Geometry.PolygonTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Polygon
  alias Girihelix.Engine.Geometry.Transform

  defp unit_square do
    Polygon.new([
      Point.new(0.0, 0.0),
      Point.new(1.0, 0.0),
      Point.new(1.0, 1.0),
      Point.new(0.0, 1.0)
    ])
  end

  test "new/1 keeps the vertex order and reports the count" do
    square = unit_square()

    assert Polygon.num_vertices(square) == 4
    assert Polygon.vertex(square, 0) == {:ok, Point.new(0.0, 0.0)}
    assert Polygon.vertex(square, 2) == {:ok, Point.new(1.0, 1.0)}
    assert square |> Polygon.points() |> length() == 4
  end

  test "vertex/2 reports an index past the end as data" do
    assert Polygon.vertex(unit_square(), 4) == {:error, :out_of_range}
  end

  test "area/1 is the shoelace area, and discards winding" do
    assert Polygon.area(unit_square()) == {:ok, 1.0}

    # the same square, wound the other way, has the same area
    clockwise =
      Polygon.new([
        Point.new(0.0, 0.0),
        Point.new(0.0, 1.0),
        Point.new(1.0, 1.0),
        Point.new(1.0, 0.0)
      ])

    assert Polygon.area(clockwise) == {:ok, 1.0}
  end

  test "area/1 of a triangle" do
    triangle = Polygon.new([Point.new(0.0, 0.0), Point.new(4.0, 0.0), Point.new(0.0, 3.0)])

    assert Polygon.area(triangle) == {:ok, 6.0}
  end

  # Review Focus 5: the Java takes a remainder modulo the vertex count, so an
  # empty polygon raises ArithmeticException rather than returning zero. An error
  # tuple keeps that an error rather than turning it into a value, and lets the
  # caller match it.
  test "area/1 reports an empty polygon as data" do
    assert Polygon.area(Polygon.new([])) == {:error, :empty_polygon}
  end

  test "arc_length/2 measures the open or closed path" do
    square = unit_square()

    assert Polygon.arc_length(square, false) == {:ok, 3.0}
    assert Polygon.arc_length(square, true) == {:ok, 4.0}
  end

  test "arc_length/2 of a single point is zero either way" do
    single = Polygon.new([Point.new(2.0, 3.0)])

    assert Polygon.arc_length(single, false) == {:ok, 0.0}
    assert Polygon.arc_length(single, true) == {:ok, 0.0}
  end

  test "arc_length/2 reports an empty closed polygon as data" do
    assert Polygon.arc_length(Polygon.new([]), true) == {:error, :empty_polygon}

    # ... but an empty open path is legitimately zero
    assert Polygon.arc_length(Polygon.new([]), false) == {:ok, 0.0}
  end

  test "contains_point?/2 is true inside and false outside" do
    square = unit_square()

    assert Polygon.contains_point?(square, Point.new(0.5, 0.5))
    refute Polygon.contains_point?(square, Point.new(2.0, 2.0))
    refute Polygon.contains_point?(square, Point.new(-0.5, 0.5))
  end

  # An empty polygon contains nothing, which is a decision: the Java indexes
  # pts[0] and throws. Returning false is the honest answer to the question, and
  # containment cannot fail, so there is no error tuple to return.
  test "contains_point?/2 is false for an empty polygon" do
    refute Polygon.contains_point?(Polygon.new([]), Point.new(0.0, 0.0))
  end

  test "apply_transform/2 returns a new polygon and leaves the original alone" do
    square = unit_square()
    moved = Polygon.apply_transform(square, Transform.translate(10.0, 0.0))

    assert Polygon.vertex(moved, 0) == {:ok, Point.new(10.0, 0.0)}
    assert Polygon.vertex(square, 0) == {:ok, Point.new(0.0, 0.0)}
  end

  test "point_in_poly/2 takes the polygon as a closed list" do
    points = Polygon.points(unit_square())

    assert Polygon.point_in_poly(points, Point.new(0.5, 0.5))
    refute Polygon.point_in_poly(points, Point.new(1.5, 0.5))
  end

  # Review Focus 5's boundary case, pinned because it is reachable and
  # asymmetric: the half-open straddle test means a point exactly on an edge is
  # reported inside on one side and outside on the other, and three of the unit
  # square's four corners report *outside* the square. Faithful to the Java —
  # Infer asks this question of intersection points that can land on a boundary —
  # so the asymmetry is documented and tested rather than discovered later.
  test "point_in_poly/2 is asymmetric on the boundary" do
    square = unit_square()

    # the lower and left edges count as inside ...
    assert Polygon.contains_point?(square, Point.new(0.5, 0.0))
    assert Polygon.contains_point?(square, Point.new(0.0, 0.5))

    # ... the upper and right edges do not
    refute Polygon.contains_point?(square, Point.new(0.5, 1.0))
    refute Polygon.contains_point?(square, Point.new(1.0, 0.5))

    # and only one of the four corners is inside
    assert Polygon.contains_point?(square, Point.new(0.0, 0.0))
    refute Polygon.contains_point?(square, Point.new(1.0, 0.0))
    refute Polygon.contains_point?(square, Point.new(1.0, 1.0))
    refute Polygon.contains_point?(square, Point.new(0.0, 1.0))
  end
end

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
    assert Polygon.vertex(square, 0) == Point.new(0.0, 0.0)
    assert Polygon.vertex(square, 2) == Point.new(1.0, 1.0)
    assert square |> Polygon.points() |> length() == 4
  end

  test "vertex/2 raises past the end rather than returning a spare slot" do
    assert_raise ArgumentError, ~r/out of range/, fn -> Polygon.vertex(unit_square(), 4) end
  end

  test "area/1 is the shoelace area, and discards winding" do
    assert Polygon.area(unit_square()) == 1.0

    # the same square, wound the other way, has the same area
    clockwise =
      Polygon.new([
        Point.new(0.0, 0.0),
        Point.new(0.0, 1.0),
        Point.new(1.0, 1.0),
        Point.new(1.0, 0.0)
      ])

    assert Polygon.area(clockwise) == 1.0
  end

  test "area/1 of a triangle" do
    triangle = Polygon.new([Point.new(0.0, 0.0), Point.new(4.0, 0.0), Point.new(0.0, 3.0)])

    assert Polygon.area(triangle) == 6.0
  end

  # Review Focus 5: the Java takes a remainder modulo the vertex count, so an
  # empty polygon raises ArithmeticException rather than returning zero. Raising
  # here keeps that an error rather than turning it into a value.
  test "area/1 raises on an empty polygon" do
    assert_raise ArgumentError, ~r/empty polygon/, fn -> Polygon.area(Polygon.new([])) end
  end

  test "arc_length/2 measures the open or closed path" do
    square = unit_square()

    assert Polygon.arc_length(square, false) == 3.0
    assert Polygon.arc_length(square, true) == 4.0
  end

  test "arc_length/2 of a single point is zero either way" do
    single = Polygon.new([Point.new(2.0, 3.0)])

    assert Polygon.arc_length(single, false) == 0.0
    assert Polygon.arc_length(single, true) == 0.0
  end

  test "arc_length/2 raises on an empty closed polygon" do
    assert_raise ArgumentError, ~r/empty polygon/, fn ->
      Polygon.arc_length(Polygon.new([]), true)
    end

    # ... but an empty open path is legitimately zero
    assert Polygon.arc_length(Polygon.new([]), false) == 0.0
  end

  test "contains_point?/2 is true inside and false outside" do
    square = unit_square()

    assert Polygon.contains_point?(square, Point.new(0.5, 0.5))
    refute Polygon.contains_point?(square, Point.new(2.0, 2.0))
    refute Polygon.contains_point?(square, Point.new(-0.5, 0.5))
  end

  # An empty polygon contains nothing, which is a decision: the Java indexes
  # pts[0] and throws. Returning false is the honest answer to the question.
  test "contains_point?/2 is false for an empty polygon" do
    refute Polygon.contains_point?(Polygon.new([]), Point.new(0.0, 0.0))
  end

  test "apply_transform/2 returns a new polygon and leaves the original alone" do
    square = unit_square()
    moved = Polygon.apply_transform(square, Transform.translate(10.0, 0.0))

    assert Polygon.vertex(moved, 0) == Point.new(10.0, 0.0)
    assert Polygon.vertex(square, 0) == Point.new(0.0, 0.0)
  end

  test "point_in_poly/2 takes the polygon as a closed list" do
    points = Polygon.points(unit_square())

    assert Polygon.point_in_poly(points, Point.new(0.5, 0.5))
    refute Polygon.point_in_poly(points, Point.new(1.5, 0.5))
  end
end

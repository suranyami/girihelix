defmodule Girihelix.Engine.Geometry.PolygonTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Polygon
  alias Girihelix.Engine.Geometry.Transform

  defp unit_square do
    Polygon.new!([
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
    assert Polygon.area(unit_square()) == 1.0

    # the same square, wound the other way, has the same area
    clockwise =
      Polygon.new!([
        Point.new(0.0, 0.0),
        Point.new(0.0, 1.0),
        Point.new(1.0, 1.0),
        Point.new(1.0, 0.0)
      ])

    assert Polygon.area(clockwise) == 1.0
  end

  test "area/1 of a triangle" do
    triangle = Polygon.new!([Point.new(0.0, 0.0), Point.new(4.0, 0.0), Point.new(0.0, 3.0)])

    assert Polygon.area(triangle) == 6.0
  end

  test "arc_length/2 measures the open or closed path" do
    square = unit_square()

    assert Polygon.arc_length(square, false) == 3.0
    assert Polygon.arc_length(square, true) == 4.0
  end

  test "arc_length/2 measures a triangle open and closed" do
    triangle = Polygon.new!([Point.new(0.0, 0.0), Point.new(4.0, 0.0), Point.new(0.0, 3.0)])

    assert Polygon.arc_length(triangle, false) == 9.0
    assert Polygon.arc_length(triangle, true) == 12.0
  end

  test "contains_point?/2 is true inside and false outside" do
    square = unit_square()

    assert Polygon.contains_point?(square, Point.new(0.5, 0.5))
    refute Polygon.contains_point?(square, Point.new(2.0, 2.0))
    refute Polygon.contains_point?(square, Point.new(-0.5, 0.5))
  end

  test "new/1 refuses fewer than three vertices" do
    assert Polygon.new([]) == {:error, :too_few_vertices}
    assert Polygon.new([Point.origin(), Point.unit_x()]) == {:error, :too_few_vertices}
    assert {:ok, _triangle} = Polygon.new([Point.origin(), Point.unit_x(), Point.unit_y()])
  end

  test "new!/1 raises on fewer than three vertices" do
    assert_raise ArgumentError, ~r/too_few_vertices/, fn -> Polygon.new!([Point.origin()]) end
  end

  # Review Focus 3: distinctness is the caller's responsibility, so a polygon of
  # three coincident vertices is representable and must measure as nothing.
  test "three coincident vertices make a polygon with no area or length" do
    point = Point.new(2.0, 3.0)
    collapsed = Polygon.new!([point, point, point])

    assert Polygon.area(collapsed) == 0.0
    assert Polygon.arc_length(collapsed, true) == 0.0
    refute Polygon.contains_point?(collapsed, point)
  end

  # Review Focus 4: Enum.fetch/2 counts from the end on a negative index.
  test "vertex/2 treats a negative index as out of range" do
    assert Polygon.vertex(unit_square(), -1) == {:error, :out_of_range}
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

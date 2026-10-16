defmodule Girihelix.Engine.Geometry.TransformTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Transform

  test "identity/0 leaves a point alone" do
    point = Point.new(3.0, -4.0)
    assert Transform.apply_to(Transform.identity(), point) == point
  end

  test "the factories build the matrices the Java builds" do
    assert Transform.scale(2.0) == Transform.new(2.0, 0.0, 0.0, 0.0, 2.0, 0.0)
    assert Transform.scale(2.0, 3.0) == Transform.new(2.0, 0.0, 0.0, 0.0, 3.0, 0.0)
    assert Transform.translate(1.0, 2.0) == Transform.new(1.0, 0.0, 1.0, 0.0, 1.0, 2.0)
    assert Transform.translate_point(Point.new(1.0, 2.0)) == Transform.translate(1.0, 2.0)
  end

  test "rotate/1 turns a point a quarter turn counter-clockwise" do
    rotated = (:math.pi() / 2.0) |> Transform.rotate() |> Transform.apply_to(Point.new(1.0, 0.0))

    assert_in_delta rotated.x, 0.0, 1.0e-12
    assert_in_delta rotated.y, 1.0, 1.0e-12
  end

  test "apply_to/2 and apply_coords/3 agree" do
    transform = 0.3 |> Transform.rotate() |> Transform.compose(Transform.translate(2.0, -1.0))

    assert Transform.apply_to(transform, Point.new(5.0, 7.0)) ==
             Transform.apply_coords(transform, 5.0, 7.0)
  end

  # The composition order is the single easiest thing in this module to read
  # backwards, so it gets an explicit test rather than a comment alone.
  test "compose/2 applies its second argument first" do
    doubler = Transform.scale(2.0)
    shifter = Transform.translate(10.0, 0.0)
    unit = Point.new(1.0, 0.0)

    # translate, then scale: (1 + 10) * 2
    assert doubler |> Transform.compose(shifter) |> Transform.apply_to(unit) ==
             Point.new(22.0, 0.0)

    # scale, then translate: 1 * 2 + 10
    assert shifter |> Transform.compose(doubler) |> Transform.apply_to(unit) ==
             Point.new(12.0, 0.0)
  end

  test "rotate_around_point/2 leaves its centre fixed" do
    centre = Point.new(3.0, 4.0)
    rotated = centre |> Transform.rotate_around_point(1.1) |> Transform.apply_to(centre)

    assert_in_delta rotated.x, centre.x, 1.0e-12
    assert_in_delta rotated.y, centre.y, 1.0e-12
  end

  test "reflect_through_line/2 fixes the line and reverses either side of it" do
    transform = Transform.reflect_through_line(Point.new(0.0, 0.0), Point.new(1.0, 0.0))

    on_line = Transform.apply_to(transform, Point.new(7.0, 0.0))
    assert_in_delta on_line.x, 7.0, 1.0e-12
    assert_in_delta on_line.y, 0.0, 1.0e-12

    mirrored = Transform.apply_to(transform, Point.new(2.0, 3.0))
    assert_in_delta mirrored.x, 2.0, 1.0e-12
    assert_in_delta mirrored.y, -3.0, 1.0e-12

    # and it is orientation-reversing, which is what flips/1 reports
    assert Transform.flips(transform)
  end

  test "invert/1 undoes a transform" do
    transform = 0.7 |> Transform.rotate() |> Transform.compose(Transform.translate(4.0, -2.0))
    point = Point.new(1.5, -3.25)

    moved = Transform.apply_to(transform, point)
    round_tripped = Transform.apply_to(Transform.invert(transform), moved)

    assert_in_delta round_tripped.x, point.x, 1.0e-12
    assert_in_delta round_tripped.y, point.y, 1.0e-12
  end

  test "invert/1 raises on a singular transform" do
    assert_raise ArgumentError, ~r/non-invertible/, fn ->
      Transform.invert(Transform.zero())
    end
  end

  test "flips/1 is false for rotations and uniform scales" do
    refute Transform.flips(Transform.rotate(0.3))
    refute Transform.flips(Transform.scale(2.0))
    assert Transform.flips(Transform.scale(1.0, -1.0))
  end

  test "match_line_segment/2 carries the unit x interval onto p to q" do
    p = Point.new(2.0, 3.0)
    q = Point.new(5.0, 7.0)
    transform = Transform.match_line_segment(p, q)

    assert Transform.apply_coords(transform, 0.0, 0.0) == p
    assert Transform.apply_coords(transform, 1.0, 0.0) == q
  end

  test "match_line_segment/2 never flips, because its determinant is a squared length" do
    backwards = Transform.match_line_segment(Point.new(0.0, 0.0), Point.new(-3.0, -4.0))

    refute Transform.flips(backwards)
    # the determinant is |q - p| squared, so it is 25 here
    assert backwards.a * backwards.e - backwards.b * backwards.d == 25.0
  end

  test "match_two_segments/4 carries one segment onto another" do
    transform =
      Transform.match_two_segments(
        Point.new(1.0, 1.0),
        Point.new(2.0, 1.0),
        Point.new(0.0, 0.0),
        Point.new(0.0, 4.0)
      )

    start = Transform.apply_to(transform, Point.new(1.0, 1.0))
    finish = Transform.apply_to(transform, Point.new(2.0, 1.0))

    assert_in_delta start.x, 0.0, 1.0e-12
    assert_in_delta start.y, 0.0, 1.0e-12
    assert_in_delta finish.x, 0.0, 1.0e-12
    assert_in_delta finish.y, 4.0, 1.0e-12
  end

  test "equality is exact on all six doubles, with no tolerance" do
    assert Transform.translate(1.0, 2.0) == Transform.translate(1.0, 2.0)
    refute Transform.translate(1.0, 2.0) == Transform.translate(1.0, 2.0 + 1.0e-12)
  end

  test "dist_from_zero/2 scales with the transform and its argument" do
    assert_in_delta Transform.dist_from_zero(Transform.scale(3.0), 1.0), 3.0, 1.0e-12
    assert_in_delta Transform.dist_from_zero(Transform.scale(3.0), 2.0), 6.0, 1.0e-12
  end
end

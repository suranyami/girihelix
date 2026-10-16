defmodule Girihelix.Engine.Geometry.IntersectTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Intersect
  alias Girihelix.Engine.Geometry.Point

  # a cross: a horizontal segment and a vertical one through its middle
  defp crossing do
    {Point.new(0.0, 0.0), Point.new(2.0, 0.0), Point.new(1.0, -1.0), Point.new(1.0, 1.0)}
  end

  test "get_intersection_params/4 returns the parameter pair, not a position" do
    {p1, q1, p2, q2} = crossing()

    assert Intersect.get_intersection_params(p1, q1, p2, q2) == {0.5, 0.5}
  end

  test "get_intersection_params/4 returns nil for parallel segments" do
    assert Intersect.get_intersection_params(
             Point.new(0.0, 0.0),
             Point.new(1.0, 0.0),
             Point.new(0.0, 1.0),
             Point.new(1.0, 1.0)
           ) == nil
  end

  test "get_intersection_params/4 returns nil for a zero-length segment" do
    degenerate = Point.new(1.0, 1.0)

    assert Intersect.get_intersection_params(
             degenerate,
             degenerate,
             Point.new(0.0, 0.0),
             Point.new(2.0, 2.0)
           ) == nil
  end

  # Review Focus 4: three quite different situations all produce nil, and the
  # caller cannot tell them apart. Pinned so that no caller grows a dependency
  # on a distinction that does not exist.
  test "parallel, off-segment and degenerate inputs are all indistinguishable" do
    parallel =
      Intersect.get_intersection(
        Point.new(0.0, 0.0),
        Point.new(1.0, 0.0),
        Point.new(0.0, 1.0),
        Point.new(1.0, 1.0)
      )

    # a genuine crossing, but beyond the end of the first segment
    beyond =
      Intersect.get_intersection(
        Point.new(0.0, 0.0),
        Point.new(1.0, 0.0),
        Point.new(2.0, -1.0),
        Point.new(2.0, 1.0)
      )

    degenerate = Point.new(1.0, 1.0)

    empty =
      Intersect.get_intersection(
        degenerate,
        degenerate,
        Point.new(0.0, 0.0),
        Point.new(2.0, 2.0)
      )

    assert parallel == nil
    assert beyond == nil
    assert empty == nil
  end

  # overlapping collinear segments are a documented non-case in the source: the
  # parallel branch returns nil and the author's comment concedes there is
  # nothing useful to do
  test "get_intersection/4 returns nil for overlapping collinear segments" do
    assert Intersect.get_intersection(
             Point.new(0.0, 0.0),
             Point.new(2.0, 0.0),
             Point.new(1.0, 0.0),
             Point.new(3.0, 0.0)
           ) == nil
  end

  test "get_intersection/4 interpolates on the first segment" do
    {p1, q1, p2, q2} = crossing()
    assert Intersect.get_intersection(p1, q1, p2, q2) == Point.new(1.0, 0.0)
  end

  test "stay_on_segments/1 admits parameters a hair outside the unit interval" do
    assert Intersect.stay_on_segments({0.0, 1.0}) == {0.0, 1.0}
    assert Intersect.stay_on_segments({-1.0e-8, 0.5}) == {-1.0e-8, 0.5}
    assert Intersect.stay_on_segments({1.0 + 1.0e-8, 0.5}) == {1.0 + 1.0e-8, 0.5}

    assert Intersect.stay_on_segments({1.5, 0.5}) == nil
    assert Intersect.stay_on_segments({0.5, -0.5}) == nil
    assert Intersect.stay_on_segments(nil) == nil
  end

  test "get_near_intersection/4 accepts a crossing up to 20% past an end" do
    # the second segment sits at x = 1.1, past the end of the first
    p1 = Point.new(0.0, 0.0)
    q1 = Point.new(1.0, 0.0)
    p2 = Point.new(1.1, -1.0)
    q2 = Point.new(1.1, 1.0)

    assert Intersect.get_intersection(p1, q1, p2, q2) == nil
    # ... and the near variant returns a point genuinely off the segment
    assert Intersect.get_near_intersection(p1, q1, p2, q2) == Point.new(1.1, 0.0)
  end

  test "get_true_intersection/4 rejects a crossing at both segments' endpoints" do
    # both segments start at the origin
    assert Intersect.get_true_intersection(
             Point.new(0.0, 0.0),
             Point.new(1.0, 0.0),
             Point.new(0.0, 0.0),
             Point.new(0.0, 1.0)
           ) == nil
  end

  test "get_true_intersection/4 keeps a crossing at one segment's endpoint only" do
    # the shared point is an endpoint of the first segment and interior to the second
    assert Intersect.get_true_intersection(
             Point.new(0.0, 0.0),
             Point.new(1.0, 0.0),
             Point.new(0.0, -1.0),
             Point.new(0.0, 1.0)
           ) == Point.new(0.0, 0.0)
  end

  test "get_true_intersection/4 keeps an ordinary interior crossing" do
    {p1, q1, p2, q2} = crossing()
    assert Intersect.get_true_intersection(p1, q1, p2, q2) == Point.new(1.0, 0.0)
  end
end

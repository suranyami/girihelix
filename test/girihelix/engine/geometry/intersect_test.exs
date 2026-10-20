defmodule Girihelix.Engine.Geometry.IntersectTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Intersect
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Segment

  # a cross: a horizontal segment and a vertical one through its middle
  defp crossing do
    {segment(0.0, 0.0, 2.0, 0.0), segment(1.0, -1.0, 1.0, 1.0)}
  end

  defp segment(x1, y1, x2, y2), do: Segment.new!(Point.new(x1, y1), Point.new(x2, y2))

  test "get_intersection_params/2 returns the parameter pair, not a position" do
    {first, second} = crossing()

    assert Intersect.get_intersection_params(first, second) == {0.5, 0.5}
  end

  test "get_intersection_params/2 returns nil for parallel segments" do
    assert Intersect.get_intersection_params(
             segment(0.0, 0.0, 1.0, 0.0),
             segment(0.0, 1.0, 1.0, 1.0)
           ) == nil
  end

  # Two quite different situations both produce nil, and the
  # caller cannot tell them apart. Pinned so that no caller grows a dependency
  # on a distinction that does not exist.
  test "parallel and off-segment inputs are indistinguishable" do
    parallel =
      Intersect.get_intersection(segment(0.0, 0.0, 1.0, 0.0), segment(0.0, 1.0, 1.0, 1.0))

    # a genuine crossing, but beyond the end of the first segment
    beyond = Intersect.get_intersection(segment(0.0, 0.0, 1.0, 0.0), segment(2.0, -1.0, 2.0, 1.0))

    assert parallel == nil
    assert beyond == nil
  end

  # overlapping collinear segments are a documented non-case: the parallel
  # branch returns nil, and there is nothing useful to do
  test "get_intersection/2 returns nil for overlapping collinear segments" do
    assert Intersect.get_intersection(segment(0.0, 0.0, 2.0, 0.0), segment(1.0, 0.0, 3.0, 0.0)) ==
             nil
  end

  test "get_intersection/2 interpolates on the first segment" do
    {first, second} = crossing()
    assert Intersect.get_intersection(first, second) == Point.new(1.0, 0.0)
  end

  test "stay_on_segments/1 admits parameters a hair outside the unit interval" do
    assert Intersect.stay_on_segments({0.0, 1.0}) == {0.0, 1.0}
    assert Intersect.stay_on_segments({-1.0e-8, 0.5}) == {-1.0e-8, 0.5}
    assert Intersect.stay_on_segments({1.0 + 1.0e-8, 0.5}) == {1.0 + 1.0e-8, 0.5}

    assert Intersect.stay_on_segments({1.5, 0.5}) == nil
    assert Intersect.stay_on_segments({0.5, -0.5}) == nil
    assert Intersect.stay_on_segments(nil) == nil
  end

  test "get_near_intersection/2 accepts a crossing up to 20% past an end" do
    # the second segment sits at x = 1.1, past the end of the first
    first = segment(0.0, 0.0, 1.0, 0.0)
    second = segment(1.1, -1.0, 1.1, 1.0)

    assert Intersect.get_intersection(first, second) == nil
    # ... and the near variant returns a point genuinely off the segment
    assert Intersect.get_near_intersection(first, second) == Point.new(1.1, 0.0)
  end

  test "get_true_intersection/2 rejects a crossing at both segments' endpoints" do
    # both segments start at the origin
    assert Intersect.get_true_intersection(
             segment(0.0, 0.0, 1.0, 0.0),
             segment(0.0, 0.0, 0.0, 1.0)
           ) == nil
  end

  test "get_true_intersection/2 keeps a crossing at one segment's endpoint only" do
    # the shared point is an endpoint of the first segment and interior to the second
    assert Intersect.get_true_intersection(
             segment(0.0, 0.0, 1.0, 0.0),
             segment(0.0, -1.0, 0.0, 1.0)
           ) ==
             Point.new(0.0, 0.0)
  end

  test "get_true_intersection/2 keeps an ordinary interior crossing" do
    {first, second} = crossing()
    assert Intersect.get_true_intersection(first, second) == Point.new(1.0, 0.0)
  end
end

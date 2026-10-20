defmodule Girihelix.Engine.PlanarMap.OrderTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap.Order

  test "compare_points/2 is lexicographic with a 1e-7 window per component" do
    assert Order.compare_points(Point.new(0.0, 5.0), Point.new(1.0, 0.0)) == :lt
    assert Order.compare_points(Point.new(0.0, 0.0), Point.new(5.0e-8, 5.0e-8)) == :eq
    assert Order.compare_points(Point.new(0.0, 0.0), Point.new(5.0e-8, 1.0)) == :lt
    assert Order.compare_points(Point.new(2.0, 0.0), Point.new(1.0, 9.0)) == :gt
  end

  # Flaw 1, pinned: the window makes the comparator non-transitive.
  test "compare_min_x/2 is not transitive" do
    assert Order.compare_min_x(0.0, 6.0e-8) == :eq
    assert Order.compare_min_x(6.0e-8, 1.2e-7) == :eq
    assert Order.compare_min_x(0.0, 1.2e-7) == :lt
    assert Order.compare_min_x(1.2e-7, 0.0) == :gt
  end

  test "find_or_insert/2 reuses a coincident vertex or names the slot" do
    sorted = [{:a, Point.new(0.0, 0.0)}, {:b, Point.new(1.0, 0.0)}]

    assert Order.find_or_insert(sorted, Point.new(1.0, 5.0e-8)) == {:found, :b}
    assert Order.find_or_insert(sorted, Point.new(0.5, 0.0)) == {:insert_at, 1}
    assert Order.find_or_insert(sorted, Point.new(2.0, 0.0)) == {:insert_at, 2}
    assert Order.find_or_insert([], Point.new(2.0, 0.0)) == {:insert_at, 0}
  end

  test "edge_insert_index/2 goes after every key it does not compare below" do
    assert Order.edge_insert_index([0.0, 1.0, 1.0, 2.0], 1.0) == 3
    assert Order.edge_insert_index([0.0, 1.0], -1.0) == 0
    assert Order.edge_insert_index([0.0, 1.0], 5.0) == 2
  end

  test "sort/3 is stable on equal keys" do
    assert Order.sort(
             [{:x, 1.0}, {:y, 0.0}, {:z, 1.0 + 1.0e-9}],
             &elem(&1, 1),
             &Order.compare_min_x/2
           ) ==
             [{:y, 0.0}, {:x, 1.0}, {:z, 1.0 + 1.0e-9}]
  end
end

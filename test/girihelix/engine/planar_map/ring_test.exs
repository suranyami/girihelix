defmodule Girihelix.Engine.PlanarMap.RingTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap.Ring

  test "pseudo_atan2/2 is monotone in the counter-clockwise angle, on [0, 1)" do
    assert Ring.pseudo_atan2(1.0, 0.0) == 0.0
    assert Ring.pseudo_atan2(0.0, 1.0) == 0.25
    assert Ring.pseudo_atan2(-1.0, 0.0) == 0.5
    assert Ring.pseudo_atan2(0.0, -1.0) == 0.75
    assert Ring.pseudo_atan2(0.0, 0.0) == 0.5
    assert Ring.pseudo_atan2(1.0, -1.0) == 0.75
  end

  test "angle/2 is the pseudo angle of the normalized direction" do
    assert Ring.angle(Point.new(1.0, 1.0), Point.new(1.0, 4.0)) == 0.25
    assert Ring.angle(Point.new(0.0, 0.0), Point.new(0.0, 0.0)) == 0.5
  end

  test "insert/2 keeps the head and places by angle, wrapping past 1.0" do
    ring =
      [{:e0, 0.1}]
      |> Ring.insert({:e1, 0.6})
      |> Ring.insert({:e2, 0.3})
      |> Ring.insert({:e3, 0.9})

    assert Ring.edges(ring) == [:e0, :e2, :e1, :e3]
    assert ring |> Ring.insert({:e4, 0.05}) |> Ring.edges() == [:e0, :e2, :e1, :e3, :e4]
  end

  test "insert/2 on an empty ring makes it the head" do
    assert Ring.insert([], {:a, 0.3}) == [{:a, 0.3}]
  end

  # Flaw 5, pinned: an equal angle goes straight after the first equal entry met.
  test "insert/2 puts an equal angle after the first entry it equals" do
    assert [{:a, 0.25}, {:b, 0.5}] |> Ring.insert({:c, 0.25}) |> Ring.edges() == [:a, :c, :b]
  end

  test "remove/2 makes the removed edge's predecessor the head" do
    ring = [{:a, 0.1}, {:b, 0.2}, {:c, 0.3}]
    assert ring |> Ring.remove(:b) |> Ring.edges() == [:a, :c]
    assert ring |> Ring.remove(:c) |> Ring.edges() == [:b, :a]
    assert ring |> Ring.remove(:a) |> Ring.edges() == [:c, :b]
    assert Ring.remove(ring, :missing) == ring
    assert Ring.remove([{:a, 0.1}], :a) == []
  end

  test "before_and_after/2 matches Taprats on degree one and two" do
    assert Ring.before_and_after([{:a, 0.1}], :a) == {:a, :a}
    assert Ring.before_and_after([{:a, 0.1}, {:b, 0.6}], :a) == {:b, :b}
    assert Ring.before_and_after([{:a, 0.1}, {:b, 0.4}, {:c, 0.7}], :b) == {:a, :c}
    assert Ring.before_and_after([{:a, 0.1}], :missing) == nil
  end

  test "swap/3 renames an entry in place and keeps its angle" do
    assert Ring.swap([{:a, 0.1}, {:b, 0.4}], :b, :z) == [{:a, 0.1}, {:z, 0.4}]
  end

  test "reangle/2 keeps the order and replaces every angle" do
    angles = %{a: 0.9, b: 0.2}
    assert Ring.reangle([{:a, 0.1}, {:b, 0.4}], &Map.fetch!(angles, &1)) == [{:a, 0.9}, {:b, 0.2}]
  end
end

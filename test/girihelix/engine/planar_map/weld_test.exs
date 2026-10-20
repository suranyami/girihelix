defmodule Girihelix.Engine.PlanarMap.WeldTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap.Weld

  test "merge_plan/2 walks both orders once, the receiver winning ties" do
    mine = [{:m0, Point.new(0.0, 0.0)}, {:m1, Point.new(2.0, 0.0)}]

    yours = [
      {:y0, Point.new(1.0, 0.0)},
      {:y1, Point.new(2.0, 5.0e-8)},
      {:y2, Point.new(3.0, 0.0)}
    ]

    assert Weld.merge_plan(mine, yours) == [
             {:mine, :m0},
             {:yours, :y0},
             {:same, :m1, :y1},
             {:yours, :y2}
           ]
  end

  test "crossings/2 finds the crossing and ignores a shared endpoint" do
    receiver = [{Point.new(0.0, 0.0), Point.new(2.0, 2.0)}]

    assert Weld.crossings([{Point.new(0.0, 2.0), Point.new(2.0, 0.0)}], receiver) == [
             Point.new(1.0, 1.0)
           ]

    assert Weld.crossings([{Point.new(0.0, 0.0), Point.new(-1.0, 3.0)}], receiver) == []
  end
end

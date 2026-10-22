defmodule Girihelix.Engine.Tilings.TilingTest do
  @moduledoc """
  The tiling value: its lattice generators' unit cell, and the lookup of
  placements by feature id.
  """

  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.Engine.Tilings.PlacedFeature
  alias Girihelix.Engine.Tilings.Tiling

  test "the unit cell is the parallelogram of the two generators" do
    tiling =
      Tiling.new(
        name: "t",
        t1: Point.new(2.0, 0.0),
        t2: Point.new(0.0, 3.0),
        features: [],
        placements: []
      )

    assert Tiling.unit_cell(tiling) == [
             Point.new(0.0, 0.0),
             Point.new(2.0, 0.0),
             Point.new(2.0, 3.0),
             Point.new(0.0, 3.0)
           ]
  end

  test "placements_for/2 filters by feature id and keeps order" do
    a = Transform.translate(1.0, 0.0)
    b = Transform.rotate(0.5)

    tiling =
      Tiling.new(
        name: "t",
        t1: Point.new(1.0, 0.0),
        t2: Point.new(0.0, 1.0),
        features: [],
        placements: [PlacedFeature.new(0, a), PlacedFeature.new(1, b), PlacedFeature.new(0, b)]
      )

    assert Tiling.placements_for(tiling, 0) == [a, b]
    assert Tiling.placements_for(tiling, 2) == []
  end
end

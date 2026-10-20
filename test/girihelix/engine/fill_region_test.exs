defmodule Girihelix.Engine.FillRegionTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.FillRegion
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Steps

  @unit_square [
    Point.new(0.0, 0.0),
    Point.new(4.0, 0.0),
    Point.new(4.0, 3.0),
    Point.new(0.0, 3.0)
  ]

  test "the identity basis fills every integer cell whose corner row and column the region spans" do
    # Under the identity basis the region spans y 0..3, so rows 0..3. Each row
    # spans x 0..4, and both ends floor to integers, so x 0..4 is emitted for
    # every row — the boundary column 4 included.
    expected = for y <- 0..3, x <- 0..4, do: {x, y}

    assert FillRegion.fill(@unit_square, Point.new(1.0, 0.0), Point.new(0.0, 1.0)) ==
             {:ok, expected}
  end

  test "parallel translation vectors are a degenerate basis" do
    assert FillRegion.fill(@unit_square, Point.new(1.0, 0.0), Point.new(2.0, 0.0)) ==
             {:error, :degenerate_basis}

    assert_raise ArgumentError, ~r/degenerate_basis/, fn ->
      FillRegion.fill!(@unit_square, Point.new(1.0, 0.0), Point.new(2.0, 0.0))
    end
  end

  test "fill/3 is the final frame of its steps" do
    steps = FillRegion.steps()
    assert Enum.map(steps, & &1.id) == [:change_basis, :find_rows, :scan_rows]

    t1 = Point.new(1.0, 0.0)
    t2 = Point.new(0.0, 1.0)
    frames = Steps.run!(steps, FillRegion.start(@unit_square, t1, t2))

    assert FillRegion.result(Steps.final(frames)) == FillRegion.fill(@unit_square, t1, t2)
  end
end

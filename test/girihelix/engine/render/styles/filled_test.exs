defmodule Girihelix.Engine.Render.Styles.FilledTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Palette
  alias Girihelix.Engine.Render.Styles.Filled

  defp split_parallel do
    {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
    {map, b} = PlanarMap.insert_vertex(map, Point.new(2.0, 0.0))
    map = PlanarMap.insert_edge!(map, a, b)
    map = PlanarMap.insert_edge!(map, a, b)
    {map, _mid} = PlanarMap.insert_vertex(map, Point.new(1.0, 0.0))
    map
  end

  defp square_diagonal do
    {vertices, map} =
      Enum.map_reduce([{0.0, 0.0}, {4.0, 0.0}, {4.0, 3.0}, {0.0, 3.0}], PlanarMap.new(), fn {x, y}, map ->
        {map, vertex} = PlanarMap.insert_vertex(map, Point.new(x, y))
        {vertex, map}
      end)

    [a, b, c, d] = vertices

    Enum.reduce([{a, b}, {b, c}, {c, d}, {d, a}, {a, c}], map, fn {v1, v2}, map ->
      PlanarMap.insert_edge!(map, v1, v2)
    end)
  end

  test "white faces are light, black faces are dark, then the boundary is stroked" do
    map = split_parallel()

    assert {:ok, %{background: nil, ops: [light, dark | boundary], faces: 2}} =
             Filled.paint(map, Palette.roles!(:"253", [:edge, :darker, :lighter]))

    assert {:polygon, light_points, :fill, [fill: "#f2ff26"]} = light
    assert {:polygon, dark_points, :fill, [fill: "#1b3644"]} = dark

    # Two faces along the doubled y = 0 edge, each bounded by the same three
    # edges; the colouring walks them in opposite directions.
    assert light_points == [{2.0, 0.0}, {0.0, 0.0}, {1.0, 0.0}]
    assert dark_points == [{0.0, 0.0}, {2.0, 0.0}, {1.0, 0.0}]

    assert boundary == [
             {:line, {0.0, 0.0}, {2.0, 0.0}, [stroke: "#340059", width: 1.0]},
             {:line, {0.0, 0.0}, {1.0, 0.0}, [stroke: "#340059", width: 1.0]},
             {:line, {1.0, 0.0}, {2.0, 0.0}, [stroke: "#340059", width: 1.0]}
           ]
  end

  test "a one-colour palette still fills and strokes" do
    assert {:ok, %{ops: ops, faces: 2}} =
             Filled.paint(split_parallel(), Palette.roles!(:"5", [:edge, :darker, :lighter]))

    fills = for {:polygon, _, :fill, [fill: hex]} <- ops, do: hex
    assert Enum.uniq(fills) == ["#4fdf1e", "#153d08"]
  end

  test "an inconsistent colouring is an error tuple" do
    assert Filled.paint(square_diagonal(), Palette.roles!(:"253", [:edge, :darker, :lighter])) ==
             {:error, :filling_conflict}
  end

  test "a map with no faces is an error tuple" do
    assert Filled.paint(PlanarMap.new(), Palette.roles!(:"253", [:edge, :darker, :lighter])) ==
             {:error, :no_faces}
  end
end

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

    assert {:ok, %{ops: [light, dark | boundary], faces: 2}} =
             Filled.paint(map, Palette.roles!(:"253"))

    assert {:polygon, _, :fill, [fill: "#ff7340"]} = light
    assert {:polygon, _, :fill, [fill: "#1b3644"]} = dark
    assert length(boundary) == PlanarMap.num_edges(map)

    for {:line, _from, _to, opts} <- boundary do
      assert opts[:stroke] == "#340059"
    end
  end

  test "a one-colour palette still fills and strokes" do
    assert {:ok, %{ops: ops, faces: 2}} = Filled.paint(split_parallel(), Palette.roles!(:"5"))
    fills = for {:polygon, _, :fill, [fill: hex]} <- ops, do: hex
    assert Enum.uniq(fills) == ["#328e13"]
  end

  test "an inconsistent colouring is an error tuple" do
    assert Filled.paint(square_diagonal(), Palette.roles!(:"253")) ==
             {:error, :filling_conflict}
  end

  test "a map with no faces is an error tuple" do
    assert Filled.paint(PlanarMap.new(), Palette.roles!(:"253")) == {:error, :no_faces}
  end
end

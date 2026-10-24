defmodule Girihelix.Engine.Render.Styles.OutlineTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Palette
  alias Girihelix.Engine.Render.Styles.Outline

  @width 0.05

  test "a dangling edge is one six-point ribbon over a background" do
    {map, [a, b]} = two_vertices()
    map = PlanarMap.insert_edge!(map, a, b)

    assert {:ok, %{background: background, ops: [ribbon], faces: nil}} =
             Outline.paint(map, Palette.roles!(:"253", [:edge, :background]))

    assert {:polygon, _, :fill, [fill: "#f2ff26"]} = background
    assert {:polygon, points, :fill, [fill: "#340059"]} = ribbon
    assert length(points) == 6

    expected = [
      {2.0, -0.05},
      {2.0, 0.0},
      {2.0, 0.05},
      {0.0, 0.05},
      {0.0, 0.0},
      {0.0, -0.05}
    ]

    points
    |> Enum.zip(expected)
    |> Enum.each(fn {point, want} -> assert_close(point, want) end)
  end

  test "a straight-through joint has no miter and falls back to the perpendicular" do
    {map, [a, b, c]} = three_collinear()
    map = map |> PlanarMap.insert_edge!(a, b) |> PlanarMap.insert_edge!(b, c)
    [edge | _] = PlanarMap.edges(map)

    {below, above} = Outline.get_points(map, edge, a, b)
    assert_close(below, {1.0, -@width})
    assert_close(above, {1.0, @width})
  end

  test "a right-angle joint mitres at the offset intersection" do
    assert_close(
      Outline.join_point(Point.new(0.0, 0.0), Point.new(1.0, 0.0), Point.new(0.0, 1.0), @width),
      {@width, @width}
    )
  end

  test "a degree-two junction mitres both offsets" do
    {map, [a, b, _c]} = v_junction()
    edge = PlanarMap.neighbour!(map, a, b)

    {below, above} = Outline.get_points(map, edge, a, b)

    assert_close(below, {1.05, -0.05})
    assert_close(above, {0.95, 0.05})
  end

  test "a degree-three junction mitres against the neighbours either side" do
    {map, [o, a, _b, _c]} = y_junction()
    edge = PlanarMap.neighbour!(map, o, a)

    {below, above} = Outline.get_points(map, edge, a, o)

    assert_close(below, {0.028867513459481284, 0.05})
    assert_close(above, {0.028867513459481284, -0.05})
  end

  test "a ribbon over a junction is six points, mitred at the joint" do
    {map, _vertices} = v_junction()

    assert {:ok, %{background: _background, ops: [ribbon | _], faces: nil}} =
             Outline.paint(map, Palette.roles!(:"253", [:edge, :background]))

    assert {:polygon, points, :fill, [fill: "#340059"]} = ribbon
    assert length(points) == 6

    expected = [
      {1.05, -0.05},
      {1.0, 0.0},
      {0.95, 0.05},
      {0.0, 0.05},
      {0.0, 0.0},
      {0.0, -0.05}
    ]

    points
    |> Enum.zip(expected)
    |> Enum.each(fn {point, want} -> assert_close(point, want) end)
  end

  test "coincident-direction edges have no finite miter" do
    assert Outline.join_point(
             Point.new(0.0, 0.0),
             Point.new(1.0, 0.0),
             Point.new(2.0, 0.0),
             @width
           ) == nil
  end

  test "an empty map paints nothing" do
    assert Outline.paint(PlanarMap.new(), Palette.roles!(:"253", [:edge, :background])) ==
             {:ok, %{background: nil, ops: [], faces: nil}}
  end

  defp two_vertices do
    {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
    {map, b} = PlanarMap.insert_vertex(map, Point.new(2.0, 0.0))
    {map, [a, b]}
  end

  defp three_collinear do
    [{0.0, 0.0}, {1.0, 0.0}, {2.0, 0.0}]
    |> Enum.map_reduce(PlanarMap.new(), fn {x, y}, map ->
      {map, vertex} = PlanarMap.insert_vertex(map, Point.new(x, y))
      {vertex, map}
    end)
    |> then(fn {vertices, map} -> {map, vertices} end)
  end

  # A right-angle bend: the bend is a degree-two vertex at (1, 0).
  defp v_junction do
    {map, [a, b, c]} = vertices([{0.0, 0.0}, {1.0, 0.0}, {1.0, 1.0}])
    {map |> PlanarMap.insert_edge!(a, b) |> PlanarMap.insert_edge!(b, c), [a, b, c]}
  end

  # A Y: three edges meet at the origin, 120 degrees apart.
  defp y_junction do
    {map, [o, a, b, c]} =
      vertices([
        {0.0, 0.0},
        {1.0, 0.0},
        {-0.5, :math.sqrt(3) / 2},
        {-0.5, -:math.sqrt(3) / 2}
      ])

    map =
      map
      |> PlanarMap.insert_edge!(o, a)
      |> PlanarMap.insert_edge!(o, b)
      |> PlanarMap.insert_edge!(o, c)

    {map, [o, a, b, c]}
  end

  defp vertices(points) do
    points
    |> Enum.map_reduce(PlanarMap.new(), fn {x, y}, map ->
      {map, vertex} = PlanarMap.insert_vertex(map, Point.new(x, y))
      {vertex, map}
    end)
    |> then(fn {vertices, map} -> {map, vertices} end)
  end

  defp assert_close(%Point{x: x, y: y}, want), do: assert_close({x, y}, want)

  defp assert_close({x, y}, {want_x, want_y}) do
    assert_in_delta x, want_x, 1.0e-12
    assert_in_delta y, want_y, 1.0e-12
  end
end

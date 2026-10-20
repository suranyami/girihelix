defmodule Girihelix.Engine.FacesTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Faces
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Steps

  defp build(points, edges) do
    {map, handles} =
      Enum.reduce(points, {PlanarMap.new(), []}, fn {x, y}, {map, handles} ->
        {map, vertex} = PlanarMap.insert_vertex(map, Point.new(x, y))
        {map, handles ++ [vertex]}
      end)

    Enum.reduce(edges, map, fn {i, j}, map ->
      PlanarMap.insert_edge!(map, Enum.at(handles, i), Enum.at(handles, j))
    end)
  end

  test "two triangles sharing an edge are a filling conflict" do
    # The clockwise outer face is rejected from the output but still registered,
    # so the colouring reaches it and it conflicts with both triangles.
    map =
      build([{0.0, 0.0}, {4.0, 0.0}, {4.0, 3.0}, {0.0, 3.0}], [
        {0, 1},
        {1, 2},
        {2, 3},
        {3, 0},
        {0, 2}
      ])

    assert Faces.extract_faces(map) == {:error, :filling_conflict}

    assert_raise ArgumentError, ~r/filling_conflict/, fn ->
      Faces.extract_faces!(map)
    end
  end

  test "a path with dangling ends has no face" do
    map = build([{0.0, 0.0}, {1.0, 0.0}, {2.0, 0.0}], [{0, 1}, {1, 2}])

    assert Faces.extract_faces(map) == {:error, :no_faces}

    assert_raise ArgumentError, ~r/no_faces/, fn ->
      Faces.extract_faces!(map)
    end
  end

  test "two parallel edges give two two-corner faces" do
    map = build([{0.0, 0.0}, {2.0, 0.0}], [{0, 1}, {0, 1}])

    assert Faces.extract_faces(map) ==
             {:ok,
              %{
                black: [
                  [Point.new(0.0, 0.0), Point.new(2.0, 0.0)],
                  [Point.new(2.0, 0.0), Point.new(0.0, 0.0)]
                ],
                white: []
              }}
  end

  test "a dangling edge leaves the face it hangs off" do
    map =
      build([{0.0, 0.0}, {2.0, 0.0}, {1.0, 2.0}, {3.0, 2.0}], [
        {0, 1},
        {1, 2},
        {2, 0},
        {2, 3}
      ])

    assert Faces.extract_faces(map) ==
             {:ok,
              %{
                black: [[Point.new(0.0, 0.0), Point.new(2.0, 0.0), Point.new(1.0, 2.0)]],
                white: []
              }}
  end

  test "two faces split by a parallel edge are opposite colours" do
    {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
    {map, b} = PlanarMap.insert_vertex(map, Point.new(2.0, 0.0))
    map = PlanarMap.insert_edge!(map, a, b)
    map = PlanarMap.insert_edge!(map, a, b)

    # Inserted after both edges, the midpoint splits only the first in edge
    # order, leaving two three-corner faces either side of the shared edges.
    {map, _mid} = PlanarMap.insert_vertex(map, Point.new(1.0, 0.0))

    assert {:ok, %{black: [_], white: [_]}} = Faces.extract_faces(map)
  end

  test "extract_faces/1 is the final frame of its steps" do
    map =
      build([{0.0, 0.0}, {2.0, 0.0}, {2.0, 2.0}, {0.0, 2.0}], [
        {0, 1},
        {1, 2},
        {2, 3},
        {3, 0}
      ])

    steps = Faces.steps()
    assert Enum.map(steps, & &1.id) == [:discover, :colour, :collect]

    frames = Steps.run!(steps, Faces.start(map))

    assert Faces.result(Steps.final(frames)) == Faces.extract_faces(map)
  end
end

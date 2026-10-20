defmodule Girihelix.Engine.PlanarMap.VerifyTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap

  defp path(points) do
    {handles, map} =
      Enum.map_reduce(points, PlanarMap.new(), fn {x, y}, map ->
        {map, v} = PlanarMap.insert_vertex(map, Point.new(x, y))
        {v, map}
      end)

    {map, handles}
  end

  test "verify/1 accepts a well-formed map" do
    {map, [a, b, c]} = path([{0.0, 0.0}, {1.0, 0.0}, {1.0, 1.0}])
    map = map |> PlanarMap.insert_edge!(a, b) |> PlanarMap.insert_edge!(b, c)

    assert PlanarMap.verify(map) == :ok
  end

  test "verify/1 accepts an empty map" do
    assert PlanarMap.verify(PlanarMap.new()) == :ok
  end

  test "verify/1 reports a self-edge as trivial" do
    {map, [a]} = path([{0.0, 0.0}])
    map = PlanarMap.insert_edge!(map, a, a)
    [e] = PlanarMap.edges(map)

    assert {:error, problems} = PlanarMap.verify(map)
    assert {:trivial_edge, e} in problems
  end

  test "verify/1 reports the parallel edges a self-weld makes" do
    {map, [a, b]} = path([{0.0, 0.0}, {1.0, 0.0}])
    map = PlanarMap.insert_edge!(map, a, b)
    {welded, _} = PlanarMap.weld!(map, map)

    assert {:error, problems} = PlanarMap.verify(welded)
    assert Enum.any?(problems, &match?({:parallel_edge, _}, &1))
  end

  test "insert_edge_checked/3 refuses every way of meeting the map except at shared endpoints" do
    {map, [a, b, c, d, m]} = path([{0.0, 0.0}, {2.0, 0.0}, {1.0, -1.0}, {1.0, 1.0}, {3.0, 0.0}])
    map = PlanarMap.insert_edge!(map, a, b)
    {map, far} = PlanarMap.insert_vertex(map, Point.new(4.0, 1.0))

    assert PlanarMap.insert_edge_checked(map, c, d) == {:error, :crosses}
    assert PlanarMap.insert_edge_checked(map, a, m) == {:error, :crosses}
    assert PlanarMap.insert_edge_checked(map, a, b) == {:error, :crosses}
    assert PlanarMap.insert_edge_checked(map, a, a) == {:error, :crosses}
    assert {:ok, _} = PlanarMap.insert_edge_checked(map, b, far)
    assert PlanarMap.insert_edge_checked(map, a, 999) == {:error, :unknown_vertex}
  end

  test "insert_edge_checked/3 refuses a T-junction, where a new endpoint lies inside an edge" do
    {map, [a, b, t, far]} = path([{0.0, 0.0}, {2.0, 0.0}, {1.0, 0.0}, {1.0, 3.0}])
    map = PlanarMap.insert_edge!(map, a, b)

    assert PlanarMap.insert_edge_checked(map, t, far) == {:error, :crosses}
    assert PlanarMap.insert_edge_checked(map, far, t) == {:error, :crosses}
  end

  test "insert_edge_checked/3 refuses an edge that passes through a vertex without overlapping" do
    {map, [a, b, p, q, r]} =
      path([{0.0, 0.0}, {1.0, 1.0}, {0.0, 2.0}, {2.0, 0.0}, {5.0, 5.0}])

    map = PlanarMap.insert_edge!(map, a, b)
    assert PlanarMap.insert_edge_checked(map, p, q) == {:error, :crosses}
    assert {:ok, _} = PlanarMap.insert_edge_checked(map, b, r)
  end

  test "insert_edge_checked!/3 raises on a crossing and on an unknown vertex" do
    {map, [a, b]} = path([{0.0, 0.0}, {1.0, 0.0}])
    map = PlanarMap.insert_edge!(map, a, b)

    assert_raise ArgumentError, ~r/crosses/, fn -> PlanarMap.insert_edge_checked!(map, a, b) end

    assert_raise ArgumentError, ~r/unknown_vertex/, fn ->
      PlanarMap.insert_edge_checked!(map, a, 99)
    end

    assert_raise ArgumentError, ~r/crosses/, fn -> PlanarMap.insert_edge_checked!(map, b, b) end
  end
end

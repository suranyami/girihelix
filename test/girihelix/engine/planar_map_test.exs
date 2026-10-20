defmodule Girihelix.Engine.PlanarMapTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Steps

  test "insert_vertex/2 reuses a vertex inside the 1e-7 square window" do
    {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(1.0, 1.0))
    {map, b} = PlanarMap.insert_vertex(map, Point.new(1.0 + 5.0e-8, 1.0 - 5.0e-8))

    assert a == b
    assert PlanarMap.num_vertices(map) == 1
  end

  test "vertices are kept in Taprats order, lexicographic by position" do
    {map, _} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(2.0, 0.0))
    {map, _} = PlanarMap.insert_vertex(map, Point.new(0.0, 5.0))
    {map, _} = PlanarMap.insert_vertex(map, Point.new(0.0, -1.0))

    assert Enum.map(PlanarMap.vertices(map), &PlanarMap.position!(map, &1)) ==
             [Point.new(0.0, -1.0), Point.new(0.0, 5.0), Point.new(2.0, 0.0)]
  end

  test "insert_edge/3 registers the edge in both rings and reports unknown handles" do
    {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
    {map, b} = PlanarMap.insert_vertex(map, Point.new(1.0, 0.0))
    map = PlanarMap.insert_edge!(map, a, b)
    [e] = PlanarMap.edges(map)

    assert PlanarMap.endpoints!(map, e) == {a, b}
    assert PlanarMap.ring!(map, a) == [e]
    assert PlanarMap.neighbour!(map, b, a) == e
    assert PlanarMap.neighbour!(map, a, a) == nil
    assert PlanarMap.insert_edge(map, a, 999) == {:error, :unknown_vertex}
    assert PlanarMap.endpoints(map, 999) == {:error, :unknown_edge}
    assert_raise ArgumentError, ~r/unknown_vertex/, fn -> PlanarMap.insert_edge!(map, 999, a) end
  end

  # Review Focus 4: the unchecked insert accepts a self-edge, as Taprats does.
  test "insert_edge!/3 from a vertex to itself puts the edge in its ring twice" do
    {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(1.0, 1.0))
    map = PlanarMap.insert_edge!(map, a, a)
    [e] = PlanarMap.edges(map)

    assert PlanarMap.ring!(map, a) == [e, e]
  end

  test "before_and_after/3 reports the ring window, or nil for a stranger edge" do
    {map, hub} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
    {map, east} = PlanarMap.insert_vertex(map, Point.new(1.0, 0.0))
    {map, north} = PlanarMap.insert_vertex(map, Point.new(0.0, 1.0))
    map = map |> PlanarMap.insert_edge!(hub, east) |> PlanarMap.insert_edge!(hub, north)
    e_east = PlanarMap.neighbour!(map, hub, east)
    e_north = PlanarMap.neighbour!(map, hub, north)

    assert PlanarMap.before_and_after!(map, hub, e_east) == {e_north, e_north}
    assert PlanarMap.before_and_after!(map, east, e_north) == nil
  end

  test "insert_vertex/2 splits the edge it lands on into two" do
    {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
    {map, b} = PlanarMap.insert_vertex(map, Point.new(2.0, 0.0))
    map = PlanarMap.insert_edge!(map, a, b)
    {map, mid} = PlanarMap.insert_vertex(map, Point.new(1.0, 0.0))

    assert PlanarMap.num_edges(map) == 2
    assert PlanarMap.neighbour!(map, mid, a)
    assert PlanarMap.neighbour!(map, mid, b)
    assert PlanarMap.neighbour!(map, a, b) == nil
  end

  # Review Focus 1: a removed vertex's handle is unknown everywhere.
  test "a removed vertex's handle is unknown everywhere" do
    {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
    {map, b} = PlanarMap.insert_vertex(map, Point.new(1.0, 0.0))
    map = map |> PlanarMap.insert_edge!(a, b) |> PlanarMap.remove_vertex!(a)

    assert PlanarMap.position(map, a) == {:error, :unknown_vertex}
    assert PlanarMap.insert_edge(map, a, b) == {:error, :unknown_vertex}
    assert PlanarMap.remove_vertex(map, a) == {:error, :unknown_vertex}
    assert_raise ArgumentError, ~r/unknown_vertex/, fn -> PlanarMap.ring!(map, a) end
    assert PlanarMap.ring!(map, b) == []
    assert PlanarMap.num_edges(map) == 0
  end

  test "remove_vertex/2 of a self-edge's vertex removes the edge once" do
    {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
    {map, b} = PlanarMap.insert_vertex(map, Point.new(1.0, 0.0))
    map = map |> PlanarMap.insert_edge!(a, a) |> PlanarMap.insert_edge!(a, b)
    map = PlanarMap.remove_vertex!(map, a)

    assert PlanarMap.num_edges(map) == 0
    assert PlanarMap.vertices(map) == [b]
  end

  # Review Focus 5 (flaw 6): a flip is not detected, so rings keep their old order.
  test "scale/2 by a negative factor moves points but keeps every ring's order" do
    {map, hub} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))

    map =
      Enum.reduce([{1.0, 0.0}, {0.0, 1.0}, {-1.0, -1.0}], map, fn {x, y}, map ->
        {map, v} = PlanarMap.insert_vertex(map, Point.new(x, y))
        PlanarMap.insert_edge!(map, hub, v)
      end)

    before = PlanarMap.ring!(map, hub)
    flipped = PlanarMap.scale(map, -1.0)

    assert PlanarMap.ring!(flipped, hub) == before
    assert PlanarMap.position!(flipped, hub) == Point.new(0.0, 0.0)
  end

  test "translate/3 moves every vertex" do
    {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(1.0, 2.0))

    assert PlanarMap.position!(PlanarMap.translate(map, 3.0, -1.0), a) == Point.new(4.0, 1.0)
  end

  test "transform/2 of an empty map is an empty map" do
    assert PlanarMap.vertices(PlanarMap.transform(PlanarMap.new(), Transform.rotate(1.0))) == []
  end

  test "replicate/3 is the final frame of replicate_steps/2" do
    {unit, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
    {unit, b} = PlanarMap.insert_vertex(unit, Point.new(1.0, 0.0))
    unit = PlanarMap.insert_edge!(unit, a, b)
    transforms = Enum.map(0..5, &Transform.rotate(&1 * :math.pi() / 3.0))

    frames = unit |> PlanarMap.replicate_steps(transforms) |> Steps.run!(PlanarMap.new())

    assert length(frames) == 1 + 6 + 1
    assert Steps.final(frames) == PlanarMap.replicate(PlanarMap.new(), unit, transforms)
  end

  # Flaw 7: two unit vertices landing on one receiver vertex make a self-edge.
  test "replicate/3 coalesces coincident copies, even into a self-edge" do
    {unit, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(-1.0, 0.0))
    {unit, b} = PlanarMap.insert_vertex(unit, Point.new(1.0, 0.0))
    unit = PlanarMap.insert_edge!(unit, a, b)

    map = PlanarMap.replicate(PlanarMap.new(), unit, [Transform.zero()])
    [v] = PlanarMap.vertices(map)
    [e] = PlanarMap.edges(map)

    assert PlanarMap.endpoints!(map, e) == {v, v}
  end

  test "weld/2 is the final frame of its steps, with the mapping over the other map's vertices" do
    {receiver, r1} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
    {receiver, r2} = PlanarMap.insert_vertex(receiver, Point.new(2.0, 2.0))
    receiver = PlanarMap.insert_edge!(receiver, r1, r2)
    {other, o1} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 2.0))
    {other, o2} = PlanarMap.insert_vertex(other, Point.new(2.0, 0.0))
    other = PlanarMap.insert_edge!(other, o1, o2)

    {welded, mapping} = PlanarMap.weld(receiver, other)

    frames = Steps.run!(PlanarMap.weld_steps(), PlanarMap.weld_start(receiver, other))
    assert PlanarMap.weld_result(Steps.final(frames)) == {welded, mapping}
    assert mapping |> Map.keys() |> Enum.sort() == Enum.sort([o1, o2])
    assert PlanarMap.num_vertices(welded) == 5
    assert PlanarMap.num_edges(welded) == 4
  end

  # Review Focus 2: welding a map to itself doubles every edge, as Taprats does.
  test "weld/2 of a map with itself unifies every vertex and doubles every edge" do
    {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
    {map, b} = PlanarMap.insert_vertex(map, Point.new(1.0, 0.0))
    map = PlanarMap.insert_edge!(map, a, b)

    {welded, mapping} = PlanarMap.weld(map, map)

    assert mapping == %{a => a, b => b}
    assert PlanarMap.num_edges(welded) == 2
  end
end

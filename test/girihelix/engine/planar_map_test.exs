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

  test "count_vertices/1 totals a map and answers zero for anything else" do
    {map, _} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(1.0, 1.0))

    assert PlanarMap.count_vertices(map) == 1
    assert PlanarMap.count_vertices(nil) == 0
    assert PlanarMap.count_vertices(:not_a_map) == 0
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

  # The unchecked insert accepts a self-edge, as Taprats does.
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

  # A removed vertex's handle is unknown everywhere.
  test "a removed vertex's handle is unknown everywhere" do
    {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
    {map, b} = PlanarMap.insert_vertex(map, Point.new(1.0, 0.0))
    map = PlanarMap.insert_edge!(map, a, b)
    [e] = PlanarMap.edges(map)
    map = PlanarMap.remove_vertex!(map, a)

    assert PlanarMap.position(map, a) == {:error, :unknown_vertex}
    assert PlanarMap.insert_edge(map, a, b) == {:error, :unknown_vertex}
    assert PlanarMap.insert_edge_checked(map, a, b) == {:error, :unknown_vertex}
    assert PlanarMap.insert_edge_checked(map, b, a) == {:error, :unknown_vertex}
    assert PlanarMap.remove_vertex(map, a) == {:error, :unknown_vertex}
    assert PlanarMap.neighbour(map, a, b) == {:error, :unknown_vertex}
    assert PlanarMap.neighbour(map, b, a) == {:error, :unknown_vertex}
    assert PlanarMap.before_and_after(map, a, e) == {:error, :unknown_vertex}
    assert PlanarMap.before_and_after(map, b, e) == {:error, :unknown_edge}
    assert_raise ArgumentError, ~r/unknown_vertex/, fn -> PlanarMap.ring!(map, a) end
    assert_raise ArgumentError, ~r/unknown_vertex/, fn -> PlanarMap.neighbour!(map, a, b) end
    assert_raise ArgumentError, ~r/unknown_vertex/, fn -> PlanarMap.neighbour!(map, b, a) end
    assert PlanarMap.ring!(map, b) == []
    assert PlanarMap.num_edges(map) == 0
  end

  test "neighbour/3 rejects a handle that never existed in either position" do
    {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))

    assert PlanarMap.neighbour(map, a, 999) == {:error, :unknown_vertex}
    assert PlanarMap.neighbour(map, 999, a) == {:error, :unknown_vertex}
    assert_raise ArgumentError, ~r/unknown_vertex/, fn -> PlanarMap.neighbour!(map, a, 999) end
  end

  test "ring/2, endpoints/2 and before_and_after/3 report unknown handles, and their bangs raise" do
    {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
    {map, b} = PlanarMap.insert_vertex(map, Point.new(1.0, 0.0))
    map = PlanarMap.insert_edge!(map, a, b)
    [e] = PlanarMap.edges(map)

    assert PlanarMap.ring(map, 999) == {:error, :unknown_vertex}
    assert PlanarMap.endpoints(map, 999) == {:error, :unknown_edge}
    assert PlanarMap.before_and_after(map, 999, e) == {:error, :unknown_vertex}
    assert PlanarMap.before_and_after(map, a, 999) == {:error, :unknown_edge}
    assert PlanarMap.before_and_after(map, 999, 999) == {:error, :unknown_vertex}
    assert_raise ArgumentError, ~r/unknown_vertex/, fn -> PlanarMap.ring!(map, 999) end
    assert_raise ArgumentError, ~r/unknown_edge/, fn -> PlanarMap.endpoints!(map, 999) end

    assert_raise ArgumentError, ~r/unknown_vertex/, fn ->
      PlanarMap.before_and_after!(map, 999, e)
    end

    assert_raise ArgumentError, ~r/unknown_edge/, fn ->
      PlanarMap.before_and_after!(map, a, 999)
    end
  end

  test "remove_vertex/2 of a self-edge's vertex removes the edge once" do
    {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
    {map, b} = PlanarMap.insert_vertex(map, Point.new(1.0, 0.0))
    map = map |> PlanarMap.insert_edge!(a, a) |> PlanarMap.insert_edge!(a, b)
    map = PlanarMap.remove_vertex!(map, a)

    assert PlanarMap.num_edges(map) == 0
    assert PlanarMap.vertices(map) == [b]
  end

  # A flip is not detected, so rings keep their old order.
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
    assert PlanarMap.vertices(PlanarMap.transform!(PlanarMap.new(), Transform.rotate(1.0))) == []
  end

  test "replicate/3 is the outcome of the final frame of replicate_steps/2" do
    {unit, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
    {unit, b} = PlanarMap.insert_vertex(unit, Point.new(1.0, 0.0))
    unit = PlanarMap.insert_edge!(unit, a, b)
    transforms = Enum.map(0..5, &Transform.rotate(&1 * :math.pi() / 3.0))

    frames =
      unit
      |> PlanarMap.replicate_steps(transforms)
      |> Steps.run!(PlanarMap.replicate_start(PlanarMap.new()))

    assert length(frames) == 1 + 6 + 1

    assert PlanarMap.replicate_result(Steps.final(frames)) ==
             PlanarMap.replicate(PlanarMap.new(), unit, transforms)
  end

  # Flaw 7: two unit vertices landing on one receiver vertex make a self-edge.
  test "replicate/3 coalesces coincident copies, even into a self-edge" do
    {unit, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(-1.0, 0.0))
    {unit, b} = PlanarMap.insert_vertex(unit, Point.new(1.0, 0.0))
    unit = PlanarMap.insert_edge!(unit, a, b)

    map = PlanarMap.replicate!(PlanarMap.new(), unit, [Transform.zero()])
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

    {welded, mapping} = PlanarMap.weld!(receiver, other)

    frames = Steps.run!(PlanarMap.weld_steps(), PlanarMap.weld_start(receiver, other))
    assert PlanarMap.weld_result(Steps.final(frames)) == {:ok, {welded, mapping}}
    assert mapping |> Map.keys() |> Enum.sort() == Enum.sort([o1, o2])
    assert PlanarMap.num_vertices(welded) == 5
    assert PlanarMap.num_edges(welded) == 4
  end

  # Welding a map to itself doubles every edge, as Taprats does.
  test "weld/2 of a map with itself unifies every vertex and doubles every edge" do
    {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
    {map, b} = PlanarMap.insert_vertex(map, Point.new(1.0, 0.0))
    map = PlanarMap.insert_edge!(map, a, b)

    {welded, mapping} = PlanarMap.weld!(map, map)

    assert mapping == %{a => a, b => b}
    assert PlanarMap.num_edges(welded) == 2
  end

  # Flaw 9: where Java's sort would throw "Comparison method violates its
  # general contract!", and Taprats would crash, the port reports the error.
  # 64 vertical edges on a 1e-8 grid, scaled by -1 so their keys flip without
  # re-sorting; every operation that sorts them then meets the broken contract.
  describe "the sort contract" do
    @contract_keys [56, 8, 33, 2, 6, 14, 1, 44, 49, 24, 4, 35, 21, 14, 55, 46] ++
                     [26, 4, 32, 51, 38, 38, 20, 8, 19, 54, 53, 59, 44, 16, 6, 41] ++
                     [20, 2, 52, 33, 54, 11, 58, 46, 5, 7, 1, 43, 52, 22, 9, 22] ++
                     [52, 30, 40, 8, 7, 44, 32, 47, 58, 55, 33, 36, 28, 51, 51, 47]

    defp flipped_edges do
      @contract_keys
      |> Enum.with_index()
      |> Enum.reduce(PlanarMap.new(), fn {key, i}, map ->
        {map, a} = PlanarMap.insert_vertex(map, Point.new(key * 1.0e-8, 2.0 * i))
        {map, b} = PlanarMap.insert_vertex(map, Point.new(key * 1.0e-8, 2.0 * i + 1.0))
        PlanarMap.insert_edge!(map, a, b)
      end)
      |> PlanarMap.scale(-1.0)
    end

    test "transform/2 reports an inconsistent order, and transform!/2 raises" do
      map = flipped_edges()

      assert PlanarMap.transform(map, Transform.identity()) == {:error, :inconsistent_order}

      assert_raise ArgumentError, ~r/inconsistent_order/, fn ->
        PlanarMap.transform!(map, Transform.identity())
      end
    end

    test "replicate/3 reports an inconsistent order, and replicate!/3 raises" do
      unit = flipped_edges()

      assert PlanarMap.replicate(PlanarMap.new(), unit, [Transform.identity()]) ==
               {:error, :inconsistent_order}

      frames =
        unit
        |> PlanarMap.replicate_steps([Transform.identity()])
        |> Steps.run!(PlanarMap.replicate_start(PlanarMap.new()))

      assert %{failure: :inconsistent_order, receiver: last} = Steps.final(frames)
      assert PlanarMap.num_edges(last) == 64

      assert_raise ArgumentError, ~r/inconsistent_order/, fn ->
        PlanarMap.replicate!(PlanarMap.new(), unit, [Transform.identity()])
      end
    end

    test "weld/2 reports an inconsistent order, and weld!/2 raises" do
      other = flipped_edges()

      assert PlanarMap.weld(PlanarMap.new(), other) == {:error, :inconsistent_order}

      assert_raise ArgumentError, ~r/inconsistent_order/, fn ->
        PlanarMap.weld!(PlanarMap.new(), other)
      end
    end
  end

  # The empty and degenerate cases, pinned without the golden fixtures.
  describe "empty and degenerate inputs" do
    defp one_edge_map do
      {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
      {map, b} = PlanarMap.insert_vertex(map, Point.new(1.0, 0.0))
      {PlanarMap.insert_edge!(map, a, b), a, b}
    end

    test "weld/2 into an empty receiver copies the other map" do
      {other, a, b} = one_edge_map()

      {welded, mapping} = PlanarMap.weld!(PlanarMap.new(), other)

      assert PlanarMap.num_vertices(welded) == 2
      assert PlanarMap.num_edges(welded) == 1
      assert mapping |> Map.keys() |> Enum.sort() == Enum.sort([a, b])
    end

    test "weld/2 of an empty other map leaves the receiver as it was, with no mapping" do
      {receiver, _a, _b} = one_edge_map()

      {welded, mapping} = PlanarMap.weld!(receiver, PlanarMap.new())

      assert PlanarMap.num_vertices(welded) == 2
      assert PlanarMap.num_edges(welded) == 1
      assert mapping == %{}
    end

    test "replicate/3 with no transforms leaves the receiver as it was" do
      {receiver, _a, _b} = one_edge_map()
      {unit, _c, _d} = one_edge_map()

      map = PlanarMap.replicate!(receiver, unit, [])

      assert PlanarMap.num_vertices(map) == 2
      assert PlanarMap.num_edges(map) == 1
    end

    test "replicate/3 of an empty unit adds nothing" do
      {receiver, _a, _b} = one_edge_map()

      map = PlanarMap.replicate!(receiver, PlanarMap.new(), [Transform.zero()])

      assert PlanarMap.num_vertices(map) == 2
      assert PlanarMap.num_edges(map) == 1
    end

    test "remove_vertex/2 of the last vertex gives an empty map" do
      {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))

      emptied = PlanarMap.remove_vertex!(map, a)

      assert PlanarMap.num_vertices(emptied) == 0
      assert PlanarMap.num_edges(emptied) == 0
      assert PlanarMap.vertices(emptied) == []
    end
  end
end

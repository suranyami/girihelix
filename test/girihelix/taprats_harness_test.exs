defmodule Girihelix.TapratsHarnessTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.TapratsHarness

  test "parse_script/1 reads every operation and ignores comments" do
    ops =
      TapratsHarness.parse_script("""
      # a comment
      A vertex 0.0 -1.5
      A edge 0 1
      A replicate B rot 1.0 ; tr 2.0 0.0
      dump A
      """)

    assert [
             {:vertex, "A", +0.0, -1.5},
             {:edge, "A", 0, 1},
             {:replicate, "A", "B", [rot, tr]},
             {:dump, "A"}
           ] =
             ops

    assert rot == Transform.rotate(1.0)
    assert tr == Transform.translate(2.0, 0.0)
  end

  test "parse_script/1 strips inline comments anywhere on a line" do
    plain = "A vertex 0.0 0.0\nA replicate B rot 1.0 ; tr 2.0 0.0\n"
    commented = "A vertex 0.0 0.0 # origin\nA replicate B rot 1.0 ; tr 2.0 0.0 # two\n"

    assert TapratsHarness.parse_script(commented) == TapratsHarness.parse_script(plain)
  end

  test "parse_script/1 reads a bare replicate as an empty transform list" do
    assert [{:replicate, "A", "B", []}] = TapratsHarness.parse_script("A replicate B\n")
  end

  test "parse_script/1 rejects an empty segment and a trailing semicolon" do
    assert_raise ArgumentError, ~r/A replicate B rot 1.0 ; ; tr 1 2/, fn ->
      TapratsHarness.parse_script("A replicate B rot 1.0 ; ; tr 1 2")
    end

    assert_raise ArgumentError, ~r/A replicate B rot 1.0 ;/, fn ->
      TapratsHarness.parse_script("A replicate B rot 1.0 ;")
    end
  end

  test "parse_script/1 reads the remaining operations and transform forms" do
    ops =
      TapratsHarness.parse_script("""
      A remove 2
      A transform m 1 2 3 4 5 6
      A scale 2
      A translate 1 -1
      A weld B
      A replicate B sc 3
      """)

    assert [
             {:remove, "A", 2},
             {:transform, "A", m},
             {:scale, "A", 2.0},
             {:translate, "A", 1.0, -1.0},
             {:weld, "A", "B"},
             {:replicate, "A", "B", [sc]}
           ] = ops

    assert m == Transform.new(1.0, 2.0, 3.0, 4.0, 5.0, 6.0)
    assert sc == Transform.scale(3.0)
  end

  test "parse_script/1 raises ArgumentError naming a malformed line" do
    assert_raise ArgumentError, ~r/A frobnicate 1/, fn ->
      TapratsHarness.parse_script("A frobnicate 1")
    end

    assert_raise ArgumentError, ~r/A vertex 1 x/, fn ->
      TapratsHarness.parse_script("A vertex 1 x")
    end
  end

  test "parse_dump/1 reads Java's float spelling" do
    dump =
      TapratsHarness.parse_dump("""
      vertices 1
      v -1.0 2.7755575615628914E-16
      edges 0
      rings
      r 0
      verify true
      """)

    assert dump == %{
             vertices: [{-1.0, 2.7755575615628914e-16}],
             edges: [],
             rings: [[]],
             verify: true
           }
  end

  test "parse_dump/1 reads edges, ring members and the other verify words" do
    text = """
    vertices 2
    v 0.0 0.0
    v 1.0 0.0
    edges 1
    e 0 1
    rings
    r 0 0
    r 1 0
    verify npe
    """

    assert %{edges: [{0, 1}], rings: [[0], [0]], verify: :npe} = TapratsHarness.parse_dump(text)
    assert %{verify: false} = TapratsHarness.parse_dump(String.replace(text, "npe", "false"))
  end

  test "compare/2 accepts coordinates within 1e-12 and nothing looser" do
    base = %{vertices: [{1.0, 0.0}], edges: [], rings: [[]], verify: true}

    assert TapratsHarness.compare(base, %{base | vertices: [{1.0 + 5.0e-13, 0.0}]}) == :ok

    assert {:error, [_]} =
             TapratsHarness.compare(base, %{base | vertices: [{1.0 + 5.0e-12, 0.0}]})
  end

  test "compare/2 is exact on structure" do
    base = %{vertices: [{0.0, 0.0}, {1.0, 0.0}], edges: [{0, 1}], rings: [[0], [0]], verify: true}

    assert {:error, _} = TapratsHarness.compare(base, %{base | edges: [{1, 0}]})
    assert {:error, _} = TapratsHarness.compare(base, %{base | rings: [[0], []]})
    assert TapratsHarness.compare(base, %{base | verify: :unchecked}) == :ok
  end

  test "compare/2 checks the verify word unless it is skipped" do
    base = %{vertices: [], edges: [], rings: [], verify: true}

    assert {:error, [_]} = TapratsHarness.compare(base, %{base | verify: false})
    assert TapratsHarness.compare(%{base | verify: false}, %{base | verify: true}) == :ok
    assert TapratsHarness.compare(%{base | verify: :npe}, %{base | verify: true}) == :ok
  end

  test "compare/2 reports a vertex count mismatch" do
    base = %{vertices: [{0.0, 0.0}], edges: [], rings: [[]], verify: true}

    assert {:error, [_ | _]} = TapratsHarness.compare(base, %{base | vertices: [], rings: []})
  end

  test "parse_script/1 reads the terminal faces operation" do
    assert [{:faces, "A"}] = TapratsHarness.parse_script("A faces\n")
  end

  test "parse_script/1 reads the terminal fill operation" do
    assert [{:fill, points, t1, t2}] =
             TapratsHarness.parse_script("fill 0 0 4 0 4 3 0 3 ; 1 0 ; 0 1\n")

    assert points == [
             Point.new(0.0, 0.0),
             Point.new(4.0, 0.0),
             Point.new(4.0, 3.0),
             Point.new(0.0, 3.0)
           ]

    assert t1 == Point.new(1.0, 0.0)
    assert t2 == Point.new(0.0, 1.0)
  end

  test "parse_dump/1 reads the faces dump" do
    dump =
      TapratsHarness.parse_dump("""
      faces ok
      black 0.0 0.0 4.0 0.0 0.0 3.0
      white 4.0 0.0 4.0 3.0 0.0 3.0
      """)

    assert dump == %{
             faces:
               {:ok,
                %{
                  black: [[{0.0, 0.0}, {4.0, 0.0}, {0.0, 3.0}]],
                  white: [[{4.0, 0.0}, {4.0, 3.0}, {0.0, 3.0}]]
                }}
           }
  end

  test "parse_dump/1 reads both faces failures" do
    assert %{faces: {:error, :filling}} = TapratsHarness.parse_dump("faces error filling\n")
    assert %{faces: {:error, :empty}} = TapratsHarness.parse_dump("faces error empty\n")
  end

  test "parse_dump/1 reads the fill dump, signed cells included" do
    dump =
      TapratsHarness.parse_dump("""
      fill ok
      cell 0 0
      cell -2 3
      """)

    assert dump == %{cells: {:ok, [{0, 0}, {-2, 3}]}}
  end

  test "parse_dump/1 reads the fill failure" do
    assert %{cells: {:error, :too_many}} = TapratsHarness.parse_dump("fill error too_many\n")
  end

  test "compare/2 accepts a face coordinate within 1e-12 and rejects a swap of the faces" do
    expected = %{faces: {:ok, %{black: [[{0.0, 0.0}, {1.0, 0.0}]], white: [[{1.0, 1.0}]]}}}

    near = %{faces: {:ok, %{black: [[{5.0e-13, 0.0}, {1.0, 0.0}]], white: [[{1.0, 1.0}]]}}}
    assert TapratsHarness.compare(expected, near) == :ok

    swapped = %{faces: {:ok, %{black: [[{1.0, 1.0}]], white: [[{0.0, 0.0}, {1.0, 0.0}]]}}}
    assert {:error, _} = TapratsHarness.compare(expected, swapped)
  end

  test "compare/2 is exact on cells, so a swapped order fails" do
    expected = %{cells: {:ok, [{0, 0}, {1, 0}]}}

    assert TapratsHarness.compare(expected, %{cells: {:ok, [{0, 0}, {1, 0}]}}) == :ok
    assert {:error, _} = TapratsHarness.compare(expected, %{cells: {:ok, [{1, 0}, {0, 0}]}})
    assert {:error, _} = TapratsHarness.compare(expected, %{cells: {:error, :too_many}})
  end
end

defmodule Girihelix.Engine.Render.Styles.PlainTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Styles.Plain

  defp roles do
    %{edge: "#111111", darker: "#222222", lighter: "#333333", background: "#eeeeee"}
  end

  defp one_edge do
    {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
    {map, b} = PlanarMap.insert_vertex(map, Point.new(2.0, 0.0))
    PlanarMap.insert_edge!(map, a, b)
  end

  test "one line per edge in the edge colour, over a background" do
    map = one_edge()

    assert {:ok, %{background: background, ops: lines, faces: nil}} = Plain.paint(map, roles())
    assert {:polygon, _, :fill, [fill: "#eeeeee"]} = background

    # Every emitted op after the background is a line with the edge's ends,
    # stroke and fixed width.
    Enum.each(lines, fn line ->
      assert {:line, from, to, opts} = line
      assert from == {0.0, 0.0}
      assert to == {2.0, 0.0}
      assert opts == [stroke: "#111111", width: 1.5]
    end)

    assert length(lines) == PlanarMap.num_edges(map)
  end

  test "an empty map paints nothing" do
    assert Plain.paint(PlanarMap.new(), roles()) == {:ok, %{background: nil, ops: [], faces: nil}}
  end
end

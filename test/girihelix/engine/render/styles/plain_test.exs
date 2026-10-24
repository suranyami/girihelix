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

    assert {:ok, %{ops: [background | lines], faces: nil}} = Plain.paint(map, roles())
    assert {:polygon, _, :fill, [fill: "#eeeeee"]} = background
    assert length(lines) == PlanarMap.num_edges(map)

    for {:line, _from, _to, opts} <- lines do
      assert opts[:stroke] == "#111111"
      assert opts[:width] == 1.5
    end
  end

  test "an empty map paints nothing" do
    assert Plain.paint(PlanarMap.new(), roles()) == {:ok, %{ops: [], faces: nil}}
  end
end

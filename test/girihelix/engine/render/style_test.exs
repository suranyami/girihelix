defmodule Girihelix.Engine.Render.StyleTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Style
  alias Girihelix.Engine.Render.Styles.Plain

  defp roles do
    %{edge: "#111111", darker: "#222222", lighter: "#333333", background: "#eeeeee"}
  end

  test "options lists the three styles in control order" do
    assert Style.options() == [:plain, :filled, :outline]
  end

  test "background builds a padded fill covering the drawing" do
    ops = [{:line, {0.0, 0.0}, {2.0, 0.0}, []}]

    assert {:polygon, [p1, p2, p3, p4], :fill, [fill: "#eeeeee"]} = Style.background(ops, roles())
    assert_close(p1, {-0.04, -0.04})
    assert_close(p2, {2.04, -0.04})
    assert_close(p3, {2.04, 0.04})
    assert_close(p4, {-0.04, 0.04})
  end

  test "an empty drawing gains no background" do
    assert Style.background([], roles()) == nil
  end

  test "a point-only drawing gains no background" do
    ops = [{:point, {1.0, 2.0}, 3.0, []}]
    assert Style.background(ops, roles()) == nil
  end

  test "paint dispatches by style id" do
    map = PlanarMap.new()
    assert {:ok, %{background: nil, ops: [], faces: nil}} = Style.paint(:plain, map, roles())
  end

  test "paint dispatches the filled style" do
    assert Style.paint(:filled, PlanarMap.new(), roles()) == {:error, :no_faces}
  end

  test "paint dispatches the outline style" do
    assert Style.paint(:outline, PlanarMap.new(), roles()) ==
             {:ok, %{background: nil, ops: [], faces: nil}}
  end

  test "each style declares the roles it needs" do
    assert Style.roles(:plain) == [:edge, :background]
    assert Style.roles(:filled) == [:edge, :darker, :lighter]
    assert Style.roles(:outline) == [:edge, :background]
  end

  test "the background is returned apart from the geometry" do
    roles = %{edge: "#111111", background: "#eeeeee"}

    {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
    {map, b} = PlanarMap.insert_vertex(map, Point.new(2.0, 0.0))
    map = PlanarMap.insert_edge!(map, a, b)

    assert {:ok, %{background: {:polygon, _, :fill, [fill: "#eeeeee"]}, ops: ops, faces: nil}} =
             Plain.paint(map, roles)

    assert Enum.all?(ops, &match?({:line, _, _, _}, &1))
  end

  defp assert_close({x, y}, {want_x, want_y}) do
    assert_in_delta x, want_x, 1.0e-12
    assert_in_delta y, want_y, 1.0e-12
  end
end

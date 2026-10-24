defmodule Girihelix.Engine.Render.StyleTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Style

  defp roles do
    %{edge: "#111111", darker: "#222222", lighter: "#333333", background: "#eeeeee"}
  end

  test "options lists the three styles in control order" do
    assert Style.options() == [:plain, :filled, :outline]
  end

  test "background prepends a padded fill covering the drawing" do
    ops = [{:line, {0.0, 0.0}, {2.0, 0.0}, []}]
    [background | rest] = Style.background(ops, roles())

    assert {:polygon, [p1, p2, p3, p4], :fill, [fill: "#eeeeee"]} = background
    assert_close(p1, {-0.04, -0.04})
    assert_close(p2, {2.04, -0.04})
    assert_close(p3, {2.04, 0.04})
    assert_close(p4, {-0.04, 0.04})
    assert rest == ops
  end

  test "an empty drawing gains no background" do
    assert Style.background([], roles()) == []
  end

  test "paint dispatches by style id" do
    map = PlanarMap.new()
    assert {:ok, %{ops: [], faces: nil}} = Style.paint(:plain, map, roles())
  end

  test "paint dispatches the filled style" do
    assert Style.paint(:filled, PlanarMap.new(), roles()) == {:error, :no_faces}
  end

  defp assert_close({x, y}, {want_x, want_y}) do
    assert_in_delta x, want_x, 1.0e-12
    assert_in_delta y, want_y, 1.0e-12
  end
end

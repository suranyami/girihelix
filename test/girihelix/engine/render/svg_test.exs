defmodule Girihelix.Engine.Render.SvgTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Render.Svg
  alias Girihelix.Engine.Render.Viewport

  test "renders every op with its defaults" do
    vp = %Viewport{left: 0.0, top: 10.0, width: 10.0, scale: 1.0}

    svg =
      Svg.render(
        [
          {:line, {0.0, 0.0}, {10.0, 10.0}, []},
          {:polygon, [{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}], :fill, []},
          {:point, {1.0, 2.0}, 0.5, []},
          {:label, {0.0, 0.0}, "a < b", []},
          {:guide, {0.0, 0.0}, {1.0, 1.0}, []}
        ],
        vp
      )

    assert svg =~ ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0.0 0.0 10.0 7.5">)

    assert svg =~
             ~s(<line x1="0.0" y1="10.0" x2="10.0" y2="0.0" stroke="currentColor" stroke-width="1.0")

    assert svg =~
             ~s(<polygon points="0.0,10.0 1.0,10.0 0.0,9.0" fill="currentColor" stroke="none")

    assert svg =~ ~s(<circle cx="1.0" cy="8.0" r="0.5" fill="currentColor")
    assert svg =~ "a &lt; b"
    assert svg =~ ~s(stroke-dasharray="4 4")
  end

  test "options override the defaults" do
    vp = %Viewport{left: 0.0, top: 0.0, width: 1.0, scale: 1.0}

    svg =
      Svg.render([{:line, {0.0, 0.0}, {1.0, 0.0}, stroke: "red", width: 3.0, opacity: 0.5}], vp)

    assert svg =~ ~s(stroke="red")
    assert svg =~ ~s(stroke-width="3.0")
    assert svg =~ ~s(opacity="0.5")
  end

  test "an empty op list still renders a root with the class" do
    vp = %Viewport{left: 0.0, top: 0.0, width: 1.0, scale: 1.0}
    assert Svg.render([], vp, class: "w-full") =~ ~s(class="w-full")
  end

  test "an unknown op or option raises" do
    vp = %Viewport{left: 0.0, top: 0.0, width: 1.0, scale: 1.0}

    assert_raise ArgumentError, ~r/unknown draw op/, fn ->
      Svg.render([{:arc, {0.0, 0.0}, {1.0, 0.0}, []}], vp)
    end

    assert_raise ArgumentError, ~r/unknown draw option/, fn ->
      Svg.render([{:line, {0.0, 0.0}, {1.0, 0.0}, colour: "red"}], vp)
    end
  end
end

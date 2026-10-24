defmodule GirihelixWeb.Workbench.Components.CanvasTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Girihelix.Engine.Render.Viewport
  alias GirihelixWeb.Workbench.Components.Canvas

  test "canvas renders an SVG for a canvas drawing" do
    vp = %Viewport{left: 0.0, top: 1.0, width: 2.0, scale: 1.0}

    html =
      render_component(&Canvas.canvas/1,
        drawing: {:canvas, [{:line, {0.0, 0.0}, {1.0, 1.0}, []}]},
        viewport: vp
      )

    assert html =~ ~s(id="canvas")
    assert html =~ "<svg"

    # An empty drawing still renders a root rather than raising.
    html = render_component(&Canvas.canvas/1, drawing: {:canvas, []}, viewport: nil)
    assert html =~ "<svg"
  end

  test "canvas renders a panel and a both drawing" do
    html = render_component(&Canvas.canvas/1, drawing: {:panel, [{"a", "1"}]}, viewport: nil)
    assert html =~ "a"
    assert html =~ "1"

    html =
      render_component(&Canvas.canvas/1,
        drawing: {:both, [{:point, {0.0, 0.0}, 1.0, []}], [{"b", "2"}]},
        viewport: %Viewport{left: 0.0, top: 0.0, width: 1.0, scale: 1.0}
      )

    assert html =~ "<svg"
    assert html =~ "b"
  end

  test "canvas labels both regions and sizes the SVG to its box" do
    html =
      render_component(&Canvas.canvas/1,
        drawing: {:both, [], [{"b", "2"}]},
        viewport: %Viewport{left: 0.0, top: 0.0, width: 1.0, scale: 1.0}
      )

    assert html =~ ~s(id="canvas")
    assert html =~ ~s(id="panel")
    assert html =~ ~s(class="w-full h-auto overflow-visible")

    html =
      render_component(&Canvas.canvas/1,
        drawing: {:canvas, []},
        viewport: nil,
        aspect: 0.5
      )

    # The empty view is the nominal 1000-wide canvas at aspect 0.5.
    assert html =~ ~s(viewBox="0.0 0.0 1.0e3 500.0")
  end

  test "the SVG root does not clip and the wrappers do" do
    for drawing <- [
          {:canvas, [{:line, {0.0, 0.0}, {1.0, 1.0}, []}]},
          {:both, [{:line, {0.0, 0.0}, {1.0, 1.0}, []}], [{"b", "2"}]}
        ] do
      html = render_component(&Canvas.canvas/1, drawing: drawing, viewport: nil)

      assert html =~ ~s(class="w-full h-auto overflow-visible")
      assert html =~ ~r/<div[^>]*id="canvas"[^>]*class="[^"]*overflow-hidden/
    end
  end

  test "canvas renders a panel as a two-column table" do
    html =
      render_component(&Canvas.canvas/1,
        drawing: {:panel, [{"label", "value"}]},
        viewport: nil
      )

    assert html =~ "<table"
    assert html =~ "<th scope=\"row\">label</th>"
    assert html =~ "<td>value</td>"
  end
end

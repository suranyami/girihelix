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

    # The picture half only: the page places the panel, drawn by `panel/1`.
    assert html =~ "<svg"
    refute html =~ ~s(id="panel")

    assert render_component(&Canvas.panel/1, rows: [{"b", "2"}]) =~ "b"
  end

  test "canvas labels the picture and sizes the SVG to its box" do
    html =
      render_component(&Canvas.canvas/1,
        drawing: {:both, [], [{"b", "2"}]},
        viewport: %Viewport{left: 0.0, top: 0.0, width: 1.0, scale: 1.0}
      )

    assert html =~ ~s(id="canvas")
    refute html =~ ~s(id="panel")
    assert render_component(&Canvas.panel/1, rows: [{"b", "2"}]) =~ ~s(id="panel")
    assert html =~ ~s(class="w-full h-auto max-h-[70vh] overflow-visible")

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

      assert html =~ ~s(class="w-full h-auto max-h-[70vh] overflow-visible")
      assert html =~ ~r/<div[^>]*id="canvas"[^>]*class="[^"]*overflow-hidden/
    end
  end

  test "the canvas carries the zoom hook and its controls" do
    for drawing <- [
          {:canvas, [{:line, {0.0, 0.0}, {1.0, 1.0}, []}]},
          {:both, [{:line, {0.0, 0.0}, {1.0, 1.0}, []}], [{"b", "2"}]}
        ] do
      html = render_component(&Canvas.canvas/1, drawing: drawing, viewport: nil)

      assert html =~ ~s(phx-hook="CanvasZoom")
      assert html =~ ~s(data-zoom-content)
      assert html =~ ~s(data-zoom="in")
      assert html =~ ~s(data-zoom="out")
      assert html =~ ~s(data-zoom="reset")

      # The nesting the hook relies on. The SVG has no divs, so the first
      # `</div>` closes the [data-zoom-content] wrapper: everything before it
      # is the canvas plus the wrapper and the SVG, everything after it holds
      # the controls.
      assert [content, controls] = String.split(html, "</div>", parts: 2)
      assert content =~ ~r/<div data-zoom-content>\s*<svg/
      assert content =~ ~s(id="canvas")
      assert controls =~ ~r/\A\s*<div[^>]*>\s*<button[^>]*data-zoom="in"/

      for action <- ~w(in out reset) do
        refute content =~ ~s(data-zoom="#{action}")
        assert controls =~ ~s(data-zoom="#{action}")
      end
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

defmodule GirihelixWeb.Workbench.Components.ReproducePaneTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias GirihelixWeb.Workbench.Components.ReproducePane

  test "the reproduce pane shows the snippet and a copy button" do
    html =
      render_component(&ReproducePane.reproduce_pane/1,
        snippet: "Point.new(1.0, 2.0)",
        index: 3
      )

    assert html =~ "Point.new(1.0, 2.0)"
    assert html =~ "frame 3"
    assert html =~ ~s|data-copy="Point.new(1.0, 2.0)"|
    assert html =~ "phx-click"
    assert html =~ ~s|id="reproduce"|
  end
end

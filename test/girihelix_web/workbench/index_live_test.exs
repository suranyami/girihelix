defmodule GirihelixWeb.Workbench.IndexLiveTest do
  use GirihelixWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "the index lists every exhibit", %{conn: conn} do
    {:ok, view, html} = live(conn, "/workbench")

    assert html =~ "Workbench"
    assert html =~ "loose"
    assert html =~ ~p"/workbench/faces"
    assert render(view) =~ "Geometry"
  end
end

defmodule GirihelixWeb.Workbench.ExhibitLiveTest do
  use GirihelixWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GirihelixWeb.Workbench.Registry

  test "an exhibit mounts with all four panes", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/workbench/point")

    assert html =~ "<svg"
    assert html =~ "Point"
    assert html =~ ~s(id="panel")
    assert html =~ ~s(id="reproduce")
    assert html =~ "Girihelix.Engine.Geometry.Point.new(3.0, 4.0)"
  end

  test "the default frame is the last one, and the transport moves through it", %{conn: conn} do
    {:ok, view, html} = live(conn, "/workbench/faces")
    assert html =~ "collect colours"

    html = render_click(view, "go", %{"to" => "first"})
    assert html =~ "Parameters"

    html = render_click(view, "go", %{"to" => "next"})
    assert html =~ "discover faces"

    html = render_click(view, "go", %{"to" => "last"})
    assert html =~ "collect colours"
  end

  test "the scrub slider sends a frame", %{conn: conn} do
    {:ok, view, html} = live(conn, "/workbench/faces")
    assert html =~ "collect colours"

    html = render_change(view, "go", %{"frame" => "1"})
    assert html =~ "discover faces"
  end

  test "the rail draws itself with every exhibit, titles only", %{conn: conn} do
    {:ok, view, html} = live(conn, "/workbench/point")

    assert has_element?(view, ".drawer-side")
    assert has_element?(view, ~s(label.drawer-button[for="rail-drawer"]))
    assert has_element?(view, ~s(.drawer-side .drawer-overlay))

    assert html =~ ~p"/workbench/loose"
    assert html =~ ~p"/workbench/transform"
    assert html =~ ~p"/workbench/rosette"

    # Titles only: the summary appears once, in the exhibit's header — never
    # inside the rail. An apostrophe is HTML-escaped, so the needle stops
    # before it.
    assert occurrences(html, "coordinates, magnitude, angle and quarter turn") == 1
  end

  test "the current exhibit is highlighted in the rail", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/workbench/point")

    assert has_element?(view, ~s(.drawer-side a[aria-current=page]), "Point")
  end

  test "the rail highlights a category's first exhibit when you land on it", %{conn: conn} do
    for {_category, exhibits} <- Registry.grouped() do
      {:ok, view, _html} = live(conn, ~p"/workbench/#{hd(exhibits).slug()}")
      title = hd(exhibits).title()

      assert has_element?(view, ~s(.drawer-side a[aria-current=page]), title)
    end
  end

  test "the top navbar marks the exhibit's category as the active one", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/workbench/point")

    assert has_element?(
             view,
             ~s(header nav[aria-label=Categories] a[aria-current=page]),
             "Geometry"
           )
  end

  test "the Workbench back link is gone", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/workbench/point")

    refute html =~ "&larr;"
  end

  test "the URL clamps a parameter and carries the frame", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/workbench/point?x=99.0&y=4.0")
    assert html =~ ~s(value="5.0")

    {:ok, view, _html} = live(conn, "/workbench/faces?frame=1")
    assert render(view) =~ "discover faces"
  end

  test "a parameter change resets to the last frame", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/workbench/point")

    html = render_change(view, "params", %{"x" => "2.0", "y" => "4.0"})
    assert html =~ "Girihelix.Engine.Geometry.Point.new(2.0, 4.0)"
  end

  test "a raising step renders the failure", %{conn: conn} do
    {:ok, _view, html} =
      live(conn, "/workbench/intersect?x1=0.0&y1=0.0&x2=0.0&y2=0.0")

    assert html =~ "failed"
    assert html =~ "build"
  end

  test "an unknown slug is a 404", %{conn: conn} do
    assert_raise GirihelixWeb.Workbench.NotFound, fn -> live(conn, "/workbench/nope") end
  end

  defp occurrences(html, needle), do: length(String.split(html, needle)) - 1
end

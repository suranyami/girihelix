defmodule GirihelixWeb.Workbench.ExhibitLiveTest do
  use GirihelixWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GirihelixWeb.Workbench.Exhibits.Styles
  alias GirihelixWeb.Workbench.Param
  alias GirihelixWeb.Workbench.Registry
  alias GirihelixWeb.Workbench.Run

  # A run is asynchronous now, so every assertion about its result waits for
  # the task rather than reading the loading render. A light exhibit settles in
  # well under a second; only the heavy tiling test takes the large budget.
  @light_timeout 30_000
  @run_timeout 300_000

  defp await_run(view), do: render_async(view, @light_timeout)

  test "an exhibit mounts with all four panes", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/workbench/point")
    html = await_run(view)

    assert html =~ "<svg"
    assert html =~ "Point"
    assert html =~ ~s(id="panel")
    assert html =~ ~s(id="reproduce")
    assert html =~ "Girihelix.Engine.Geometry.Point.new(3.0, 4.0)"
  end

  test "the default frame is the last one, and the transport moves through it", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/workbench/faces")
    assert await_run(view) =~ "collect colours"

    html = render_click(view, "go", %{"to" => "first"})
    assert html =~ "Parameters"

    html = render_click(view, "go", %{"to" => "next"})
    assert html =~ "discover faces"

    html = render_click(view, "go", %{"to" => "last"})
    assert html =~ "collect colours"
  end

  test "the scrub slider sends a frame", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/workbench/faces")
    assert await_run(view) =~ "collect colours"

    html = render_change(view, "go", %{"frame" => "1"})
    assert html =~ "discover faces"
  end

  test "the rail draws itself with the current category's exhibits, titles only", %{conn: conn} do
    {:ok, view, html} = live(conn, "/workbench/point")

    assert has_element?(view, "#rail-root aside")

    assert has_element?(view, ~s(#rail-root aside a[href="/workbench/loose"]))
    assert has_element?(view, ~s(#rail-root aside a[href="/workbench/transform"]))

    # Titles only: the summary appears once, in the exhibit's header — never
    # inside the rail. An apostrophe is HTML-escaped, so the needle stops
    # before it.
    assert occurrences(html, "coordinates, magnitude, angle and quarter turn") == 1

    # The rail shows the exhibit's title, short by construction: the byline
    # (the old title's tag-line) appears once, under the header's title.
    assert occurrences(html, "position as a vector") == 1
    refute html =~ " — "

    # And the page never pins the old long title anywhere, rails included.
    refute html =~ "Point — position as a vector"
  end

  test "the rail lists only the current category's exhibits", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/workbench/tiling")

    for slug <- ["catalogue", "tiling", "instancing"] do
      assert has_element?(view, ~s(#rail-root aside a[href="/workbench/#{slug}"]))
    end

    for slug <- ["point", "loose", "star", "rosette"] do
      refute has_element?(view, ~s(#rail-root aside a[href="/workbench/#{slug}"]))
    end
  end

  test "the top navbar carries the rail's toggle", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/workbench/point")

    assert has_element?(view, ~s(header label[for="rail-drawer"]))

    # The checkbox alone owns the rail's state: the persistence hook sits on
    # the rail root, and a label is all it takes to toggle it — no daisyUI
    # drawer structure anywhere.
    assert has_element?(view, ~s(#rail-root[phx-hook=RailDrawer]))
    assert has_element?(view, ~s(#rail-root input.peer#rail-drawer))
    refute has_element?(view, ".drawer")
  end

  test "a closed rail shows each exhibit's name, not its first letter", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/workbench/tiling")

    assert has_element?(view, "#rail-root aside a", "Instancing")
    refute has_element?(view, "#rail-root aside .badge")
    refute has_element?(view, "#rail-root aside [data-rail-label]")
  end

  test "the current exhibit is highlighted in the rail", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/workbench/point")

    assert has_element?(view, ~s(#rail-root aside a[aria-current=page]), "Point")
  end

  test "the rail highlights a category's first exhibit when you land on it", %{conn: conn} do
    for {_category, exhibits} <- Registry.grouped() do
      {:ok, view, _html} = live(conn, ~p"/workbench/#{hd(exhibits).slug()}")
      title = hd(exhibits).title()

      assert has_element?(view, ~s(#rail-root aside a[aria-current=page]), title)
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
    assert await_run(view) =~ "discover faces"
  end

  test "a parameter change resets to the last frame", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/workbench/point")
    await_run(view)

    render_change(view, "params", %{"x" => "2.0", "y" => "4.0"})
    assert await_run(view) =~ "Girihelix.Engine.Geometry.Point.new(2.0, 4.0)"
  end

  test "a raising step renders the failure", %{conn: conn} do
    {:ok, view, _html} =
      live(conn, "/workbench/intersect?x1=0.0&y1=0.0&x2=0.0&y2=0.0")

    html = await_run(view)
    assert html =~ "failed"
    assert html =~ "build"
  end

  test "the styles exhibit pins a viewport narrower than its patch", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/workbench/styles")

    # The patch spans five cells but the pinned window shows two, so the figure
    # projects outside the viewBox: a fitted viewport would keep every point
    # inside it. Negative coordinates are the fringe the overflow class reveals.
    assert await_run(view) =~ ~r/points="[^"]*-\d/
  end

  @tag :heavy
  @tag timeout: 900_000
  test "a large tiling renders asynchronously with progress", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/workbench/styles?tiling=7.6")

    assert has_element?(view, "#run-progress")
    assert render_async(view, @run_timeout) =~ ~s(id="canvas")
    refute has_element?(view, "#run-progress")
  end

  test "navigating frames reuses the finished frames", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/workbench/styles")
    await_run(view)

    html = render_click(view, "go", %{"to" => "prev"})
    refute has_element?(view, "#run-progress")
    assert html =~ "weld the feature maps"
  end

  @tag :heavy
  @tag timeout: 600_000
  test "heavy tilings use one cell and light ones two" do
    params = defaults()
    assert %{cells: 2} = Run.build(Styles, params, nil)
    assert %{cells: 1} = Run.build(Styles, %{params | tiling: :"Girih Star"}, nil)
  end

  test "an unknown slug is a 404", %{conn: conn} do
    assert_raise GirihelixWeb.Workbench.NotFound, fn -> live(conn, "/workbench/nope") end
  end

  defp occurrences(html, needle), do: length(String.split(html, needle)) - 1
  defp defaults, do: Param.values(Styles.params(), :default)
end

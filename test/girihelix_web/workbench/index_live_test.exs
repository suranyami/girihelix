defmodule GirihelixWeb.Workbench.IndexLiveTest do
  use GirihelixWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GirihelixWeb.Workbench.Registry

  test "the index lists every exhibit", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/workbench")

    assert html =~ "Girihelix"
    assert html =~ "loose"
    assert html =~ ~p"/workbench/faces"
    assert html =~ "Geometry"
    assert html =~ "Tilings"
  end

  test "the navbar links every category to its first exhibit", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/workbench")
    nav = ~s(header nav[aria-label=Categories])

    for {category, exhibits} <- Registry.grouped() do
      first = hd(exhibits)
      label = Phoenix.Naming.humanize(category)

      assert has_element?(view, nav, label)

      assert has_element?(view, ~s(#{nav} a[href="/workbench/#{first.slug()}"]), label)
    end
  end

  test "the index highlights no category", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/workbench")

    refute has_element?(view, ~s(header nav[aria-label=Categories] a[aria-current=page]))
  end

  test "the index rail lists the categories, linking each one's first exhibit", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/workbench")

    for {_category, exhibits} <- Registry.grouped() do
      first = hd(exhibits)

      assert has_element?(view, ~s(#rail-root aside a[href="/workbench/#{first.slug()}"]))
    end

    refute has_element?(view, ~s(#rail-root aside a[href="/workbench/faces"]))
  end

  test "no Exhibits link and no theme toggle remain on the page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/workbench")

    refute html =~ "Exhibits"
    refute html =~ "data-phx-theme"
  end
end

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

  test "the navbar links every category", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/workbench")

    assert html =~ ~p"/workbench?category=geometry"
    assert html =~ ~p"/workbench?category=figures"
    assert html =~ ~p"/workbench?category=tilings"
  end

  test "a category param scopes the directory to one category", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/workbench?category=figures")

    assert html =~ "Rosette"
    refute html =~ ~p"/workbench/point"
  end

  test "an unknown category shows the full directory", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/workbench?category=nonsense")

    assert html =~ "Point"
    assert html =~ "Rosette"
  end
end

defmodule GirihelixWeb.Workbench.ExhibitLiveCacheTest do
  # Synchronous on purpose: these assertions read the shared cache's entries, and
  # a concurrently running async test would build and evict entries between the
  # reads. ExUnit runs sync modules alone, after every async one.
  use GirihelixWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias GirihelixWeb.Workbench.ConstructCache

  @timeout 60_000

  defp styles_key, do: {"styles", {:styles, :"8.5", :rosette}}

  test "style, palette and tiles redraw cached frames without rebuilding", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/workbench/styles")
    render_async(view, @timeout)

    entry = ConstructCache.get(ConstructCache, styles_key())
    assert entry

    # Each change repaints the assigned frames synchronously: the new rows are in
    # the event's own render and no run is in flight.
    html = render_change(view, "params", %{"style" => "outline"})
    assert html =~ "outline"
    refute html =~ ~s(id="run-progress")

    html = render_change(view, "params", %{"style" => "outline", "palette" => "348"})
    assert html =~ "Wada 348"
    refute html =~ ~s(id="run-progress")

    html =
      render_change(view, "params", %{"style" => "outline", "palette" => "348", "tiles" => "true"})

    assert html =~ ~s(fill="#2563eb")
    refute html =~ ~s(id="run-progress")

    # A rebuild would have stored a new entry with a new `inserted_at`; reuse
    # leaves the cached construction exactly as the first run built it.
    assert ConstructCache.get(ConstructCache, styles_key()).inserted_at == entry.inserted_at
  end
end

defmodule GirihelixWeb.Workbench.Components.SourcePaneTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias GirihelixWeb.Workbench.Components.SourcePane

  test "the source pane marks the active range and handles both errors" do
    source =
      {:ok,
       %{
         path: "lib/x.ex",
         first: 2,
         last: 3,
         context_first: 1,
         context_last: 4,
         lines: [{1, "one"}, {2, "two"}, {3, "three"}, {4, "four"}]
       }}

    html = render_component(&SourcePane.source_pane/1, source: source)
    assert html =~ "lib/x.ex:2"
    assert html =~ "three"
    assert html =~ "bg-warning/30"

    assert render_component(&SourcePane.source_pane/1, source: {:error, :no_step}) =~
             "Parameters, before any step"

    assert render_component(&SourcePane.source_pane/1, source: {:error, :unavailable}) =~
             "Source unavailable"
  end

  test "the source pane renders only the context lines" do
    source =
      {:ok,
       %{
         path: "lib/x.ex",
         first: 2,
         last: 2,
         context_first: 1,
         context_last: 4,
         lines: [{1, "one"}, {2, "two"}, {3, "three"}, {4, "four"}, {5, "five"}]
       }}

    html = render_component(&SourcePane.source_pane/1, source: source)

    assert html =~ "one"
    assert html =~ "four"
    refute html =~ "five"
  end
end

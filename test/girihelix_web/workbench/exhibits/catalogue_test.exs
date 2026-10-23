defmodule GirihelixWeb.Workbench.Exhibits.CatalogueTest do
  @moduledoc """
  The catalogue exhibit lists every shipped tiling with its tile counts.
  """

  use ExUnit.Case, async: true

  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibits.Catalogue
  alias GirihelixWeb.Workbench.Param

  test "the catalogue exhibit lists every tiling and its counts" do
    params = Param.values(Catalogue.params(), :default)
    frames = params |> Catalogue.steps() |> Steps.run!(Catalogue.initial(params))

    assert Catalogue.slug() == "catalogue"
    assert Catalogue.category() == :tilings

    assert {:panel, rows} = Catalogue.draw(List.last(frames), params)
    assert {"4.5", "3 features, 7 placements"} in rows
    assert length(rows) >= 60
  end
end

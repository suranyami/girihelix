defmodule GirihelixWeb.Workbench.Exhibits.TilingsTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.Engine.Tilings.Catalogue
  alias GirihelixWeb.Workbench.Exhibits.Tilings

  test "tile ops cover every placement at every translation with a tint per type" do
    tiling = Catalogue.load!("8.5")
    translations = [Transform.identity(), Transform.translate(10.0, 0.0)]
    ops = Tilings.tile_ops(tiling, translations)

    assert length(ops) == 2 * length(tiling.placements) * 2

    fills =
      for {:polygon, _, :fill, [fill: hex, opacity: 0.12]} <- ops, do: hex

    assert length(Enum.uniq(fills)) == min(length(tiling.features), 5)
    assert Enum.any?(ops, &match?({:polygon, _, :stroke, _}, &1))

    assert Enum.any?(
             ops,
             &match?({:polygon, _, :stroke, [stroke: _, width: 0.75, opacity: 0.5]}, &1)
           )
  end

  test "frame zero uses the identity translation" do
    tiling = Catalogue.load!("8.5")
    assert Tilings.tile_ops(tiling, []) == Tilings.tile_ops(tiling, [Transform.identity()])
  end
end

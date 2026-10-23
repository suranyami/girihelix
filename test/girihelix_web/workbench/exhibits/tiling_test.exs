defmodule GirihelixWeb.Workbench.Exhibits.TilingTest do
  @moduledoc """
  The tiling exhibit draws one tiling's vectors, outlines and cell markers.
  """

  use ExUnit.Case, async: true

  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibits.Tiling
  alias GirihelixWeb.Workbench.Param

  test "the tiling exhibit draws vectors, outlines and cells" do
    params = Param.values(Tiling.params(), :default)
    frames = params |> Tiling.steps() |> Steps.run!(Tiling.initial(params))

    assert Enum.map(Tiling.steps(params), & &1.id) == [:place]
    assert {:both, ops, rows} = Tiling.draw(List.last(frames), params)
    assert Enum.any?(ops, &match?({:polygon, _, _, _}, &1))
    assert Enum.any?(ops, &match?({:guide, _, _, _}, &1))
    assert {"name", "4.5"} = List.keyfind(rows, "name", 0)
  end

  test "frame zero draws the tiling's static guides" do
    params = Param.values(Tiling.params(), :default)
    first = params |> Tiling.steps() |> Steps.run!(Tiling.initial(params)) |> hd()
    assert {:both, [_ | _], [_ | _]} = Tiling.draw(first, params)
  end
end

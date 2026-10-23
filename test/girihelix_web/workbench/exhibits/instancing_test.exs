defmodule GirihelixWeb.Workbench.Exhibits.InstancingTest do
  @moduledoc """
  The instancing exhibit constructs a tiling with figures and reports verify.
  """

  use ExUnit.Case, async: true

  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibits.Instancing
  alias GirihelixWeb.Workbench.Param

  test "the instancing exhibit constructs and reports verify" do
    params = Param.values(Instancing.params(), :default)
    last = params |> Instancing.steps() |> Steps.run!(Instancing.initial(params)) |> List.last()

    assert Enum.map(Instancing.steps(params), & &1.id) == [:place, :bind, :units, :weld]
    assert {:both, ops, rows} = Instancing.draw(last, params)
    assert ops != []
    assert {"verify", "ok"} = List.keyfind(rows, "verify", 0)
  end

  test "an unbound run still draws the tiling guides" do
    params = %{Param.values(Instancing.params(), :default) | figure: :none}
    last = params |> Instancing.steps() |> Steps.run!(Instancing.initial(params)) |> List.last()

    assert {:both, [_ | _], rows} = Instancing.draw(last, params)
    assert {"verify", "n/a"} = List.keyfind(rows, "verify", 0)
  end

  test "a triangle tiling in star mode is a failure frame, not a crash" do
    params = %{Param.values(Instancing.params(), :default) | tiling: :"3-8-12", figure: :star}

    assert {:error, %Steps.Failure{frames: frames}} =
             Steps.run(Instancing.steps(params), Instancing.initial(params))

    assert frames != []

    for frame <- frames do
      assert {:both, [_ | _], [_ | _]} = Instancing.draw(frame, params)
    end
  end
end

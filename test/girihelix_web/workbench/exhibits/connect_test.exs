defmodule GirihelixWeb.Workbench.Exhibits.ConnectTest do
  @moduledoc """
  The `connect` exhibit: no `s` parameter, the derived scale, frame drawing and
  the reproduce snippet.
  """

  use ExUnit.Case, async: true

  alias Girihelix.Engine.Figures.ConnectFigure
  alias Girihelix.Engine.Figures.Rosette, as: RosetteFigure
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibits.Connect
  alias GirihelixWeb.Workbench.Param

  test "the connect exhibit has no s parameter and reports the derived scale" do
    refute Enum.any?(Connect.params(), &(&1.name == :s))

    params = Param.values(Connect.params(), :default)
    last = params |> Connect.steps() |> Steps.run!(Connect.initial(params)) |> List.last()

    assert {:both, _ops, rows} = Connect.draw(last, params)
    assert {"derived s", value} = List.keyfind(rows, "derived s", 0)
    assert abs(String.to_float(value) - 0.7071067811865475) < 1.0e-12
    assert Connect.reproduce(params) =~ "ConnectFigure.new!"
  end

  test "identifies itself and declares the child parameters" do
    assert Connect.slug() == "connect"
    assert Connect.category() == :figures
    assert Connect.title() != ""
    assert Connect.summary() != ""

    assert Enum.map(Connect.params(), & &1.name) == [:child, :n, :q, :d, :child_s]
  end

  test "starts from ConnectFigure.start/2 with the derived scale" do
    params = Param.values(Connect.params(), :default)
    child = RosetteFigure.new!(8, 0.0, 3)

    assert Connect.initial(params) == ConnectFigure.start(child, ConnectFigure.new!(child).s)
    assert Connect.steps(params) == ConnectFigure.steps(child, ConnectFigure.new!(child).s)
  end

  test "frame zero draws only the tip marker before the unit is built" do
    params = Param.values(Connect.params(), :default)

    assert {:both, ops, rows} =
             Connect.draw(hd(Steps.run!(Connect.steps(params), Connect.initial(params))), params)

    assert ops == [{:point, {1.0, 0.0}, 4.0, []}]
    assert {"fallback", "-"} in rows
    assert {"max x", "-"} in rows
    assert {"verify", "n/a"} in rows
  end

  test "the completed frame reports the result and labels its diagnostics" do
    params = Param.values(Connect.params(), :default)

    assert {:both, ops, rows} = draw_last(params)

    assert Enum.any?(ops, &match?({:label, _, "child unit", []}, &1))
    assert Enum.any?(ops, &match?({:label, _, "half step", []}, &1))
    assert {"child", "rosette"} in rows
    assert {"fallback", "no"} in rows
    assert {"vertices", _} = List.keyfind(rows, "vertices", 0)
    assert {"max x", _} = List.keyfind(rows, "max x", 0)
    assert {"verify", "ok"} in rows
  end

  test "a star child spells its reproduce call with the star's d" do
    params = %{Param.values(Connect.params(), :default) | child: :star, n: 8, d: 3.0, child_s: 2}

    assert Connect.reproduce(params) =~ "Girihelix.Engine.Figures.Star.new!(8, 3.0, 2)"
  end

  test "pins the 2.5-unit viewport centred on the unit circle" do
    params = Param.values(Connect.params(), :default)

    assert Connect.viewport(params) == %Girihelix.Engine.Render.Viewport{
             left: -1.25,
             top: 1.25,
             width: 2.5,
             scale: 400.0
           }
  end

  defp draw_last(params) do
    params
    |> Connect.steps()
    |> Steps.run!(Connect.initial(params))
    |> List.last()
    |> Connect.draw(params)
  end
end

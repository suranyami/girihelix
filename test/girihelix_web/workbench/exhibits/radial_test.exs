defmodule GirihelixWeb.Workbench.Exhibits.RadialTest do
  @moduledoc """
  The `radial` exhibit: the ladder's single replicate step, the per-copy labels,
  the panel rows and the reproduce snippet.
  """

  use ExUnit.Case, async: true

  alias Girihelix.Engine.Figures.RadialFigure
  alias Girihelix.Engine.Figures.Rosette, as: RosetteFigure
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibits.Radial
  alias GirihelixWeb.Workbench.Param

  test "the radial exhibit steps the ladder once and labels every copy" do
    params = Param.values(Radial.params(), :default)
    frames = params |> Radial.steps() |> Steps.run!(Radial.initial(params))

    assert Enum.map(Radial.steps(params), & &1.id) == [:replicate]
    assert {:both, ops, rows} = Radial.draw(List.last(frames), params)
    assert Enum.count(ops, &match?({:label, _, "Tr" <> _, _}, &1)) == params.n
    assert {"transforms", _} = List.keyfind(rows, "transforms", 0)
    assert Radial.reproduce(params) =~ "RadialFigure.map"
  end

  test "identifies itself and declares the design's parameters" do
    assert Radial.slug() == "radial"
    assert Radial.category() == :figures
    assert Radial.title() != ""
    assert Radial.summary() != ""

    assert Enum.map(Radial.params(), & &1.name) == [:kind, :n, :d, :q, :s]

    [kind, n, d, q, s] = Radial.params()
    assert {kind.type, kind.default, kind.options} == {:enum, :rosette, [:star, :rosette]}
    assert {n.type, n.default, n.range} == {:integer, 8, 3..24}
    assert {d.type, d.default, d.range, d.step} == {:float, 3.0, 1..10, 0.1}
    assert {q.type, q.default, q.range, q.step} == {:float, 0.0, -2..2, 0.05}
    assert {s.type, s.default, s.range} == {:integer, 3, 1..6}
  end

  test "builds the figure from kind and the ladder from n" do
    params = Param.values(Radial.params(), :default)

    assert Radial.initial(params) == %{
             figure: RosetteFigure.new!(8, 0.0, 3),
             map: nil,
             unit: nil,
             transforms: RadialFigure.ladder(8)
           }
  end

  test "frame zero draws only the tip marker and dashes the unset rows" do
    params = Param.values(Radial.params(), :default)

    assert {:both, ops, rows} =
             Radial.draw(hd(Steps.run!(Radial.steps(params), Radial.initial(params))), params)

    assert ops == [{:point, {1.0, 0.0}, 4.0, []}]
    assert {"unit vertices", "-"} in rows
    assert {"vertices", "0"} in rows
    assert {"verify", "n/a"} in rows
  end

  test "the completed frame reports the ladder and every copy" do
    params = Param.values(Radial.params(), :default)

    assert {:both, ops, rows} = draw_last(params)

    assert Enum.any?(ops, &match?({:label, _, "Tr^1", []}, &1))
    assert Enum.any?(ops, &match?({:label, _, "Tr^8", []}, &1))
    assert {"kind", "rosette"} in rows
    assert {"n", "8"} in rows
    assert {"transforms", "8"} in rows
    assert {"vertices", _} = List.keyfind(rows, "vertices", 0)
    assert {"unit vertices", _} = List.keyfind(rows, "unit vertices", 0)
    assert {"verify", "ok"} in rows
  end

  test "a star kind reports the star kind and its reproduce call" do
    params = %{Param.values(Radial.params(), :default) | kind: :star}

    assert {:both, _ops, rows} = draw_last(params)
    assert {"kind", "star"} in rows

    assert Radial.reproduce(params) =~
             "Girihelix.Engine.Figures.RadialFigure.map(" <>
               "Girihelix.Engine.Figures.Star.new!(8, 3.0, 3))"
  end

  test "pins the 2.5-unit viewport centred on the unit circle" do
    params = Param.values(Radial.params(), :default)

    assert Radial.viewport(params) == %Girihelix.Engine.Render.Viewport{
             left: -1.25,
             top: 1.25,
             width: 2.5,
             scale: 400.0
           }
  end

  defp draw_last(params) do
    params
    |> Radial.steps()
    |> Steps.run!(Radial.initial(params))
    |> List.last()
    |> Radial.draw(params)
  end
end

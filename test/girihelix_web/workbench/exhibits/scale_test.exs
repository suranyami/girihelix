defmodule GirihelixWeb.Workbench.Exhibits.ScaleTest do
  @moduledoc """
  The `scale` exhibit: its identity, parameters, step ids, frame drawing and
  reproduce snippet.
  """

  use ExUnit.Case, async: true

  alias Girihelix.Engine.Figures.Rosette, as: RosetteFigure
  alias Girihelix.Engine.Figures.ScaleFigure
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibits.Scale
  alias GirihelixWeb.Workbench.Param

  test "the scale exhibit draws the child, the border and the extension" do
    params = Param.values(Scale.params(), :default)
    frames = params |> Scale.steps() |> Steps.run!(Scale.initial(params))

    assert Enum.map(Scale.steps(params), & &1.id) ==
             [:clamp, :child, :scale, :clip, :extend, :endpoint]

    assert {:both, ops, rows} = Scale.draw(List.last(frames), params)
    assert [_ | _] = ops
    assert Enum.any?(ops, &match?({:point, _, _, _}, &1))
    assert Enum.any?(ops, &match?({:point, _, 4.0, []}, &1))
    refute Enum.any?(ops, &match?({:point, _, 3.0, [opacity: 0.6]}, &1))
    assert {"passthrough", _} = List.keyfind(rows, "passthrough", 0)
    assert Scale.reproduce(params) =~ "ScaleFigure.build_unit"
  end

  test "the scale exhibit draws frame zero before the child is built" do
    params = Param.values(Scale.params(), :default)
    first = params |> Scale.steps() |> Steps.run!(Scale.initial(params)) |> hd()

    assert {:both, _ops, _rows} = Scale.draw(first, params)
  end

  test "identifies itself and declares the design's parameters" do
    assert Scale.slug() == "scale"
    assert Scale.category() == :figures
    assert Scale.title() != ""
    assert Scale.summary() != ""

    assert Enum.map(Scale.params(), & &1.name) == [:child, :n, :q, :d, :child_s, :s]

    [child, n, q, d, child_s, s] = Scale.params()
    assert {child.type, child.default, child.options} == {:enum, :rosette, [:rosette, :star]}
    assert {n.type, n.default, n.range} == {:integer, 8, 3..12}
    assert {q.type, q.default, q.range, q.step} == {:float, 0.0, -2..2, 0.05}
    assert {d.type, d.default, d.range, d.step} == {:float, 3.0, 1..10, 0.1}
    assert {child_s.type, child_s.default, child_s.range} == {:integer, 3, 1..6}
    assert {s.type, s.default, s.range, s.step} == {:float, 1.5, 0..3, 0.1}
  end

  test "starts from ScaleFigure.start/2 and runs the engine's steps" do
    params = Param.values(Scale.params(), :default)
    child = RosetteFigure.new!(8, 0.0, 3)

    assert Scale.initial(params) == ScaleFigure.start(child, 1.5)
    assert Scale.steps(params) == ScaleFigure.steps(child, 1.5)
  end

  test "frame zero draws only the tip marker and dashes the unset rows" do
    params = Param.values(Scale.params(), :default)

    assert {:both, ops, rows} =
             Scale.draw(hd(Steps.run!(Scale.steps(params), Scale.initial(params))), params)

    assert ops == [{:point, {1.0, 0.0}, 4.0, []}]
    assert {"s stored", "-"} in rows
    assert {"passthrough", "-"} in rows
    assert {"tip", "-"} in rows
    assert {"endpoint", "-"} in rows
    assert {"verify", "n/a"} in rows
  end

  test "the completed frame labels every diagnostic guide" do
    params = Param.values(Scale.params(), :default)

    assert {:both, ops, _rows} = draw_last(params)

    assert Enum.any?(ops, &match?({:label, _, "child unit", []}, &1))
    assert Enum.any?(ops, &match?({:label, _, "clip border", []}, &1))
    assert Enum.any?(ops, &match?({:label, _, "tip ray", []}, &1))
  end

  test "an s of one is a passthrough and draws no clip" do
    params = %{Param.values(Scale.params(), :default) | s: 1.0}

    assert {:both, ops, rows} = draw_last(params)

    assert {"passthrough", "yes"} in rows
    assert {"s stored", "1.0"} in rows
    refute Enum.any?(ops, &match?({:label, _, "clip border", []}, &1))
    refute Enum.any?(ops, &match?({:label, _, "tip ray", []}, &1))
  end

  test "a star child spells its reproduce call with the star's d" do
    params = %{Param.values(Scale.params(), :default) | child: :star, n: 8, d: 3.0, child_s: 2}

    assert Scale.reproduce(params) =~ "Girihelix.Engine.Figures.Star.new!(8, 3.0, 2)"
  end

  test "frames an aspect-correct window large enough for the scaled child" do
    params = Param.values(Scale.params(), :default)
    radius = 1.5
    width = 2.0 * radius / 0.75
    viewport = Scale.viewport(params, [])

    assert viewport.left == -radius / 0.75
    assert viewport.top == radius
    assert viewport.width == width
    assert viewport.scale == 1000.0 / width
  end

  defp draw_last(params) do
    params
    |> Scale.steps()
    |> Steps.run!(Scale.initial(params))
    |> List.last()
    |> Scale.draw(params)
  end
end

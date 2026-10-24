defmodule GirihelixWeb.Workbench.Exhibits.StarTest do
  @moduledoc """
  The `star` exhibit: its identity, parameters, step ids, frame drawing and
  reproduce snippet.
  """

  use ExUnit.Case, async: true

  alias Girihelix.Engine.Figures.Star, as: StarFigure
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibits.Star
  alias GirihelixWeb.Workbench.Param

  test "the star exhibit builds, draws and reproduces" do
    params = Param.values(Star.params(), :default)
    state = Star.initial(params)
    frames = params |> Star.steps() |> Steps.run!(state)
    last = List.last(frames)

    assert Star.slug() == "star"
    assert Star.category() == :figures
    assert_steps(Star.steps(params), [:clamp, :chord, :crossings, :assemble, :closure])

    assert {:both, ops, rows} = Star.draw(last, params)
    assert Enum.any?(ops, &match?({:line, _, _, _}, &1))
    assert Enum.any?(ops, &match?({:label, _, _, _}, &1))
    assert Enum.any?(ops, &match?({:label, _, "base chord", []}, &1))
    assert {"vertices", _} = List.keyfind(rows, "vertices", 0)
    assert Star.reproduce(params) =~ "Girihelix.Engine.Figures.Star.new!(8, 3.0, 2)"
  end

  test "every frame draws, including frame zero" do
    params = Param.values(Star.params(), :default)

    for frame <- params |> Star.steps() |> Steps.run!(Star.initial(params)) do
      assert {:both, ops, _rows} = Star.draw(frame, params)
      assert [_ | _] = ops
    end
  end

  test "identifies itself and declares the design's parameters" do
    assert Star.title() != ""
    assert Star.summary() != ""

    assert [n, d, s] = Star.params()
    assert {n.name, n.type, n.default, n.range} == {:n, :integer, 8, 3..24}
    assert {d.name, d.type, d.default, d.range, d.step} == {:d, :float, 3.0, 1..10, 0.1}
    assert {s.name, s.type, s.default, s.range} == {:s, :integer, 2, 1..6}
  end

  test "starts from Star.start/3 and runs the engine's steps" do
    params = Param.values(Star.params(), :default)

    assert Star.initial(params) == StarFigure.start(8, 3.0, 2)
    assert Star.steps(params) == StarFigure.steps(8, 3.0, 2)
  end

  test "frame zero draws only the tip marker" do
    params = Param.values(Star.params(), :default)

    assert {:both, ops, rows} =
             Star.draw(hd(Steps.run!(Star.steps(params), Star.initial(params))), params)

    assert ops == [{:point, {1.0, 0.0}, 4.0, []}]
    assert {"vertices", "0"} in rows
    assert {"edges", "0"} in rows
    assert {"verify", "n/a"} in rows
  end

  test "the closure frame adds the apex edge in a distinct stroke" do
    params = %{Param.values(Star.params(), :default) | s: 3}
    last = params |> Star.steps() |> Steps.run!(Star.initial(params)) |> List.last()
    assert {:both, ops, rows} = Star.draw(last, params)

    assert Enum.any?(ops, &match?({:line, _, _, [width: 3.0, dash: "6 3"]}, &1))
    assert Enum.any?(ops, &match?({:label, _, "closure", []}, &1))
    assert {"closure", "yes"} in rows
  end

  test "the fractional closure frame marks the cent point" do
    params = %{Param.values(Star.params(), :default) | d: 2.5, s: 2}
    last = params |> Star.steps() |> Steps.run!(Star.initial(params)) |> List.last()
    assert {:both, ops, rows} = Star.draw(last, params)

    assert Enum.any?(ops, &match?({:point, _, 5.0, _}, &1))
    assert {"closure", "yes"} in rows
  end

  test "frames an aspect-correct window centred on the origin" do
    params = Param.values(Star.params(), :default)
    radius = 1.25
    width = 2.0 * radius / 0.75
    viewport = Star.viewport(params, [])

    assert viewport.left == -radius / 0.75
    assert viewport.top == radius
    assert viewport.width == width
    assert viewport.scale == 1000.0 / width
  end

  defp assert_steps(steps, ids), do: assert(Enum.map(steps, & &1.id) == ids)
end

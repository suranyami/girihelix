defmodule GirihelixWeb.Workbench.Exhibits.RosetteTest do
  @moduledoc """
  The `rosette` exhibit: its identity, parameters, clamps, skip count, frame
  drawing and reproduce snippet.
  """

  use ExUnit.Case, async: true

  alias Girihelix.Engine.Figures.Rosette, as: RosetteFigure
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibits.Rosette
  alias GirihelixWeb.Workbench.Param

  test "the rosette exhibit reports the clamp and the skip count" do
    params = %{Param.values(Rosette.params(), :default) | n: 12, q: -0.8, s: 4}
    last = params |> Rosette.steps() |> Steps.run!(Rosette.initial(params)) |> List.last()

    assert {:both, ops, rows} = Rosette.draw(last, params)
    assert Enum.any?(ops, &match?({:guide, _, _, _}, &1))
    assert Enum.any?(ops, &match?({:label, _, _, _}, &1))
    assert Enum.any?(ops, &match?({:label, _, "outer bisector", []}, &1))
    assert Enum.any?(ops, &match?({:label, _, "tip to qtip", []}, &1))
    assert Enum.any?(ops, &match?({:label, _, "key line", []}, &1))
    assert {"steps skipped", skipped} = List.keyfind(rows, "steps skipped", 0)
    assert skipped != "0"
    assert Rosette.reproduce(params) =~ "Rosette.new!(12, -0.8, 4)"
  end

  test "every frame draws, including frame zero" do
    params = Param.values(Rosette.params(), :default)

    for frame <- params |> Rosette.steps() |> Steps.run!(Rosette.initial(params)) do
      assert {:both, ops, _rows} = Rosette.draw(frame, params)
      assert [_ | _] = ops
    end
  end

  test "identifies itself and declares the design's parameters" do
    assert Rosette.slug() == "rosette"
    assert Rosette.category() == :figures
    assert Rosette.title() != ""
    assert Rosette.summary() != ""

    assert [n, q, s] = Rosette.params()
    assert {n.name, n.type, n.default, n.range} == {:n, :integer, 8, 3..24}
    assert {q.name, q.type, q.default, q.range, q.step} == {:q, :float, 0.0, -2..2, 0.05}
    assert {s.name, s.type, s.default, s.range} == {:s, :integer, 3, 1..6}
  end

  test "starts from Rosette.start/3 and runs the engine's steps" do
    params = Param.values(Rosette.params(), :default)

    assert Rosette.initial(params) == RosetteFigure.start(8, 0.0, 3)
    assert Rosette.steps(params) == RosetteFigure.steps(8, 0.0, 3)
  end

  test "frame zero draws only the tip marker" do
    params = Param.values(Rosette.params(), :default)

    assert {:both, ops, rows} =
             Rosette.draw(hd(Steps.run!(Rosette.steps(params), Rosette.initial(params))), params)

    assert ops == [{:point, {1.0, 0.0}, 4.0, []}]
    assert {"vertices", "0"} in rows
    assert {"edges", "0"} in rows
    assert {"verify", "n/a"} in rows
  end

  test "clamps an out-of-domain q and s in the panel" do
    params = %{Param.values(Rosette.params(), :default) | q: 2.0, s: 6}
    last = params |> Rosette.steps() |> Steps.run!(Rosette.initial(params)) |> List.last()
    assert {:both, _ops, rows} = Rosette.draw(last, params)

    assert {"q requested", "2.0"} in rows
    assert {"q clamped", "0.99"} in rows
    assert {"s requested", "6"} in rows
    assert {"s stored", "3"} in rows
  end

  test "draws the stable ray only when q is negative" do
    positive = %{Param.values(Rosette.params(), :default) | q: 0.5}
    negative = %{Param.values(Rosette.params(), :default) | q: -0.5}

    {:both, positive_ops, _} = draw_last(positive)
    {:both, negative_ops, _} = draw_last(negative)

    assert Enum.any?(negative_ops, &match?({:label, _, "stable ray", []}, &1))
    refute Enum.any?(positive_ops, &match?({:label, _, "stable ray", []}, &1))
  end

  test "frames an aspect-correct window centred on the origin" do
    params = Param.values(Rosette.params(), :default)
    radius = 1.25
    width = 2.0 * radius / 0.75
    viewport = Rosette.viewport(params)

    assert viewport.left == -radius / 0.75
    assert viewport.top == radius
    assert viewport.width == width
    assert viewport.scale == 1000.0 / width
  end

  defp draw_last(params) do
    params
    |> Rosette.steps()
    |> Steps.run!(Rosette.initial(params))
    |> List.last()
    |> Rosette.draw(params)
  end
end

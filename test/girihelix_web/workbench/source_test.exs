defmodule GirihelixWeb.Workbench.SourceTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Faces
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Source

  test "an engine step resolves to its file and call range" do
    step = hd(Faces.steps())

    assert {:ok, source} = Source.resolve(step)
    assert source.path == "lib/girihelix/engine/faces.ex"
    assert source.first == elem(step.source, 1)

    text =
      source.lines |> Enum.map(&elem(&1, 1)) |> Enum.slice((source.first - 1)..(source.last - 1))

    assert Enum.join(text, "\n") =~ "discover faces"
  end

  test "a multi-line step call resolves past its first line" do
    step = hd(PlanarMap.weld_steps())
    assert {:ok, source} = Source.resolve(step)
    assert source.last > source.first
  end

  test "nil, a missing file and a path outside lib are errors" do
    assert Source.resolve(nil) == {:error, :no_step}

    outside = %Steps.Step{
      id: :x,
      label: "x",
      doc: "x",
      run: & &1,
      source: {"reference/1.1.12/x.java", 1}
    }

    assert Source.resolve(outside) == {:error, :unavailable}

    missing = %Steps.Step{id: :x, label: "x", doc: "x", run: & &1, source: {"lib/nope.ex", 1}}
    assert Source.resolve(missing) == {:error, :unavailable}
  end
end

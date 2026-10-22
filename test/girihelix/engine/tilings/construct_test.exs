defmodule Girihelix.Engine.Tilings.ConstructTest do
  @moduledoc """
  The region a tiling fills, and the placement and binding steps that run over
  it.
  """

  use ExUnit.Case, async: true

  alias Girihelix.Engine.Figures.Rosette
  alias Girihelix.Engine.Geometry.Loose
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.Engine.Steps
  alias Girihelix.Engine.Tilings.Catalogue
  alias Girihelix.Engine.Tilings.Construct
  alias Girihelix.Engine.Tilings.Tiling

  test "default_region is the expanded bounding box, not the unit parallelogram" do
    tiling =
      Tiling.new(
        name: "t",
        t1: Point.new(2.0, 0.0),
        t2: Point.new(0.0, 2.0),
        features: [],
        placements: []
      )

    region = Construct.default_region(tiling)
    assert length(region) == 4

    margin = 0.01 * 2.0
    assert Loose.equals(Enum.at(region, 0), Point.new(-margin, -margin))
    assert Loose.equals(Enum.at(region, 2), Point.new(2.0 + margin, 2.0 + margin))
  end

  test "the :place step enumerates the cell translations" do
    tiling = Catalogue.load!("4.5")
    steps = Construct.steps(tiling, fn _ -> nil end, Construct.default_region(tiling))
    assert Enum.map(steps, & &1.id) == [:place, :bind, :units, :weld]

    state =
      steps
      |> Steps.run!(Construct.start(tiling, fn _ -> nil end, Construct.default_region(tiling)))
      |> Steps.final()

    assert state.translations != []
    assert Enum.all?(state.translations, &match?(%Transform{}, &1))
  end

  test "the :bind step keeps only non-nil bindings" do
    tiling = Catalogue.load!("4.5")
    binder = fn feature -> if feature.regular, do: Rosette.new!(feature.regular, 0.0, 3) end

    state =
      tiling
      |> Construct.steps(binder, Construct.default_region(tiling))
      |> Steps.run!(Construct.start(tiling, binder, Construct.default_region(tiling)))
      |> Steps.final()

    assert [{feature, %Rosette{}}] = state.bindings
    assert feature.regular == 4
  end
end

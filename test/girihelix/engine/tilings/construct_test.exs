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
  alias Girihelix.Engine.PlanarMap
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

  test "construct merges one feature per placement and the periodic copies, then welds" do
    tiling = Catalogue.load!("4.5")
    binder = fn feature -> if feature.regular, do: Rosette.new!(feature.regular, 0.0, 3) end

    assert {:ok, map} = Construct.construct(tiling, binder, Construct.default_region(tiling))
    assert PlanarMap.verify(map) == :ok
    assert PlanarMap.num_vertices(map) > 0
    assert PlanarMap.num_edges(map) > 0
  end

  test "the stepped and plain paths agree" do
    tiling = Catalogue.load!("4.5")
    binder = fn feature -> if feature.regular, do: Rosette.new!(feature.regular, 0.0, 3) end

    stepped =
      tiling
      |> Construct.steps(binder, Construct.default_region(tiling))
      |> Steps.run!(Construct.start(tiling, binder, Construct.default_region(tiling)))
      |> Steps.final()
      |> Construct.result()

    assert stepped == Construct.construct(tiling, binder, Construct.default_region(tiling))
  end

  test "a degenerate lattice is a tuple error" do
    tiling =
      Tiling.new(
        name: "bad",
        t1: Point.new(1.0, 0.0),
        t2: Point.new(2.0, 0.0),
        features: [],
        placements: []
      )

    assert Construct.construct(tiling, fn _ -> nil end, Construct.default_region(tiling)) ==
             {:error, :degenerate_basis}
  end

  # The fill counts its rows in lattice coordinates, so `default_region/1` —
  # one unit cell expanded by a 1% margin — never spans more than 1,000 of them,
  # however long the generators are. A region that really clears the cap is
  # passed directly.
  test "a region taller than the row cap is too_many_units" do
    tiling =
      Tiling.new(
        name: "tall",
        t1: Point.new(1.0, 0.0),
        t2: Point.new(0.0, 1.0),
        features: [],
        placements: []
      )

    region = [
      Point.new(-0.01, 0.0),
      Point.new(1.01, 0.0),
      Point.new(1.01, 1100.0),
      Point.new(-0.01, 1100.0)
    ]

    assert Construct.construct(tiling, fn _ -> nil end, region) == {:error, :too_many_units}
  end

  test "a raising binder is figure_failed, and the stepped path retains a failure frame" do
    tiling = Catalogue.load!("4.5")
    binder = fn _ -> raise ArgumentError, "star: degenerate_crossing" end

    assert {:error, {:figure_failed, %ArgumentError{}}} =
             Construct.construct(tiling, binder, Construct.default_region(tiling))

    assert {:error, %Steps.Failure{frames: frames}} =
             Steps.run(
               Construct.steps(tiling, binder, Construct.default_region(tiling)),
               Construct.start(tiling, binder, Construct.default_region(tiling))
             )

    assert frames != []
  end

  test "construct! raises the reason, or the wrapped exception of a raising binder" do
    degenerate =
      Tiling.new(
        name: "bad",
        t1: Point.new(1.0, 0.0),
        t2: Point.new(2.0, 0.0),
        features: [],
        placements: []
      )

    assert_raise ArgumentError, "construct: degenerate_basis", fn ->
      Construct.construct!(degenerate, fn _ -> nil end, Construct.default_region(degenerate))
    end

    tiling = Catalogue.load!("4.5")
    binder = fn _ -> raise ArgumentError, "star: degenerate_crossing" end

    assert_raise ArgumentError, "star: degenerate_crossing", fn ->
      Construct.construct!(tiling, binder, Construct.default_region(tiling))
    end
  end
end

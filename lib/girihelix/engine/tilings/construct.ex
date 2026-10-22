defmodule Girihelix.Engine.Tilings.Construct do
  @moduledoc """
  Places a tiling's tiles over a region and binds each tile to its figure.

  This is the value behind Taprats' tiling `construct` class: the region to fill
  is laid out in lattice coordinates, every feature of the tiling is sent through
  a binder — a function from feature to figure, or `nil` for "no figure" — and
  the result, after Task 6, is one welded planar map of the whole pattern.

  The algorithm is a `Girihelix.Engine.Steps` sequence over one `t:state/0`,
  with the same two entry points `FillRegion` has: a plain `start/3` + `result/1`
  pair and a `steps/3` sequence for the workbench.

  **The default region is the expanded bounding box of the unit cell.** A raw
  unit cell would put, say, a corner at `-1.0e-16` on tiling `4.5`, which floors
  to a spurious lattice row; expanding each side by `0.01` of the larger
  generator's length keeps the fill's inward rounding from inventing cells.

  **Short-circuit.** Once one step records a `:failure`, the later steps pass the
  state through unchanged, exactly as `FillRegion`'s steps do.
  """

  import Girihelix.Engine.Steps, only: [step: 4]

  alias Girihelix.Engine.Figures.Figure
  alias Girihelix.Engine.FillRegion
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Steps
  alias Girihelix.Engine.Tilings.Feature
  alias Girihelix.Engine.Tilings.Tiling

  @margin_factor 0.01

  @typedoc "A function from a tile to its figure, or `nil` for none."
  @type binder :: (Feature.t() -> Figure.t() | nil)

  @typedoc "A fill failure: what `FillRegion.fill/3` rejected the region for."
  @type reason :: FillRegion.reason()

  @typedoc """
  The state the steps run over.

  `translations` is the lattice's unit cells over the region, in
  `FillRegion`'s row-major order; `bindings` pairs each kept feature with the
  figure its binder returned; `feature_maps` and `map` stay empty until Task 6
  builds and welds them; `failure` is the first recorded fill failure.
  """
  @type state :: %{
          tiling: Tiling.t(),
          binder: binder(),
          region: [Point.t()],
          translations: [Transform.t()],
          bindings: [{Feature.t(), Figure.t()}],
          feature_maps: [PlanarMap.t()],
          map: nil | PlanarMap.t(),
          failure: nil | reason()
        }

  @doc """
  The four corners of the unit cell's bounding box, with `0.01` of the larger
  generator's length added to each side.

  The corners run counter-clockwise from the lower left, in perimeter order, as
  `FillRegion.fill/3` expects.
  """
  @spec default_region(Tiling.t()) :: [Point.t()]
  def default_region(%Tiling{t1: t1, t2: t2} = tiling) do
    corners = Tiling.unit_cell(tiling)
    margin = @margin_factor * max(Point.mag(t1), Point.mag(t2))
    xs = Enum.map(corners, & &1.x)
    ys = Enum.map(corners, & &1.y)

    box(
      Enum.min(xs) - margin,
      Enum.min(ys) - margin,
      Enum.max(xs) + margin,
      Enum.max(ys) + margin
    )
  end

  @doc "The state `steps/3` starts from."
  @spec start(Tiling.t(), binder(), [Point.t()]) :: state()
  def start(%Tiling{} = tiling, binder, region) do
    %{
      tiling: tiling,
      binder: binder,
      region: region,
      translations: [],
      bindings: [],
      feature_maps: [],
      map: nil,
      failure: nil
    }
  end

  @doc """
  The stages of the construction as a step sequence over a `t:state/0`: `:place`,
  `:bind`, `:units` and `:weld`.
  """
  @spec steps(Tiling.t(), binder(), [Point.t()]) :: [Steps.Step.t()]
  def steps(_tiling, _binder, _region) do
    [
      step(
        :place,
        "place the lattice units",
        "Fills the region with the lattice's unit cells, recording a fill failure.",
        &place/1
      ),
      step(
        :bind,
        "bind the figures",
        "Maps every feature through the binder and keeps the non-nil bindings.",
        &bind/1
      ),
      step(
        :units,
        "build the feature maps",
        "Placeholder until Task 6: passes the state through unchanged.",
        &pass/1
      ),
      step(
        :weld,
        "weld the feature maps",
        "Placeholder until Task 6: passes the state through unchanged.",
        &pass/1
      )
    ]
  end

  @doc """
  The outcome of a finished `t:state/0`: the welded map, or the recorded failure.

  Task 5's placeholder: an unwelded state reports `{:ok, nil}`. Task 6 welds
  `feature_maps` into `map` and returns it.
  """
  @spec result(state()) :: {:ok, PlanarMap.t() | nil} | {:error, reason()}
  def result(%{failure: nil}), do: {:ok, nil}
  def result(%{failure: reason}), do: {:error, reason}

  # -- place ------------------------------------------------------------------

  defp place(%{failure: reason} = state) when not is_nil(reason), do: state

  defp place(%{tiling: tiling, region: region} = state) do
    case FillRegion.fill(region, tiling.t1, tiling.t2) do
      {:ok, cells} -> %{state | translations: translate_cells(cells, tiling)}
      {:error, reason} -> %{state | failure: reason}
    end
  end

  defp translate_cells(cells, %Tiling{t1: t1, t2: t2}) do
    Enum.map(cells, fn {m, n} ->
      Transform.translate(m * t1.x + n * t2.x, m * t1.y + n * t2.y)
    end)
  end

  # -- bind -------------------------------------------------------------------

  defp bind(%{failure: reason} = state) when not is_nil(reason), do: state

  defp bind(%{tiling: tiling, binder: binder} = state) do
    %{
      state
      | bindings: Enum.flat_map(tiling.features, fn feature -> kept(binder.(feature), feature) end)
    }
  end

  defp kept(nil, _feature), do: []
  defp kept(figure, feature), do: [{feature, figure}]

  # -- Task 6 placeholders ------------------------------------------------------

  defp pass(state), do: state

  # -- region -----------------------------------------------------------------

  defp box(xmin, ymin, xmax, ymax) do
    [
      Point.new(xmin, ymin),
      Point.new(xmax, ymin),
      Point.new(xmax, ymax),
      Point.new(xmin, ymax)
    ]
  end
end

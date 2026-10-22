defmodule Girihelix.Engine.Tilings.Construct do
  @moduledoc """
  Places a tiling's tiles over a region and binds each tile to its figure.

  This is the value behind Taprats' tiling `construct` class: the region to fill
  is laid out in lattice coordinates, every feature of the tiling is sent through
  a binder — a function from feature to figure, or `nil` for "no figure" — and
  the result is one welded planar map of the whole pattern.

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

  @typedoc """
  A construction failure: what the place step's fill rejected the region for, an
  order the replicate or weld sorts could not honour, or a figure that raised.
  """
  @type reason ::
          FillRegion.reason() | :inconsistent_order | {:figure_failed, Exception.t()}

  @typedoc """
  The state the steps run over.

  `translations` is the lattice's unit cells over the region, in
  `FillRegion`'s row-major order; `bindings` pairs each kept feature with the
  figure its binder returned; `feature_maps` is one whole-feature map per bound
  feature, each replicated over its placements and the unit translations; `map`
  is the feature maps welded together, starting from an empty one; `failure` is
  the first recorded failure.
  """
  @type state :: %{
          tiling: Tiling.t(),
          binder: binder(),
          region: [Point.t()],
          translations: [Transform.t()],
          bindings: [{Feature.t(), Figure.t()}],
          feature_maps: [PlanarMap.t()],
          map: PlanarMap.t(),
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
      map: PlanarMap.new(),
      failure: nil
    }
  end

  @doc """
  The stages of the construction as a step sequence over a `t:state/0`: `:place`,
  `:bind`, `:units` and `:weld`.

  The three arguments name the construction, and the caller passes the same
  three to `start/3`: the steps themselves read the tiling, binder and region
  from the state `start/3` builds, never from these arguments, so one sequence
  pairs with one state. This is the workbench's entry point; `construct/3` runs
  it for the plain callers.
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
        "Merges each bound feature's figure over its placements, then the whole over the unit translations, recording an order the sorts could not honour.",
        &units/1
      ),
      step(
        :weld,
        "weld the feature maps",
        "Folds the weld over the feature maps, sewing crossings together and unifying shared vertices, recording an order the sorts could not honour.",
        &weld/1
      )
    ]
  end

  @doc """
  The outcome of a finished `t:state/0`: the welded map, or the recorded failure.
  """
  @spec result(state()) :: {:ok, PlanarMap.t()} | {:error, reason()}
  def result(%{failure: nil, map: map}), do: {:ok, map}
  def result(%{failure: reason}), do: {:error, reason}

  @doc """
  Constructs a tiling over a region with figures bound, in one call.

  Runs the `steps/3` sequence from `start/3` over the same three arguments. The
  welded map comes back as `{:ok, map}`, a recorded failure as
  `{:error, reason}`, and a figure that raised — through the binder, or building
  the figure's map — as `{:error, {:figure_failed, exception}}`.
  """
  @spec construct(Tiling.t(), binder(), [Point.t()]) :: {:ok, PlanarMap.t()} | {:error, reason()}
  def construct(%Tiling{} = tiling, binder, region) do
    case Steps.run(steps(tiling, binder, region), start(tiling, binder, region)) do
      {:ok, frames} -> frames |> Steps.final() |> result()
      {:error, %Steps.Failure{exception: exception}} -> {:error, {:figure_failed, exception}}
    end
  end

  @doc """
  As `construct/3`, but returns the bare map and raises: an `ArgumentError`
  naming a recorded reason, or the wrapped exception of a figure that raised.
  """
  @spec construct!(Tiling.t(), binder(), [Point.t()]) :: PlanarMap.t()
  def construct!(%Tiling{} = tiling, binder, region) do
    case construct(tiling, binder, region) do
      {:ok, map} -> map
      {:error, {:figure_failed, exception}} -> raise exception
      {:error, reason} -> raise ArgumentError, "construct: #{reason}"
    end
  end

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

  # -- units ------------------------------------------------------------------

  defp units(%{failure: reason} = state) when not is_nil(reason), do: state

  defp units(%{bindings: bindings} = state), do: Enum.reduce(bindings, state, &unit/2)

  defp unit(_binding, %{failure: reason} = state) when not is_nil(reason), do: state

  defp unit({feature, figure}, %{tiling: tiling, translations: translations, feature_maps: maps} = state) do
    case replicate_figure(tiling, {feature, figure}, translations) do
      {:ok, map} -> %{state | feature_maps: maps ++ [map]}
      {:error, reason} -> %{state | failure: reason}
    end
  end

  # Per bound feature, the figure's whole map is replicated over the feature's
  # placements into one unit map, and the unit map is then replicated over the
  # region's lattice translations into one whole-feature map.
  defp replicate_figure(tiling, {feature, figure}, translations) do
    with {:ok, unit} <-
           PlanarMap.replicate(
             PlanarMap.new(),
             Figure.map(figure),
             Tiling.placements_for(tiling, feature.id)
           ) do
      PlanarMap.replicate(PlanarMap.new(), unit, translations)
    end
  end

  # -- weld ---------------------------------------------------------------------

  defp weld(%{failure: reason} = state) when not is_nil(reason), do: state

  defp weld(%{feature_maps: maps} = state) do
    case weld_maps(maps) do
      {:ok, map} -> %{state | map: map}
      {:error, reason} -> %{state | failure: reason}
    end
  end

  defp weld_maps([]), do: {:ok, PlanarMap.new()}
  defp weld_maps([first | rest]), do: Enum.reduce(rest, {:ok, first}, &weld_into/2)

  defp weld_into({:ok, receiver}, other) do
    case PlanarMap.weld(receiver, other) do
      {:ok, {welded, _mapping}} -> {:ok, welded}
      {:error, reason} -> {:error, reason}
    end
  end

  defp weld_into({:error, _reason} = error, _other), do: error

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

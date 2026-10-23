defmodule GirihelixWeb.Workbench.Exhibits.Instancing do
  @moduledoc """
  One catalogue tiling instanced with a figure: the constructed pattern over the
  expanded unit cell.

  The tiling is one shipped `.tiling` file, filled over its expanded unit cell
  and bound figure-wise: every regular tile gets the chosen radial figure — a
  rosette, a star or none — and the construction welds the replicated figures
  into one planar map. Frame zero draws the static structure before any
  construction has run: the two translation vectors closed into the unit cell,
  every placed tile's outline. The `:place` frame adds a marker at every unit
  cell's origin; the welded pattern draws over the outlines once it exists.

  `Star.build!/3` is deliberately the unchecked constructor: a triangle tile,
  such as tiling `3-8-12`'s, builds a struct whose map raises at the closure,
  so the run is a failure frame, not a LiveView 500.

  The panel reports the tiling's own numbers — the shared `Tilings` rows — and
  the welded map's `vertices`, `edges` and `verify`. An empty map — frame zero,
  an unbound run, a failed figure — has nothing to verify, so those frames
  report `n/a` rather than a verdict on nothing.

  This is workbench code, not engine code: the construction is the `Construct`
  engine's step sequence, never a rebuild, and the picture draws op by op over
  the state `Construct.start/3` builds.

  The two figure binders are public because the exhibit's `reproduce/1` names
  one of them in the paste-able call it returns.
  """

  @behaviour GirihelixWeb.Workbench.Exhibit

  alias Girihelix.Engine.Figures.Rosette, as: RosetteFigure
  alias Girihelix.Engine.Figures.Star, as: StarFigure
  alias Girihelix.Engine.PlanarMap, as: EngineMap
  alias Girihelix.Engine.Steps
  alias Girihelix.Engine.Tilings.Catalogue, as: EngineCatalogue
  alias Girihelix.Engine.Tilings.Construct
  alias Girihelix.Engine.Tilings.Feature
  alias Girihelix.Engine.Tilings.Tiling, as: EngineTiling
  alias GirihelixWeb.Workbench.Exhibit
  alias GirihelixWeb.Workbench.Exhibits.Figures
  alias GirihelixWeb.Workbench.Exhibits.Tilings
  alias GirihelixWeb.Workbench.Param

  @impl true
  @spec slug() :: String.t()
  def slug, do: "instancing"

  @impl true
  @spec title() :: String.t()
  def title, do: "Instancing — one tiling, bound to a figure, welded into a pattern"

  @impl true
  @spec summary() :: String.t()
  def summary, do: "Every regular tile bound to a figure, replicated over the lattice, welded into one map."

  @impl true
  @spec category() :: atom()
  def category, do: :tilings

  @impl true
  @spec params() :: [Param.t()]
  def params do
    [
      %Param{
        name: :tiling,
        type: :enum,
        options: EngineCatalogue.name_options(),
        default: :"4.5",
        doc: "The shipped tiling to instance."
      },
      %Param{
        name: :figure,
        type: :enum,
        options: [:rosette, :star, :none],
        default: :rosette,
        doc: "The figure bound to every regular tile; `none` leaves every tile unbound."
      }
    ]
  end

  @impl true
  @spec initial(map()) :: Construct.state()
  def initial(%{tiling: name, figure: figure}) do
    tiling = load(name)
    Construct.start(tiling, binder(figure), Construct.default_region(tiling))
  end

  @impl true
  @spec steps(map()) :: [Steps.Step.t()]
  def steps(%{tiling: name, figure: figure}) do
    tiling = load(name)
    Construct.steps(tiling, binder(figure), Construct.default_region(tiling))
  end

  @impl true
  @spec draw(Steps.Frame.t(), map()) :: Exhibit.drawing()
  def draw(%Steps.Frame{state: state}, _params) do
    ops =
      Tilings.translation_ops(state.tiling) ++
        Tilings.cell_ops(state.translations) ++
        Tilings.outline_ops(state.tiling) ++
        Figures.map_ops(state.map)

    {:both, ops, Tilings.rows(state.tiling) ++ Figures.rows_for(pattern(state.map))}
  end

  @impl true
  @spec reproduce(map()) :: String.t()
  def reproduce(%{tiling: name, figure: figure}) do
    tiling = "Girihelix.Engine.Tilings.Catalogue.load!(" <> inspect(Atom.to_string(name)) <> ")"

    "Girihelix.Engine.Tilings.Construct.construct(" <>
      tiling <>
      ", " <>
      binder_call(figure) <>
      ", Girihelix.Engine.Tilings.Construct.default_region(" <> tiling <> "))"
  end

  # The catalogue is trusted local data: `load!/1` is the honest raise.
  @spec load(atom()) :: EngineTiling.t()
  defp load(name), do: EngineCatalogue.load!(name_string(name))

  defp name_string(name), do: Atom.to_string(name)

  # One binder per declared figure; workbench code, not engine code.
  defp binder(:none), do: &nil_binder/1
  defp binder(:rosette), do: &rosette_binder/1
  defp binder(:star), do: &star_binder/1

  # "No figure": every feature is placed, none is bound to one.
  defp nil_binder(_feature), do: nil

  @doc "The `:rosette` binder: every regular tile gets a rosette, the rest none."
  @spec rosette_binder(Feature.t()) :: RosetteFigure.t() | nil
  def rosette_binder(%Feature{regular: nil}), do: nil
  def rosette_binder(%Feature{regular: sides}), do: RosetteFigure.new!(sides, 0.0, 3)

  @doc """
  The `:star` binder: every regular tile gets a star, the rest none.

  `Star.build!/3` is deliberately the unchecked constructor, so a tiling with a
  triangle tile — `3-8-12` — fails in `:units`, when `Figure.map/1` raises at
  the star's closure, and the run is a failure frame.
  """
  @spec star_binder(Feature.t()) :: StarFigure.t() | nil
  def star_binder(%Feature{regular: nil}), do: nil
  def star_binder(%Feature{regular: sides}), do: StarFigure.build!(sides, 3.0, 2)

  defp binder_call(:none), do: "fn _feature -> nil end"
  defp binder_call(:rosette), do: "&GirihelixWeb.Workbench.Exhibits.Instancing.rosette_binder/1"
  defp binder_call(:star), do: "&GirihelixWeb.Workbench.Exhibits.Instancing.star_binder/1"

  # The welded pattern draws over the outlines; an empty map draws nothing.
  defp pattern(map), do: pattern(EngineMap.num_edges(map), map)

  defp pattern(0, _map), do: nil
  defp pattern(_edges, map), do: map
end

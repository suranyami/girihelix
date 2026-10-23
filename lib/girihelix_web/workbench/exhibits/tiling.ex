defmodule GirihelixWeb.Workbench.Exhibits.Tiling do
  @moduledoc """
  One tiling's structure, drawn and numbered: its vectors, unit cell, outlines.

  The tiling is one shipped `.tiling` file chosen from the catalogue. Frame zero
  draws the static structure before any construction has run: the two
  translation vectors `t1` and `t2` from the origin, closed into the unit-cell
  parallelogram, and every placed tile as a stroked outline. The single frame
  after the `:place` step — the construction is capped there — adds a small
  marker at every unit cell's origin, the lattice the fill laid out over the
  region.

  The panel reports the tiling's own numbers: its name, `t1`, `t2`, features,
  placements.

  This is a thin shell over the shared `Tilings` helper, which spells all of the
  ops and rows the `:tilings` exhibits draw. The helper reads the engine
  struct's public API — hence the `EngineTiling` alias, keeping the workbench
  module (this one) and the engine struct apart by name.

  This is workbench code, not engine code: the construction itself is the
  `Construct` engine's `:place` step over a `nil` binder, never a rebuild.
  """

  @behaviour GirihelixWeb.Workbench.Exhibit

  alias Girihelix.Engine.Steps
  alias Girihelix.Engine.Tilings.Catalogue, as: EngineCatalogue
  alias Girihelix.Engine.Tilings.Construct
  alias Girihelix.Engine.Tilings.Tiling, as: EngineTiling
  alias GirihelixWeb.Workbench.Exhibit
  alias GirihelixWeb.Workbench.Exhibits.Tilings
  alias GirihelixWeb.Workbench.Param

  @impl true
  @spec slug() :: String.t()
  def slug, do: "tiling"

  @impl true
  @spec title() :: String.t()
  def title, do: "Tiling"

  @impl true
  def byline, do: "one tiling's vectors, unit cell and outlines"
  @impl true
  @spec summary() :: String.t()
  def summary, do: "The two translation vectors closed into the unit cell, every placed tile outlined."

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
        doc: "The shipped tiling to draw."
      }
    ]
  end

  @impl true
  @spec initial(map()) :: Construct.state()
  def initial(%{tiling: name}) do
    tiling = load(name)
    Construct.start(tiling, &nil_binder/1, Construct.default_region(tiling))
  end

  @impl true
  @spec steps(map()) :: [Steps.Step.t()]
  def steps(%{tiling: name}) do
    tiling = load(name)
    tiling |> Construct.steps(&nil_binder/1, Construct.default_region(tiling)) |> Enum.take(1)
  end

  @impl true
  @spec draw(Steps.Frame.t(), map()) :: Exhibit.drawing()
  def draw(%Steps.Frame{state: state}, _params) do
    ops =
      Tilings.translation_ops(state.tiling) ++
        Tilings.cell_ops(state.translations) ++
        Tilings.outline_ops(state.tiling)

    {:both, ops, Tilings.rows(state.tiling)}
  end

  @impl true
  @spec reproduce(map()) :: String.t()
  def reproduce(%{tiling: name}) do
    tiling = "Girihelix.Engine.Tilings.Catalogue.load!(" <> inspect(Atom.to_string(name)) <> ")"

    "Girihelix.Engine.Tilings.Construct.construct!(" <>
      tiling <>
      ", fn _feature -> nil end, " <>
      "Girihelix.Engine.Tilings.Construct.default_region(" <> tiling <> "))"
  end

  # The catalogue is trusted local data: `load!/1` is the honest raise.
  @spec load(atom()) :: EngineTiling.t()
  defp load(name), do: EngineCatalogue.load!(name_string(name))

  defp name_string(name), do: Atom.to_string(name)

  # "No figure": every feature is placed, none is bound to one.
  defp nil_binder(_feature), do: nil
end

defmodule GirihelixWeb.Workbench.Exhibits.Catalogue do
  @moduledoc """
  The whole shipped catalogue as a table: one row per `.tiling` file.

  Every shipped tiling parses, so the default panel is one row per name in
  index order with its tile counts. A file that failed to parse keeps its
  failure as its row rather than being dropped, so the panel shows what the
  engine can and cannot load — the panel is live engine data, the same
  `Catalogue.all/0` anything else would call. Frame zero has loaded nothing
  yet, so it shows one honest placeholder row rather than an empty table.

  This is a `{:panel, rows}` exhibit: no canvas ops. The structure exhibits —
  `Tiling` and `Instancing` (later tasks) — draw the tiling's geometry over
  in the `:tilings` category.
  """

  @behaviour GirihelixWeb.Workbench.Exhibit

  import Girihelix.Engine.Steps, only: [step: 4]

  alias Girihelix.Engine.Steps
  alias Girihelix.Engine.Tilings.Catalogue, as: EngineCatalogue
  alias Girihelix.Engine.Tilings.Tiling
  alias GirihelixWeb.Workbench.Exhibit
  alias GirihelixWeb.Workbench.Param

  @impl true
  @spec slug() :: String.t()
  def slug, do: "catalogue"

  @impl true
  @spec title() :: String.t()
  def title, do: "Catalogue — every shipped tiling"

  @impl true
  def summary, do: "One row per shipped tiling: its tile and placement counts."

  @impl true
  def category, do: :tilings

  @impl true
  @spec params() :: [Param.t()]
  def params, do: []

  @impl true
  @spec initial(map()) :: [{String.t(), String.t()}]
  def initial(_params), do: []

  @impl true
  @spec steps(map()) :: [Steps.Step.t()]
  def steps(_params) do
    [
      step(
        :load,
        "load the catalogue",
        "Parses every shipped .tiling file, keeping failures as rows.",
        fn _ ->
          Enum.map(EngineCatalogue.all(), &row/1)
        end
      )
    ]
  end

  @impl true
  @spec draw(Steps.Frame.t(), map()) :: Exhibit.drawing()
  def draw(%Steps.Frame{state: rows}, _params) do
    {:panel, panel_rows(rows)}
  end

  @impl true
  @spec reproduce(map()) :: String.t()
  def reproduce(_params), do: "Girihelix.Engine.Tilings.Catalogue.all()"

  @doc "The row one catalogue entry becomes: `{name, counts}`."
  @spec row({String.t(), {:ok, Tiling.t()} | {:error, term()}}) :: {String.t(), String.t()}
  def row({name, {:ok, tiling}}), do: {name, counts(tiling)}
  def row({name, {:error, reason}}), do: {name, "cannot parse: #{inspect(reason)}"}

  # Frame zero (and a failed `:load` run's retained frame) has loaded nothing
  # yet: one honest placeholder row, never an empty table.
  defp panel_rows([]), do: [{"catalogue", "not loaded"}]

  defp panel_rows(rows), do: rows

  defp counts(tiling), do: "#{length(tiling.features)} features, #{length(tiling.placements)} placements"
end

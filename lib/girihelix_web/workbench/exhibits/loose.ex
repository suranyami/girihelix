defmodule GirihelixWeb.Workbench.Exhibits.Loose do
  @moduledoc """
  The tolerance surface as a table: two constants and three predicates.

  Nothing here is geometric, so the exhibit draws a panel rather than a canvas.
  Its rows are computed by calling `Girihelix.Engine.Geometry.Loose` — they are
  not transcribed numbers — which is what makes the table a live statement about
  the engine rather than a comment that can drift.

  The last row is the one to read twice. `near/3` compares its tolerance against
  a **squared** distance, so a `1.0e-10` tolerance admits two points `1.0e-6`
  apart: their squared distance is `1.0e-12`, below the threshold. That squared
  tolerance is an effective linear radius of `sqrt(1.0e-10) = 1.0e-5`. Passed to
  `near/2`, the same number is a linear tolerance of `1.0e-10`, a factor of
  `1.0e5` stricter.
  """

  @behaviour GirihelixWeb.Workbench.Exhibit

  import Girihelix.Engine.Steps, only: [step: 4]

  alias Girihelix.Engine.Geometry.Loose, as: Tolerance
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibit
  alias GirihelixWeb.Workbench.Param

  @origin Point.new(0.0, 0.0)
  @one_micrometre Point.new(1.0e-6, 0.0)

  @impl true
  @spec slug() :: String.t()
  def slug, do: "loose"

  @impl true
  @spec title() :: String.t()
  def title, do: "Loose — the tolerance surface"

  @impl true
  @spec summary() :: String.t()
  def summary, do: "Two tolerances, and the squared-distance trap between them."

  @impl true
  @spec category() :: atom()
  def category, do: :geometry

  @impl true
  @spec params() :: [Param.t()]
  def params, do: []

  @impl true
  @spec initial(map()) :: map()
  def initial(_params), do: %{}

  @impl true
  @spec steps(map()) :: [Steps.Step.t()]
  def steps(_params) do
    [
      step(
        :build,
        "Read the parameters",
        "No computation happens here; draw/2 computes the table from the engine.",
        & &1
      )
    ]
  end

  @impl true
  @spec draw(Steps.Frame.t(), map()) :: Exhibit.drawing()
  def draw(_frame, _params), do: {:panel, rows()}

  @impl true
  @spec reproduce(map()) :: String.t()
  def reproduce(_params), do: "GirihelixWeb.Workbench.Exhibits.Loose.rows()"

  @doc "The five tolerance rows, the values `draw/2` puts in the panel."
  @spec rows() :: [{String.t(), String.t()}]
  def rows do
    [
      {"tol/0", to_string(Tolerance.tol())},
      {"tol2/0", to_string(Tolerance.tol2())},
      {"equals(1.0, 1.0 + 1.0e-8)", to_string(Tolerance.equals(1.0, 1.0 + 1.0e-8))},
      {"near(1.0e-8, 1.0e-7)", to_string(Tolerance.near(1.0e-8, 1.0e-7))},
      {
        "near two points 1.0e-6 apart, tolerance 1.0e-10",
        to_string(Tolerance.near(@origin, @one_micrometre, Tolerance.tol2()))
      }
    ]
  end
end

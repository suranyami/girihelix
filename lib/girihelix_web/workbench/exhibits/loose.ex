defmodule GirihelixWeb.Workbench.Exhibits.Loose do
  @moduledoc """
  The tolerance surface as a table: two constants and three predicates.

  Nothing here is geometric, so the exhibit draws a panel rather than a canvas.
  Its rows are computed by calling `Girihelix.Engine.Geometry.Loose` — they are
  not transcribed numbers — which is what makes the table a live statement about
  the engine rather than a comment that can drift.

  The last row is the one to read twice. `near/3` compares its tolerance against
  a **squared** distance, so a `1.0e-10` tolerance admits two points `1.0e-6`
  apart: their squared distance is `1.0e-12`, below the threshold. Passed to
  `near/2`, the same number would be a linear tolerance a hundred times stricter.
  """

  @behaviour GirihelixWeb.Workbench.Exhibit

  import Girihelix.Engine.Steps, only: [step: 4]

  alias Girihelix.Engine.Geometry.Loose, as: Tolerance
  alias Girihelix.Engine.Geometry.Point

  @origin Point.new(0.0, 0.0)
  @one_micrometre Point.new(1.0e-6, 0.0)

  @impl true
  def slug, do: "loose"

  @impl true
  def title, do: "Loose — the tolerance surface"

  @impl true
  def summary, do: "Two tolerances, and the squared-distance trap between them."

  @impl true
  def category, do: :geometry

  @impl true
  def params, do: []

  @impl true
  def initial(_params), do: %{}

  @impl true
  def steps(_params) do
    [
      step(
        :build,
        "Compute the tolerance table",
        "Calls each Loose predicate once, at the values the table names.",
        & &1
      )
    ]
  end

  @impl true
  def draw(_frame, _params), do: {:panel, rows()}

  @impl true
  def reproduce(_params) do
    "Girihelix.Engine.Geometry.Loose.near(" <>
      "Point.new(0.0, 0.0), Point.new(1.0e-6, 0.0), 1.0e-10)"
  end

  defp rows do
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

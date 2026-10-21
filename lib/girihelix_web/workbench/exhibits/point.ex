defmodule GirihelixWeb.Workbench.Exhibits.Point do
  @moduledoc """
  A point read as a vector: position, magnitude, direction and quarter turn.

  The picture is the vector from the origin to `(x, y)`, with the origin as a
  small marker and the point itself as a larger one. The rows are computed by
  calling `Girihelix.Engine.Geometry.Point` — they are not transcribed numbers —
  so the table always states what the engine returns for the parameters shown.

  `perp/1` is the counter-clockwise quarter turn, `(x, y) -> (-y, x)`, not a
  clockwise one. At the defaults `(3.0, 4.0)` it is `(-4.0, 3.0)`.
  """

  @behaviour GirihelixWeb.Workbench.Exhibit

  import Girihelix.Engine.Steps, only: [step: 4]

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibit
  alias GirihelixWeb.Workbench.Exhibits.Format
  alias GirihelixWeb.Workbench.Param

  # SVG units, not map units: a marker keeps its screen size as the viewport
  # changes, so these are never projected.
  @origin_radius 0.15
  @point_radius 0.25

  @impl true
  @spec slug() :: String.t()
  def slug, do: "point"

  @impl true
  @spec title() :: String.t()
  def title, do: "Point — position as a vector"

  @impl true
  @spec summary() :: String.t()
  def summary, do: "A point's coordinates, magnitude, angle and quarter turn."

  @impl true
  @spec category() :: atom()
  def category, do: :geometry

  @impl true
  @spec params() :: [Param.t()]
  def params do
    [
      %Param{
        name: :x,
        type: :float,
        range: -5..5,
        step: 0.1,
        default: 3.0,
        doc: "The point's x coordinate."
      },
      %Param{
        name: :y,
        type: :float,
        range: -5..5,
        step: 0.1,
        default: 4.0,
        doc: "The point's y coordinate."
      }
    ]
  end

  @impl true
  @spec initial(map()) :: map()
  def initial(params), do: params

  @impl true
  @spec steps(map()) :: [Steps.Step.t()]
  def steps(_params) do
    [
      step(
        :build,
        "Read the point",
        "Takes (x, y) from the parameters; the measures are read when drawing.",
        & &1
      )
    ]
  end

  @impl true
  @spec draw(Steps.Frame.t(), map()) :: Exhibit.drawing()
  def draw(_frame, params) do
    %Point{x: x, y: y} = point = point(params)
    origin = Point.origin()

    ops = [
      {:point, {origin.x, origin.y}, @origin_radius, []},
      {:line, {origin.x, origin.y}, {x, y}, []},
      {:point, {x, y}, @point_radius, []}
    ]

    {:both, ops, rows(point)}
  end

  @impl true
  @spec reproduce(map()) :: String.t()
  def reproduce(params) do
    %Point{x: x, y: y} = point(params)
    "Girihelix.Engine.Geometry.Point.new(#{Format.coordinate(x)}, #{Format.coordinate(y)})"
  end

  defp point(%{x: x, y: y}), do: Point.new(x, y)

  defp rows(%Point{} = point) do
    %Point{x: perp_x, y: perp_y} = Point.perp(point)

    [
      {"x", Format.coordinate(point.x)},
      {"y", Format.coordinate(point.y)},
      {"mag", Format.coordinate(Point.mag(point))},
      {"mag2", Format.coordinate(Point.mag2(point))},
      {"angle", Format.coordinate(Point.angle(point))},
      {"perp", "#{Format.coordinate(perp_x)}, #{Format.coordinate(perp_y)}"}
    ]
  end
end

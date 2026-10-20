defmodule GirihelixWeb.Workbench.Exhibits.Polygon do
  @moduledoc """
  A closed polygon read three ways: its vertices, its area and path length, and
  whether a probe point lies inside it.

  The shape is the unit square, the unit triangle, or a five-point star centred
  at `(0.5, 0.5)` with outer radius `0.5` and inner radius `0.2`. The star's ten
  vertices start at angle zero and alternate outer and inner, so the first is
  `(1.0, 0.5)`.

  Every row is computed by calling `Girihelix.Engine.Geometry.Polygon` — they
  are not transcribed numbers. The area is the shoelace area with its sign
  discarded, and the arc length is the **closed** path: the implicit edge from
  the last vertex back to the first is included. At the defaults the unit square
  has four vertices, area `1.0`, arc length `4.0`, and its centre `(0.5, 0.5)`
  is inside it.

  Containment is the even-odd test behind `Polygon.contains_point?/2`, which
  classifies a probe exactly **on** a boundary asymmetrically: the lower and left
  edges of the unit square count as inside while the upper and right edges do
  not. The probe marker is drawn wherever the parameters put it, inside or not.
  """

  @behaviour GirihelixWeb.Workbench.Exhibit

  import Girihelix.Engine.Steps, only: [step: 4]

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Polygon
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibit
  alias GirihelixWeb.Workbench.Param

  # SVG units, not map units: a marker keeps its screen size as the viewport
  # changes, so these are never projected.
  @vertex_radius 0.2
  @probe_radius 0.3

  @square [
    Point.new(0.0, 0.0),
    Point.new(1.0, 0.0),
    Point.new(1.0, 1.0),
    Point.new(0.0, 1.0)
  ]

  @triangle [Point.new(0.0, 0.0), Point.new(1.0, 0.0), Point.new(0.0, 1.0)]

  @centre_x 0.5
  @centre_y 0.5
  @outer_radius 0.5
  @inner_radius 0.2
  @star_vertices 10
  # The angle between consecutive star vertices: 2*pi/10.
  @star_angle :math.pi() / 5

  @impl true
  @spec slug() :: String.t()
  def slug, do: "polygon"

  @impl true
  @spec title() :: String.t()
  def title, do: "Polygon — vertices, area and containment"

  @impl true
  @spec summary() :: String.t()
  def summary, do: "A square, triangle or star with its area, closed path and probe."

  @impl true
  @spec category() :: atom()
  def category, do: :geometry

  @impl true
  @spec params() :: [Param.t()]
  def params do
    [
      %Param{
        name: :shape,
        type: :enum,
        options: [:square, :triangle, :star],
        default: :square,
        doc: "The polygon to measure."
      },
      probe(:probe_x, "The probe's x coordinate."),
      probe(:probe_y, "The probe's y coordinate.")
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
        "Build the polygon and probe",
        "Polygon.new!/1 builds the shape; the probe is the point to test for containment.",
        &build/1
      )
    ]
  end

  @impl true
  @spec draw(Steps.Frame.t(), map()) :: Exhibit.drawing()
  def draw(%Steps.Frame{state: %{polygon: polygon, probe: probe}}, _params) do
    {:both, ops(polygon, probe), rows(polygon, probe)}
  end

  # Frame zero has only the parameters: the polygon is built from them here so
  # the initial frame is drawable like every later one.
  def draw(%Steps.Frame{state: params}, _params) do
    %{polygon: polygon, probe: probe} = build(params)
    {:both, ops(polygon, probe), rows(polygon, probe)}
  end

  @impl true
  @spec reproduce(map()) :: String.t()
  def reproduce(params) do
    "Girihelix.Engine.Geometry.Polygon.new!([" <>
      Enum.map_join(points(params), ", ", &point_call/1) <> "])"
  end

  defp probe(name, doc) do
    %Param{name: name, type: :float, range: -2..2, step: 0.1, default: 0.5, doc: doc}
  end

  defp build(params) do
    %{polygon: Polygon.new!(points(params)), probe: Point.new(params.probe_x, params.probe_y)}
  end

  defp points(%{shape: :square}), do: @square
  defp points(%{shape: :triangle}), do: @triangle
  defp points(%{shape: :star}), do: star_points()

  defp star_points do
    for index <- 0..(@star_vertices - 1) do
      angle = index * @star_angle
      radius = star_radius(index)

      Point.new(
        @centre_x + radius * :math.cos(angle),
        @centre_y + radius * :math.sin(angle)
      )
    end
  end

  # The vertices alternate outer and inner, beginning with an outer one at
  # angle zero.
  defp star_radius(index) when rem(index, 2) == 0, do: @outer_radius
  defp star_radius(_index), do: @inner_radius

  defp ops(polygon, probe) do
    points = Polygon.points(polygon)

    [{:polygon, Enum.map(points, &pair/1), :fill, [fill: "currentColor", opacity: 0.15]}] ++
      Enum.map(points, &{:point, pair(&1), @vertex_radius, []}) ++
      [{:point, pair(probe), @probe_radius, []}]
  end

  defp rows(polygon, probe) do
    [
      {"vertices", Integer.to_string(Polygon.num_vertices(polygon))},
      {"area", coordinate(Polygon.area(polygon))},
      {"arc length", coordinate(Polygon.arc_length(polygon, true))},
      {"contains probe", to_string(Polygon.contains_point?(polygon, probe))}
    ]
  end

  defp point_call(%Point{x: x, y: y}) do
    "Girihelix.Engine.Geometry.Point.new(#{coordinate(x)}, #{coordinate(y)})"
  end

  defp pair(%Point{x: x, y: y}), do: {x, y}

  # Every measure and coordinate reads as a float: `1.0`, never `1`.
  defp coordinate(value), do: value |> Kernel.*(1.0) |> to_string()
end

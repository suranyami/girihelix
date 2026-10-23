defmodule GirihelixWeb.Workbench.Exhibits.Intersect do
  @moduledoc """
  Two segments and the crossing of the lines through them.

  The picture draws each segment as a line with its endpoints marked, and the
  crossing as a larger marker when there is one. Three rows state what
  `Girihelix.Engine.Geometry.Intersect` returns: the parameter pair `{s, t}`
  along the two segments, the position `get_intersection/2` reports, and the
  position `get_true_intersection/2` reports, which drops a crossing that lands
  at the ends of **both** segments.

  The parameter pair is filtered by `stay_on_segments/1`, so it is nil exactly
  when the crossing is off one of the segments; all three rows then say "none".
  At the defaults the first segment runs from `(0.0, 0.0)` to `(4.0, 0.0)` and
  the second from `(1.0, -2.0)` to `(1.0, 2.0)`, so they cross at `(1.0, 0.0)`
  with parameters `{0.25, 0.5}`.

  Coincident endpoints are a failure state, not a crash. The build step calls
  `Segment.new!/2`, which raises `ArgumentError`; `Steps.run/3` turns that into a
  `Steps.Failure`, and frame zero still draws the input coordinates.
  """

  @behaviour GirihelixWeb.Workbench.Exhibit

  import Girihelix.Engine.Steps, only: [step: 4]

  alias Girihelix.Engine.Geometry.Intersect
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Segment
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibit
  alias GirihelixWeb.Workbench.Exhibits.Format
  alias GirihelixWeb.Workbench.Param

  # SVG units, not map units: a marker keeps its screen size as the viewport
  # changes, so these are never projected.
  @endpoint_radius 6.0
  @crossing_radius 9.0

  @impl true
  @spec slug() :: String.t()
  def slug, do: "intersect"

  @impl true
  @spec title() :: String.t()
  def title, do: "Intersect"

  @impl true
  def byline, do: "where two segments cross"
  @impl true
  @spec summary() :: String.t()
  def summary, do: "Two segments, their parameter pair and the crossing of their lines."

  @impl true
  @spec category() :: atom()
  def category, do: :geometry

  @impl true
  @spec params() :: [Param.t()]
  def params do
    [
      axis(:x1, 0.0, "The first segment's start x."),
      axis(:y1, 0.0, "The first segment's start y."),
      axis(:x2, 4.0, "The first segment's end x."),
      axis(:y2, 0.0, "The first segment's end y."),
      axis(:x3, 1.0, "The second segment's start x."),
      axis(:y3, -2.0, "The second segment's start y."),
      axis(:x4, 1.0, "The second segment's end x."),
      axis(:y4, 2.0, "The second segment's end y.")
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
        "Build the segments and cross them",
        "Segment.new!/2 builds both segments; Intersect returns the parameters and positions.",
        &build/1
      )
    ]
  end

  @impl true
  @spec draw(Steps.Frame.t(), map()) :: Exhibit.drawing()
  def draw(%Steps.Frame{state: %{first: _first} = built}, _params) do
    {:both, built_ops(built), built_rows(built)}
  end

  def draw(%Steps.Frame{state: params}, _params) do
    {:both, input_ops(params), unbuilt_rows()}
  end

  @impl true
  @spec reproduce(map()) :: String.t()
  def reproduce(%{x1: x1, y1: y1, x2: x2, y2: y2, x3: x3, y3: y3, x4: x4, y4: y4}) do
    "{:ok, first} = " <>
      segment_call({x1, y1}, {x2, y2}) <>
      "\n{:ok, second} = " <>
      segment_call({x3, y3}, {x4, y4}) <>
      "\nGirihelix.Engine.Geometry.Intersect.get_intersection(first, second)"
  end

  defp axis(name, default, doc) do
    %Param{name: name, type: :float, range: -5..5, step: 0.1, default: default, doc: doc}
  end

  defp build(params) do
    first = Segment.new!(Point.new(params.x1, params.y1), Point.new(params.x2, params.y2))
    second = Segment.new!(Point.new(params.x3, params.y3), Point.new(params.x4, params.y4))

    %{
      first: first,
      second: second,
      params: first |> Intersect.get_intersection_params(second) |> Intersect.stay_on_segments(),
      intersection: Intersect.get_intersection(first, second),
      true_intersection: Intersect.get_true_intersection(first, second)
    }
  end

  # The built state carries the segments, so the crossing is read, not rebuilt.
  defp built_ops(%{first: first, second: second} = built) do
    [
      {:line, Format.pair(Segment.from(first)), Format.pair(Segment.to(first)), []},
      {:line, Format.pair(Segment.from(second)), Format.pair(Segment.to(second)), []}
    ] ++
      endpoint_ops([
        Segment.from(first),
        Segment.to(first),
        Segment.from(second),
        Segment.to(second)
      ]) ++
      crossing_ops(built.intersection)
  end

  # Frame zero has only the parameters: the segments are drawn from the inputs
  # without building them, so a coincident pair is still drawable.
  defp input_ops(params) do
    points =
      Enum.map(
        [
          {params.x1, params.y1},
          {params.x2, params.y2},
          {params.x3, params.y3},
          {params.x4, params.y4}
        ],
        fn {x, y} -> Point.new(x, y) end
      )

    [from_first, to_first, from_second, to_second] = points

    [
      {:line, Format.pair(from_first), Format.pair(to_first), []},
      {:line, Format.pair(from_second), Format.pair(to_second), []}
    ] ++ endpoint_ops(points)
  end

  defp endpoint_ops(points), do: Enum.map(points, &{:point, Format.pair(&1), @endpoint_radius, []})

  defp crossing_ops(nil), do: []
  defp crossing_ops(%Point{} = point), do: [{:point, Format.pair(point), @crossing_radius, []}]

  defp built_rows(%{params: params, intersection: intersection, true_intersection: true_intersection}) do
    [
      {"params", format_params(params)},
      {"intersection", format_point(intersection)},
      {"true intersection", format_point(true_intersection)}
    ]
  end

  defp unbuilt_rows do
    [
      {"params", "none"},
      {"intersection", "none"},
      {"true intersection", "none"}
    ]
  end

  defp format_params(nil), do: "none"
  defp format_params({s, t}), do: "{#{Format.coordinate(s)}, #{Format.coordinate(t)}}"

  defp format_point(nil), do: "none"
  defp format_point(%Point{x: x, y: y}), do: "#{Format.coordinate(x)}, #{Format.coordinate(y)}"

  defp segment_call(from, to) do
    "Girihelix.Engine.Geometry.Segment.new(#{point_call(from)}, #{point_call(to)})"
  end

  defp point_call({x, y}) do
    "Girihelix.Engine.Geometry.Point.new(#{Format.coordinate(x)}, #{Format.coordinate(y)})"
  end
end

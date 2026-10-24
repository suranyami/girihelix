defmodule GirihelixWeb.Workbench.Exhibits.PlanarMap do
  @moduledoc """
  Two maps welded where their edges cross, or one short spoke copied six times.

  `:weld_squares` is the receiver unit square `(0, 0)…(1, 1)` and a second unit
  square offset by `(0.5, 0.5)`. Its four steps find the two crossings, split
  both maps there, unify the coincident vertices, and copy the other map's
  edges into the receiver. The picture draws the receiver's edges as lines, its
  vertices as small markers, the other map's edges as guides, and every crossing
  as a larger marker.

  `:replicate_ladder` starts from an empty receiver and copies the open spoke
  `(0, 0), (1, 0), (1.5, 0.3)` under six rotations at multiples of `pi/3`, then
  sorts the appended edges. The replicate state carries no other map, so the
  unit being copied is rebuilt from the parameters and drawn as guides; that
  also keeps frame zero, whose receiver is empty, drawable.

  The viewport is pinned rather than fitted. The receiver grows from four
  vertices and four edges to ten and twelve as the weld runs, and a fitted
  viewport would zoom out frame by frame; the pin keeps the squares fixed in the
  canvas. Both scenarios stay inside `(-2.0, -2.0)…(2.0, 2.0)`.

  The panel's `crossings` row is the number of crossing markers found, and its
  `verify` row is `Girihelix.Engine.PlanarMap.verify/1` for the receiver:
  `"ok"` when the map is sound, otherwise the problems it reports.
  """

  @behaviour GirihelixWeb.Workbench.Exhibit

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Viewport
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibit
  alias GirihelixWeb.Workbench.Exhibits.Format
  alias GirihelixWeb.Workbench.Param

  # SVG units, not map units: a marker keeps its screen size as the viewport
  # changes, so these are never projected.
  @vertex_radius 6.0
  @crossing_radius 9.0

  @square_points [{0.0, 0.0}, {1.0, 0.0}, {1.0, 1.0}, {0.0, 1.0}]
  @spoke_points [{0.0, 0.0}, {1.0, 0.0}, {1.5, 0.3}]

  @rotations 6
  # The angle between consecutive copies: 2*pi/6.
  @rotation_angle :math.pi() / 3.0

  @viewport_bounds {-2.0, -2.0, 2.0, 2.0}

  @impl true
  @spec slug() :: String.t()
  def slug, do: "map"

  @impl true
  @spec title() :: String.t()
  def title, do: "PlanarMap"

  @impl true
  def byline, do: "welding and replication"
  @impl true
  @spec summary() :: String.t()
  def summary, do: "Two squares welded at their crossings, or one spoke copied six times."

  @impl true
  @spec category() :: atom()
  def category, do: :geometry

  @impl true
  @spec params() :: [Param.t()]
  def params do
    [
      %Param{
        name: :scenario,
        type: :enum,
        options: [:weld_squares, :replicate_ladder],
        default: :weld_squares,
        doc: "The operation to show: weld two squares, or replicate a spoke."
      }
    ]
  end

  @doc """
  The pair of maps a scenario runs on.

  The first element is the receiver. The second is the map the operation
  consumes: the other map to weld, or the unit to replicate. Both scenarios have
  a second map, so the `nil` the type permits is unused.
  """
  @spec scenario(:weld_squares | :replicate_ladder) :: {PlanarMap.t(), PlanarMap.t() | nil}
  def scenario(:weld_squares), do: {square(0.0, 0.0), square(0.5, 0.5)}
  def scenario(:replicate_ladder), do: {PlanarMap.new(), spoke()}

  @impl true
  @spec initial(map()) :: PlanarMap.weld_state() | PlanarMap.replicate_state()
  def initial(%{scenario: :weld_squares}) do
    {receiver, other} = scenario(:weld_squares)
    PlanarMap.weld_start(receiver, other)
  end

  def initial(%{scenario: :replicate_ladder}) do
    {receiver, _unit} = scenario(:replicate_ladder)
    PlanarMap.replicate_start(receiver)
  end

  @impl true
  @spec steps(map()) :: [Steps.Step.t()]
  def steps(%{scenario: :weld_squares}), do: PlanarMap.weld_steps()

  def steps(%{scenario: :replicate_ladder}) do
    {_receiver, unit} = scenario(:replicate_ladder)
    PlanarMap.replicate_steps(unit, rotations())
  end

  @impl true
  @spec viewport(map(), [Steps.Frame.t()]) :: Viewport.t()
  def viewport(_params, _frames), do: Viewport.fit(@viewport_bounds, padding: 0.0)

  @impl true
  @spec draw(Steps.Frame.t(), map()) :: Exhibit.drawing()
  def draw(%Steps.Frame{state: %{other: other, crossings: crossings} = state}, _params) do
    {:both, weld_ops(state, other, crossings), weld_rows(state, crossings)}
  end

  # The replicate state has no other map. The unit is rebuilt from the
  # parameters so frame zero, whose receiver is empty, still has a picture.
  def draw(%Steps.Frame{state: %{receiver: receiver}}, params) do
    {:both, replicate_ops(receiver, params), replicate_rows(receiver)}
  end

  @doc """
  The finished map a scenario builds.

  Unlike `scenario/1`, which returns the inputs, this runs the same steps the
  exhibit shows and returns the receiver the operation leaves behind.
  """
  @spec result(:weld_squares | :replicate_ladder) :: PlanarMap.t()
  def result(:weld_squares) do
    {receiver, other} = scenario(:weld_squares)
    receiver |> PlanarMap.weld!(other) |> elem(0)
  end

  def result(:replicate_ladder) do
    {receiver, unit} = scenario(:replicate_ladder)
    PlanarMap.replicate!(receiver, unit, rotations())
  end

  @impl true
  @spec reproduce(map()) :: String.t()
  def reproduce(%{scenario: scenario}) do
    "GirihelixWeb.Workbench.Exhibits.PlanarMap.result(#{inspect(scenario)})"
  end

  defp weld_ops(%{receiver: receiver}, other, crossings) do
    edge_ops(receiver) ++ vertex_ops(receiver) ++ guide_ops(other) ++ crossing_ops(crossings)
  end

  defp replicate_ops(receiver, params) do
    {_receiver, unit} = scenario(params.scenario)
    edge_ops(receiver) ++ vertex_ops(receiver) ++ guide_ops(unit)
  end

  defp edge_ops(map), do: Enum.map(PlanarMap.edges(map), &edge_op(map, &1, :line))
  defp guide_ops(map), do: Enum.map(PlanarMap.edges(map), &edge_op(map, &1, :guide))

  defp edge_op(map, edge, tag) do
    {v1, v2} = PlanarMap.endpoints!(map, edge)

    {tag, Format.pair(PlanarMap.position!(map, v1)), Format.pair(PlanarMap.position!(map, v2)), []}
  end

  defp vertex_ops(map) do
    Enum.map(PlanarMap.vertices(map), fn vertex ->
      {:point, Format.pair(PlanarMap.position!(map, vertex)), @vertex_radius, []}
    end)
  end

  defp crossing_ops(crossings) do
    Enum.map(crossings, &{:point, Format.pair(&1), @crossing_radius, []})
  end

  defp weld_rows(%{receiver: receiver}, crossings) do
    [
      {"receiver vertices", Integer.to_string(PlanarMap.num_vertices(receiver))},
      {"receiver edges", Integer.to_string(PlanarMap.num_edges(receiver))},
      {"crossings", Integer.to_string(length(crossings))},
      verify_row(receiver)
    ]
  end

  defp replicate_rows(receiver) do
    [
      {"receiver vertices", Integer.to_string(PlanarMap.num_vertices(receiver))},
      {"receiver edges", Integer.to_string(PlanarMap.num_edges(receiver))},
      {"crossings", "0"},
      verify_row(receiver)
    ]
  end

  defp verify_row(map) do
    case PlanarMap.verify(map) do
      :ok -> {"verify", "ok"}
      {:error, problems} -> {"verify", Enum.map_join(problems, ", ", &inspect/1)}
    end
  end

  defp square(dx, dy) do
    {vertices, map} =
      Enum.map_reduce(@square_points, PlanarMap.new(), fn {x, y}, map ->
        insert(Point.new(x + dx, y + dy), map)
      end)

    closed_edges(map, vertices)
  end

  defp spoke do
    {vertices, map} =
      Enum.map_reduce(@spoke_points, PlanarMap.new(), fn {x, y}, map ->
        insert(Point.new(x, y), map)
      end)

    open_edges(map, vertices)
  end

  defp insert(%Point{} = point, map) do
    {map, vertex} = PlanarMap.insert_vertex(map, point)
    {vertex, map}
  end

  defp closed_edges(map, [first | _] = vertices), do: open_edges(map, vertices ++ [first])

  defp open_edges(map, vertices) do
    vertices
    |> Enum.zip(Enum.drop(vertices, 1))
    |> Enum.reduce(map, fn {v1, v2}, map -> PlanarMap.insert_edge!(map, v1, v2) end)
  end

  defp rotations do
    Enum.map(0..(@rotations - 1), &Transform.rotate(&1 * @rotation_angle))
  end
end

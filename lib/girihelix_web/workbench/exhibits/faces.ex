defmodule GirihelixWeb.Workbench.Exhibits.Faces do
  @moduledoc """
  Discover a planar map's faces and two-colour them so neighbours differ.

  Each scenario is one of the Plan 1c golden maps, built vertex by vertex and
  edge by edge: a pair of parallel edges split by a midpoint, a triangle with a
  dangling edge, a figure eight, two vertices joined twice, a square with its
  diagonal, and a 3×3 grid. The split and grid maps show that building order
  matters: the midpoint is inserted **after** the parallel edges, and the grid
  is laid out row by row, because `PlanarMap.insert_vertex/2` splits at most one
  edge and discovery follows edge order.

  The picture draws every edge as a line, marks the two colours differently once
  the colour step has assigned them, and marks every discovered face's corners.
  Black faces are filled in `currentColor` at 0.4 opacity; white faces are a
  dashed `currentColor` stroke, so both colours stay visible in the light and
  dark themes. Discovery registers the rejected clockwise outer contour too, so
  its corners are marked even though it is never drawn as a face.

  A map that cannot be two-coloured is reported, not raised. The colour step
  records `:filling_conflict` or `:no_faces` in the frame's state, so the run
  still completes and the panel's `failure` row names the reason. The square
  with a diagonal and the 3×3 grid both show the conflict; frame zero and every
  intermediate frame draw from the state as it stands, including a failed one.
  """

  @behaviour GirihelixWeb.Workbench.Exhibit

  alias Girihelix.Engine.Faces, as: FaceColouring
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibit
  alias GirihelixWeb.Workbench.Exhibits.Format
  alias GirihelixWeb.Workbench.Param

  # SVG units, not map units: a marker keeps its screen size as the viewport
  # changes, so these are never projected.
  @vertex_radius 0.15

  @split_points [{0.0, 0.0}, {2.0, 0.0}]
  @split_midpoint {1.0, 0.0}

  @dangling_points [{0.0, 0.0}, {2.0, 0.0}, {1.0, 2.0}, {3.0, 2.0}]

  @figure_eight_points [
    {0.0, 0.0},
    {2.0, 0.0},
    {2.0, 2.0},
    {0.0, 2.0},
    {-2.0, 0.0},
    {-2.0, -2.0},
    {0.0, -2.0}
  ]

  @two_corner_points [{0.0, 0.0}, {2.0, 0.0}]

  @square_points [{0.0, 0.0}, {4.0, 0.0}, {4.0, 3.0}, {0.0, 3.0}]

  @grid_side 4

  @impl true
  @spec slug() :: String.t()
  def slug, do: "faces"

  @impl true
  @spec title() :: String.t()
  def title, do: "Faces — discovering and two-colouring a planar map"

  @impl true
  @spec summary() :: String.t()
  def summary, do: "A planar map's faces, coloured so faces sharing an edge differ."

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
        options: [:split_parallel, :dangling, :figure_eight, :two_corner, :square_diagonal, :grid],
        default: :split_parallel,
        doc: "The planar map to discover faces in."
      }
    ]
  end

  @doc """
  The planar map a scenario runs on.

  The maps are the Plan 1c golden scenarios, so the exhibit shows the same maps
  the engine's golden tests pin.
  """
  @spec scenario(
          :split_parallel
          | :dangling
          | :figure_eight
          | :two_corner
          | :square_diagonal
          | :grid
        ) :: PlanarMap.t()
  def scenario(:split_parallel) do
    {[a, b], map} = insert_all(@split_points)

    map
    |> PlanarMap.insert_edge!(a, b)
    |> PlanarMap.insert_edge!(a, b)
    |> split_at(@split_midpoint)
  end

  def scenario(:dangling) do
    {[a, b, c, d], map} = insert_all(@dangling_points)
    connect(map, [{a, b}, {b, c}, {c, a}, {c, d}])
  end

  def scenario(:figure_eight) do
    {[a, b, c, d, e, f, g], map} = insert_all(@figure_eight_points)

    connect(map, [{a, b}, {b, c}, {c, d}, {d, a}, {a, e}, {e, f}, {f, g}, {g, a}])
  end

  def scenario(:two_corner) do
    {[a, b], map} = insert_all(@two_corner_points)
    connect(map, [{a, b}, {a, b}])
  end

  def scenario(:square_diagonal) do
    {[a, b, c, d], map} = insert_all(@square_points)
    connect(map, [{a, b}, {b, c}, {c, d}, {d, a}, {a, c}])
  end

  def scenario(:grid) do
    {vertices, map} = insert_all(grid_points())
    connect(map, grid_edges(vertices))
  end

  @impl true
  @spec initial(map()) :: FaceColouring.state()
  def initial(%{scenario: scenario}), do: FaceColouring.start(scenario(scenario))

  @impl true
  @spec steps(map()) :: [Steps.Step.t()]
  def steps(_params), do: FaceColouring.steps()

  @impl true
  @spec draw(Steps.Frame.t(), map()) :: Exhibit.drawing()
  def draw(%Steps.Frame{state: state}, _params) do
    {:both, ops(state), rows(state)}
  end

  @impl true
  @spec reproduce(map()) :: String.t()
  def reproduce(%{scenario: scenario}) do
    "Girihelix.Engine.Faces.extract_faces(" <>
      "GirihelixWeb.Workbench.Exhibits.Faces.scenario(#{inspect(scenario)}))"
  end

  defp insert_all(points) do
    Enum.map_reduce(points, PlanarMap.new(), fn {x, y}, map ->
      {map, vertex} = PlanarMap.insert_vertex(map, Point.new(x, y))
      {vertex, map}
    end)
  end

  # Only the split matters here: the midpoint has no handle the scenario uses.
  defp split_at(map, {x, y}) do
    {map, _vertex} = PlanarMap.insert_vertex(map, Point.new(x, y))
    map
  end

  defp connect(map, edges) do
    Enum.reduce(edges, map, fn {v1, v2}, map -> PlanarMap.insert_edge!(map, v1, v2) end)
  end

  # The golden 4×4 vertex grid is laid out row by row, and its edges run along
  # each row first and then down each column.
  defp grid_points do
    for y <- 0..(@grid_side - 1), x <- 0..(@grid_side - 1), do: {x * 1.0, y * 1.0}
  end

  defp grid_edges(vertices) do
    horizontal =
      for y <- 0..(@grid_side - 1),
          x <- 0..(@grid_side - 2),
          do: {at(vertices, y, x), at(vertices, y, x + 1)}

    vertical =
      for y <- 0..(@grid_side - 2),
          x <- 0..(@grid_side - 1),
          do: {at(vertices, y, x), at(vertices, y + 1, x)}

    horizontal ++ vertical
  end

  defp at(vertices, row, column) do
    Enum.at(vertices, row * @grid_side + column)
  end

  defp ops(%{map: map, infos: infos, order: order}) do
    edge_ops(map) ++ fill_ops(map, infos, order) ++ vertex_ops(map, infos)
  end

  defp edge_ops(map) do
    Enum.map(PlanarMap.edges(map), fn edge ->
      {v1, v2} = PlanarMap.endpoints!(map, edge)

      {:line, Format.pair(PlanarMap.position!(map, v1)), Format.pair(PlanarMap.position!(map, v2)), []}
    end)
  end

  defp fill_ops(map, infos, order) do
    order
    |> Enum.map(&fill_op(map, infos[&1]))
    |> Enum.reject(&is_nil/1)
  end

  defp fill_op(map, %{vertices: vertices, state: :black}) do
    polygon_op(map, vertices, :fill, fill: "currentColor", opacity: 0.4)
  end

  defp fill_op(map, %{vertices: vertices, state: :white}) do
    polygon_op(map, vertices, :stroke, stroke: "currentColor", width: 1.5, dash: "4 3")
  end

  defp fill_op(_map, _info), do: nil

  defp polygon_op(map, vertices, mode, opts) do
    points = Enum.map(vertices, &Format.pair(PlanarMap.position!(map, &1)))
    {:polygon, points, mode, opts}
  end

  # Every discovered face is marked, including the rejected outer contour: the
  # map's corners are what discovery walked, whether or not the face is kept.
  defp vertex_ops(map, infos) do
    infos
    |> Enum.sort()
    |> Enum.flat_map(fn {_id, info} ->
      Enum.map(info.vertices, fn vertex ->
        {:point, Format.pair(PlanarMap.position!(map, vertex)), @vertex_radius, []}
      end)
    end)
  end

  defp rows(%{infos: infos, order: order, failure: failure}) do
    [
      {"discovered", Integer.to_string(map_size(infos))},
      {"kept", Integer.to_string(length(order))},
      {"black", Integer.to_string(count_colour(infos, order, :black))},
      {"white", Integer.to_string(count_colour(infos, order, :white))},
      {"failure", failure_name(failure)}
    ]
  end

  defp count_colour(infos, order, :black) do
    Enum.count(order, &match?(%{state: :black}, infos[&1]))
  end

  defp count_colour(infos, order, :white) do
    Enum.count(order, &match?(%{state: :white}, infos[&1]))
  end

  defp failure_name(nil), do: "none"
  defp failure_name(reason), do: Atom.to_string(reason)
end

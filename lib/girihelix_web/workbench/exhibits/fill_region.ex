defmodule GirihelixWeb.Workbench.Exhibits.FillRegion do
  @moduledoc """
  Fill a quadrilateral region with the lattice's unit cells.

  The region is the axis-aligned rectangle `(0, 0)…(width, height)`. Two
  translation vectors `T1` and `T2` span the lattice, and the fill finds every
  integer pair whose point `t1 * T1 + t2 * T2` names a cell over the region.

  The picture draws the region as a stroked polygon, both translation vectors
  from the origin as guides, and every scanned row's outermost `x` extent as a
  guide mapped through the basis. Only the final frame fills cells:
  `:change_basis` and `:find_rows` leave the row map empty, so before the scan
  the picture shows the region and the vectors but no rows; the `:scan_rows`
  frame adds every row extent and its cells. Each filled cell is the
  parallelogram `origin`, `origin + T1`, `origin + T1 + T2`, `origin + T2`.

  Two failures are reported, not raised. Parallel translation vectors record
  `:degenerate_basis` in the `:change_basis` step, and a region spanning more
  than 1,000 lattice rows records `:too_many_units` in `:find_rows`. The
  remaining steps pass a failed state through, and the panel's `failure` row
  names the reason. Such a run draws the region and the vectors but no rows and
  no cells.
  """

  @behaviour GirihelixWeb.Workbench.Exhibit

  alias Girihelix.Engine.FillRegion, as: RegionFill
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibit
  alias GirihelixWeb.Workbench.Exhibits.Format
  alias GirihelixWeb.Workbench.Param

  @impl true
  @spec slug() :: String.t()
  def slug, do: "fill-region"

  @impl true
  @spec title() :: String.t()
  def title, do: "FillRegion"

  @impl true
  def byline, do: "tiling a region with lattice translates"
  @impl true
  @spec summary() :: String.t()
  def summary, do: "A rectangle scanned row by row and filled with lattice cells."

  @impl true
  @spec category() :: atom()
  def category, do: :geometry

  @impl true
  @spec params() :: [Param.t()]
  def params do
    [
      %Param{
        name: :width,
        type: :float,
        range: 1..10,
        step: 0.5,
        default: 4.0,
        doc: "The region's width."
      },
      %Param{
        name: :height,
        type: :float,
        range: 1..10,
        step: 0.5,
        default: 3.0,
        doc: "The region's height."
      },
      vector_param(:t1x, 1.0, "The first translation vector's x component."),
      vector_param(:t1y, 0.0, "The first translation vector's y component."),
      vector_param(:t2x, 0.0, "The second translation vector's x component."),
      vector_param(:t2y, 1.0, "The second translation vector's y component.")
    ]
  end

  @impl true
  @spec initial(map()) :: RegionFill.state()
  def initial(%{t1x: t1x, t1y: t1y, t2x: t2x, t2y: t2y} = params) do
    RegionFill.start(region(params), Point.new(t1x, t1y), Point.new(t2x, t2y))
  end

  @impl true
  @spec steps(map()) :: [Steps.Step.t()]
  def steps(_params), do: RegionFill.steps()

  @impl true
  @spec draw(Steps.Frame.t(), map()) :: Exhibit.drawing()
  def draw(%Steps.Frame{state: state} = frame, _params) do
    cells = cell_ops(frame)
    {:both, ops(state, cells), rows(state, length(cells))}
  end

  @impl true
  @spec reproduce(map()) :: String.t()
  def reproduce(params) do
    t1 = Point.new(params.t1x, params.t1y)
    t2 = Point.new(params.t2x, params.t2y)

    "Girihelix.Engine.FillRegion.fill([" <>
      Enum.map_join(region(params), ", ", &point_call/1) <>
      "], " <> point_call(t1) <> ", " <> point_call(t2) <> ")"
  end

  defp vector_param(name, default, doc) do
    %Param{name: name, type: :float, range: -2..2, step: 0.1, default: default, doc: doc}
  end

  defp region(%{width: width, height: height}) do
    [
      Point.new(0.0, 0.0),
      Point.new(width, 0.0),
      Point.new(width, height),
      Point.new(0.0, height)
    ]
  end

  defp ops(state, cells) do
    region_op(state) ++
      translation_ops(state) ++
      row_ops(state) ++
      cells
  end

  defp region_op(%{region: region}) do
    [
      {:polygon, Enum.map(region, &Format.pair/1), :stroke, [width: 1.5]},
      {:label, region |> Enum.at(3) |> Format.pair(), "region", []}
    ]
  end

  defp translation_ops(%{t1: t1, t2: t2}) do
    origin = Point.new(0.0, 0.0)

    List.flatten([
      {:guide, {0.0, 0.0}, Format.pair(t1), [width: 2.0]},
      arrow_ops(origin, t1, "T1"),
      {:guide, {0.0, 0.0}, Format.pair(t2), [width: 2.0]},
      arrow_ops(origin, t2, "T2")
    ])
  end

  # The arrowhead is sized from the vector itself, so it reads at any viewport
  # scale without the exhibit knowing the serializer's scale. A zero vector
  # degenerates to a point-sized head and still labels the origin.
  defp arrow_ops(from, to, label) do
    direction = Point.subtract(to, from)
    head = 0.18 * Point.mag(direction)
    unit = Point.normalize(direction)
    base = Point.subtract(to, Point.scale(unit, head))
    side = Point.scale(Point.perp(unit), head * 0.5)

    [
      {:polygon, Enum.map([to, Point.add(base, side), Point.subtract(base, side)], &Format.pair/1), :fill,
       [fill: "currentColor"]},
      {:label, to |> Point.add(Point.scale(unit, head * 0.6)) |> Format.pair(), label, []}
    ]
  end

  # The row map holds lattice-space extents, so each guide is mapped through
  # the basis: the world points are `x * T1 + y * T2`.
  defp row_ops(%{iymin: nil}), do: []

  defp row_ops(%{iymin: iymin, rows: rows, t1: t1, t2: t2}) do
    rows
    |> Enum.sort()
    |> Enum.flat_map(fn {offset, {xmin, xmax}} ->
      y = iymin + offset
      from = lattice_point(xmin, y, t1, t2)
      to = lattice_point(xmax, y, t1, t2)
      middle = midpoint(from, to)

      [
        {:guide, from, to, [width: 2.0]},
        {:label, middle, row_label(y, xmin, xmax), []}
      ]
    end)
  end

  defp midpoint({ax, ay}, {bx, by}), do: {(ax + bx) / 2.0, (ay + by) / 2.0}

  defp row_label(y, xmin, xmax) do
    "row #{y}: x #{Format.coordinate(xmin)} .. #{Format.coordinate(xmax)}"
  end

  # Cells exist only once the scan has completed without a failure.
  defp cell_ops(%Steps.Frame{step: %Steps.Step{id: :scan_rows}, state: %{failure: nil} = state}) do
    {:ok, cells} = RegionFill.result(state)
    Enum.map(cells, &cell_op(&1, state))
  end

  defp cell_ops(_frame), do: []

  defp cell_op({i, j}, %{t1: t1, t2: t2}) do
    origin = Point.new(i * t1.x + j * t2.x, i * t1.y + j * t2.y)
    along_t1 = Point.new(origin.x + t1.x, origin.y + t1.y)
    far = Point.new(along_t1.x + t2.x, along_t1.y + t2.y)
    along_t2 = Point.new(origin.x + t2.x, origin.y + t2.y)

    {:polygon, Enum.map([origin, along_t1, far, along_t2], &Format.pair/1), :fill,
     [fill: "currentColor", stroke: "currentColor", width: 0.75, opacity: 0.3]}
  end

  defp rows(state, cell_count) do
    [
      {"rows", Integer.to_string(map_size(state.rows))},
      {"cells", Integer.to_string(cell_count)},
      {"failure", failure_name(state.failure)},
      {"shading", "unit cells"},
      {"bars", "each row's outermost x extent"},
      {"arrows", "T1 and T2"}
    ]
  end

  defp failure_name(nil), do: "none"
  defp failure_name(reason), do: Atom.to_string(reason)

  defp point_call(%Point{x: x, y: y}) do
    "Girihelix.Engine.Geometry.Point.new(#{Format.coordinate(x)}, #{Format.coordinate(y)})"
  end

  defp lattice_point(x, y, %Point{} = t1, %Point{} = t2) do
    Format.pair(Point.new(x * t1.x + y * t2.x, x * t1.y + y * t2.y))
  end
end

defmodule GirihelixWeb.Workbench.Exhibits.FillRegion do
  @moduledoc """
  Fill a quadrilateral region with the lattice's unit cells.

  The region is the axis-aligned rectangle `(0, 0)…(width, height)`. Two
  translation vectors `T1` and `T2` span the lattice, and the fill finds every
  integer pair whose point `t1 * T1 + t2 * T2` names a cell over the region.

  The picture draws the region as a stroked polygon, both translation vectors
  from the origin as guides, and every scanned row's outermost `x` extent as a
  horizontal guide. Only the last frame fills cells: `:change_basis` and
  `:find_rows` leave the row map empty, so the scan is visible as it is built.
  Each filled cell is the parallelogram `origin`, `origin + T1`,
  `origin + T1 + T2`, `origin + T2`.

  A degenerate basis — parallel translation vectors — is reported, not raised.
  The `:change_basis` step records `:degenerate_basis`, the remaining steps pass
  the state through, and the panel's `failure` row names the reason. Such a run
  draws the region and the vectors but no rows and no cells.
  """

  @behaviour GirihelixWeb.Workbench.Exhibit

  alias Girihelix.Engine.FillRegion, as: RegionFill
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibit
  alias GirihelixWeb.Workbench.Param

  @impl true
  @spec slug() :: String.t()
  def slug, do: "fill-region"

  @impl true
  @spec title() :: String.t()
  def title, do: "FillRegion — tiling a region with lattice translates"

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
    [region_op(state)] ++
      translation_ops(state) ++
      row_ops(state) ++
      cells
  end

  defp region_op(%{region: region}) do
    {:polygon, Enum.map(region, &pair/1), :stroke, []}
  end

  defp translation_ops(%{t1: t1, t2: t2}) do
    [
      {:guide, {0.0, 0.0}, pair(t1), []},
      {:guide, {0.0, 0.0}, pair(t2), []}
    ]
  end

  # `iymin` is nil until `:find_rows` has run, so frame zero has no row guides
  # even though its row map is empty anyway.
  defp row_ops(%{iymin: nil}), do: []

  defp row_ops(%{iymin: iymin, rows: rows}) do
    rows
    |> Enum.sort()
    |> Enum.map(fn {offset, {xmin, xmax}} ->
      y = 1.0 * (iymin + offset)
      {:guide, {xmin, y}, {xmax, y}, []}
    end)
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

    {:polygon, Enum.map([origin, along_t1, far, along_t2], &pair/1), :fill, [fill: "currentColor", opacity: 0.15]}
  end

  defp rows(state, cell_count) do
    [
      {"rows", Integer.to_string(map_size(state.rows))},
      {"cells", Integer.to_string(cell_count)},
      {"failure", failure_name(state.failure)}
    ]
  end

  defp failure_name(nil), do: "none"
  defp failure_name(reason), do: Atom.to_string(reason)

  defp point_call(%Point{x: x, y: y}) do
    "Girihelix.Engine.Geometry.Point.new(#{coordinate(x)}, #{coordinate(y)})"
  end

  defp pair(%Point{x: x, y: y}), do: {x, y}

  # Every coordinate reads as a float: `1.0`, never `1`.
  defp coordinate(value), do: value |> Kernel.*(1.0) |> to_string()
end

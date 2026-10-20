defmodule Girihelix.Engine.FillRegion do
  @moduledoc """
  Finds every lattice translate whose unit cell lands over a quadrilateral
  region.

  The region is given as four points in world coordinates, and `t1` and `t2` are
  the translation vectors of the lattice. The result is a list of integer pairs
  `{t1, t2}` in the lattice's own coordinates, each naming the point
  `t1 * T1 + t2 * T2`: emitting them paints a unit at every such point.

  The work is a basis change and a scanline fill. The basis change is the
  inverse of the matrix whose columns are the translation vectors, so a world
  point becomes its lattice coordinates. The fill then finds, per integer row,
  the region's outermost x extent and emits every integer x from `floor(xmin)`
  to `floor(xmax)` inclusive.

  ## Deliberate bounds

  **The fill can leave gaps along the region's edges.** It tracks only a row's
  outermost extent, and rounds both ends inward with `floor`, so a cell that
  only partly overlaps the region can be omitted. The prescribed workaround is
  to expand the region before filling; that belongs to the caller.

  **At most 1,000 rows are filled.** A region spanning more than 1,000 integer
  rows returns `{:error, :too_many_units}`.

  Parallel translation vectors have no basis change; they return
  `{:error, :degenerate_basis}`. The test is exact equality with a zero
  determinant, so nearly parallel vectors produce very large coordinates
  instead of failing.

  Horizontality is the exact test `fy == ty`; there is no tolerance.
  """

  import Girihelix.Engine.Steps, only: [step: 4]

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Steps

  @max_row_gap 999

  @typedoc "A lattice translate, in the coordinates of the translation vectors."
  @type cell :: {integer(), integer()}

  @type reason :: :degenerate_basis | :too_many_units

  @typedoc """
  The state the fill's steps run over. `basis` is the four scalars of the
  inverse matrix, `points` the region in lattice coordinates, and `rows` maps a
  row's offset to its `{xmin, xmax}` extent.
  """
  @type state :: %{
          region: [Point.t()],
          t1: Point.t(),
          t2: Point.t(),
          basis: nil | [float()],
          points: [Point.t()],
          iymin: nil | integer(),
          iymax: nil | integer(),
          rows: %{integer() => {float(), float()}},
          failure: nil | reason()
        }

  @doc """
  Fills `region` with lattice translates of `t1` and `t2`, in emission order.
  """
  @spec fill([Point.t()], Point.t(), Point.t()) ::
          {:ok, [cell()]} | {:error, reason()}
  def fill([%Point{} = p1, %Point{} = p2, %Point{} = p3, %Point{} = p4], %Point{} = t1, %Point{} = t2) do
    steps()
    |> Steps.run!(start([p1, p2, p3, p4], t1, t2))
    |> Steps.final()
    |> result()
  end

  @doc "As `fill/3`, but returns the cells and raises `ArgumentError` naming the reason."
  @spec fill!([Point.t()], Point.t(), Point.t()) :: [cell()]
  def fill!(region, t1, t2), do: region |> fill(t1, t2) |> unwrap!()

  @doc "The state `fill/3` starts from."
  @spec start([Point.t()], Point.t(), Point.t()) :: state()
  def start([%Point{} = p1, %Point{} = p2, %Point{} = p3, %Point{} = p4], %Point{} = t1, %Point{} = t2) do
    %{
      region: [p1, p2, p3, p4],
      t1: t1,
      t2: t2,
      basis: nil,
      points: [p1, p2, p3, p4],
      iymin: nil,
      iymax: nil,
      rows: %{},
      failure: nil
    }
  end

  @doc """
  The stages of `fill/3` as a step sequence over a `t:state/0`: `:change_basis`,
  `:find_rows` and `:scan_rows`.
  """
  @spec steps() :: [Steps.Step.t()]
  def steps do
    [
      step(
        :change_basis,
        "change basis",
        "Maps the four region corners into the lattice coordinates, recording a degenerate basis.",
        &change_basis/1
      ),
      step(
        :find_rows,
        "find rows",
        "Finds the integer row range and records a region taller than the cap.",
        &find_rows/1
      ),
      step(
        :scan_rows,
        "scan rows",
        "Walks the four edges, recording each row's outermost x extent.",
        &scan_rows/1
      )
    ]
  end

  @doc "The outcome of a finished `t:state/0`: the cells, or the recorded failure."
  @spec result(state()) :: {:ok, [cell()]} | {:error, reason()}
  def result(%{failure: nil} = state), do: {:ok, cells(state)}
  def result(%{failure: reason}), do: {:error, reason}

  # -- change basis -----------------------------------------------------------

  defp change_basis(%{failure: reason} = state) when not is_nil(reason), do: state

  defp change_basis(%{t1: t1, t2: t2, region: region} = state) do
    det = t1.x * t2.y - t2.x * t1.y
    basis_change(state, det, t1, t2, region)
  end

  defp basis_change(state, det, _t1, _t2, _region) when det == 0.0, do: %{state | failure: :degenerate_basis}

  defp basis_change(state, det, t1, t2, region) do
    scale = 1.0 / det
    matrix = [t2.y * scale, -t2.x * scale, -t1.y * scale, t1.x * scale]

    %{state | basis: matrix, points: Enum.map(region, &apply_basis(matrix, &1))}
  end

  defp apply_basis([a, b, c, d], %Point{x: x, y: y}), do: Point.new(a * x + b * y, c * x + d * y)

  # -- find rows --------------------------------------------------------------

  defp find_rows(%{failure: reason} = state) when not is_nil(reason), do: state

  defp find_rows(%{points: points} = state) do
    ys = Enum.map(points, & &1.y)
    iymin = ys |> Enum.min() |> Float.floor() |> trunc()
    iymax = ys |> Enum.max() |> Float.floor() |> trunc()

    cap_rows(%{state | iymin: iymin, iymax: iymax}, iymax - iymin)
  end

  defp cap_rows(state, gap) when gap > @max_row_gap, do: %{state | failure: :too_many_units}
  defp cap_rows(state, _gap), do: state

  # -- scan rows --------------------------------------------------------------

  defp scan_rows(%{failure: reason} = state) when not is_nil(reason), do: state

  defp scan_rows(%{points: [p1, p2, p3, p4], iymin: iymin} = state) do
    rows =
      [p1, p2, p3, p4]
      |> Enum.zip([p2, p3, p4, p1])
      |> Enum.reduce(%{}, fn {from, to}, rows -> scan_edge(from, to, rows, iymin) end)

    %{state | rows: rows}
  end

  defp scan_edge(%Point{x: fx, y: fy}, %Point{x: tx, y: ty}, rows, iymin) when fy == ty do
    add_extent(rows, floor_int(fy) - iymin, [fx, tx])
  end

  defp scan_edge(%Point{} = from, %Point{} = to, rows, iymin) do
    {fx, fy, tx, ty} = lower_first(from, to)
    slope = (tx - fx) / (ty - fy)
    y = Float.floor(fy)
    x = fx + (y - fy) * slope

    y
    |> trunc()
    |> walk_rows(floor_int(ty), x, y, slope, {fx, fy, tx, ty})
    |> Enum.reduce(rows, fn {iy, xs}, rows -> add_extent(rows, iy - iymin, xs) end)
  end

  defp lower_first(%Point{x: fx, y: fy}, %Point{x: tx, y: ty}) when fy > ty, do: {tx, ty, fx, fy}

  defp lower_first(%Point{x: fx, y: fy}, %Point{x: tx, y: ty}), do: {fx, fy, tx, ty}

  # The running x is accumulated one row at a time, not evaluated as
  # `x0 + k * slope`: the two differ in the last bits, and the result is
  # floored, so the accumulation is the faithful one.
  defp walk_rows(iy, iym, x, y, slope, {fx, fy, tx, ty}) do
    {rows, _last} =
      Enum.map_reduce(iy..iym, {x, y}, fn i, {x, y} ->
        nx = x + slope
        ny = y + 1.0
        lower = lower_value(y, fy, fx, x)
        upper = upper_value(ny, ty, tx, nx)
        {{i, [lower, upper]}, {nx, ny}}
      end)

    rows
  end

  defp lower_value(y, fy, fx, _x) when y <= fy, do: fx
  defp lower_value(_y, _fy, _fx, x), do: x

  defp upper_value(ny, ty, tx, _nx) when ny > ty, do: tx
  defp upper_value(_ny, _ty, _tx, nx), do: nx

  defp add_extent(rows, offs, xs) do
    Map.update(rows, offs, extent(xs), &merge_extent(&1, xs))
  end

  defp extent(xs), do: {Enum.min(xs), Enum.max(xs)}

  defp merge_extent({lo, hi}, xs), do: {min(lo, Enum.min(xs)), max(hi, Enum.max(xs))}

  # -- output -----------------------------------------------------------------

  defp cells(%{iymin: iymin, iymax: iymax, rows: rows}) do
    Enum.flat_map(iymin..iymax, fn iy -> row_cells(rows, iy - iymin, iy) end)
  end

  defp row_cells(rows, offs, iy) do
    case Map.fetch(rows, offs) do
      :error -> []
      {:ok, {xmin, xmax}} -> span_cells(floor_int(xmin), floor_int(xmax), iy)
    end
  end

  defp span_cells(startx, endx, _iy) when startx > endx, do: []
  defp span_cells(startx, endx, iy), do: Enum.map(startx..endx, &{&1, iy})

  defp floor_int(value), do: value |> Float.floor() |> trunc()

  defp unwrap!({:ok, cells}), do: cells
  defp unwrap!({:error, reason}), do: raise(ArgumentError, "fill region: #{reason}")
end

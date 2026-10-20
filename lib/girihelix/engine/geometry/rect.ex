defmodule Girihelix.Engine.Geometry.Rect do
  @moduledoc """
  An axis-aligned rectangle in a **y-down** frame: `(x, y)` is the top-left
  corner, `right = x + width`, and `bottom = y - height`.

  The convention comes from screen coordinates and is kept throughout: `top/1`
  is the larger y, `bottom/1` the smaller, and the y axis of `union/2` and
  `intersection/2` swaps the usual min/max sense. A rectangle's four numbers are
  accepted as they stand — nothing validates a sign, so a negative width is an
  inside-out rectangle rather than an error.

  `intersection/2` is the one operation that can fail: the rectangles are
  `:disjoint` exactly when the overlap would have negative extent. Merely
  touching rectangles return a zero-extent rectangle, not an error.

  ## Degenerate sizes

  `center_inside/2` divides by both of the inner rectangle's dimensions, so each
  must be non-zero. A zero extent raises `ArithmeticError` there; no other
  operation divides.
  """

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Transform

  @enforce_keys [:x, :y, :width, :height]
  defstruct [:x, :y, :width, :height]

  @type t :: %__MODULE__{x: float(), y: float(), width: float(), height: float()}

  @doc "Builds a rectangle from its top-left corner and its sizes."
  @spec new(number(), number(), number(), number()) :: t()
  def new(x, y, width, height), do: %__MODULE__{x: x * 1.0, y: y * 1.0, width: width * 1.0, height: height * 1.0}

  @doc "The rectangle whose top-left corner is `point`."
  @spec from_point(Point.t(), number(), number()) :: t()
  def from_point(%Point{x: x, y: y}, width, height), do: new(x, y, width, height)

  @doc """
  The rectangle between a top-left and a bottom-right point.

  `width` is `br.x - tl.x` and `height` is `tl.y - br.y`; corners in the other
  order give negative sizes.
  """
  @spec from_corners(Point.t(), Point.t()) :: t()
  def from_corners(%Point{x: x, y: y}, %Point{x: right, y: bottom}), do: new(x, y, right - x, y - bottom)

  @doc "The left edge."
  @spec left(t()) :: float()
  def left(%__MODULE__{x: x}), do: x

  @doc "The right edge."
  @spec right(t()) :: float()
  def right(%__MODULE__{x: x, width: width}), do: x + width

  @doc "The top edge, the larger y."
  @spec top(t()) :: float()
  def top(%__MODULE__{y: y}), do: y

  @doc "The bottom edge, the smaller y."
  @spec bottom(t()) :: float()
  def bottom(%__MODULE__{y: y, height: height}), do: y - height

  @doc "The width."
  @spec width(t()) :: float()
  def width(%__MODULE__{width: width}), do: width

  @doc "The height."
  @spec height(t()) :: float()
  def height(%__MODULE__{height: height}), do: height

  @doc "The centre."
  @spec center(t()) :: Point.t()
  def center(%__MODULE__{x: x, y: y, width: width, height: height}), do: Point.new(x + width * 0.5, y - height * 0.5)

  @doc "The smallest rectangle containing both."
  @spec union(t(), t()) :: t()
  def union(%__MODULE__{} = a, %__MODULE__{} = b) do
    nx = min(a.x, b.x)
    ny = max(a.y, b.y)
    nrx = max(a.x + a.width, b.x + b.width)
    nry = min(a.y - a.height, b.y - b.height)

    new(nx, ny, nrx - nx, ny - nry)
  end

  @doc """
  The overlap of two rectangles, or `{:error, :disjoint}`.

  Rectangles that only touch give a zero-extent rectangle; a negative extent is
  the only failure.
  """
  @spec intersection(t(), t()) :: {:ok, t()} | {:error, :disjoint}
  def intersection(%__MODULE__{} = a, %__MODULE__{} = b) do
    nx = max(a.x, b.x)
    ny = min(a.y, b.y)
    nrx = min(a.x + a.width, b.x + b.width)
    nry = max(a.y - a.height, b.y - b.height)

    overlap(nx, ny, nrx, nry)
  end

  defp overlap(nx, ny, nrx, nry) when nrx < nx or nry > ny, do: {:error, :disjoint}
  defp overlap(nx, ny, nrx, nry), do: {:ok, new(nx, ny, nrx - nx, ny - nry)}

  @doc """
  Scales the rectangle uniformly about its centre.

  A negative factor produces an inside-out rectangle.
  """
  @spec central_scale(t(), number()) :: t()
  def central_scale(%__MODULE__{x: x, y: y, width: width, height: height}, factor) do
    cx = x + width * 0.5
    cy = y - height * 0.5
    nw = width * factor
    nh = height * factor

    new(cx - nw * 0.5, cy + nh * 0.5, nw, nh)
  end

  @doc """
  The transform that fits `inner` inside `outer`, centred, with the same aspect.

  The scale is the smaller of the two per-axis fits, so the result touches
  `outer` on at most one axis. Both of `inner`'s dimensions must be non-zero.
  """
  @spec center_inside(t(), t()) :: Transform.t()
  def center_inside(%__MODULE__{} = inner, %__MODULE__{} = outer) do
    factor = min(outer.width / inner.width, outer.height / inner.height)
    mine = center(inner)
    yours = center(outer)

    Transform.compose(
      Transform.translate_point(yours),
      Transform.compose(Transform.scale(factor, factor), Transform.translate(-mine.x, -mine.y))
    )
  end
end

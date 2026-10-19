defmodule Girihelix.Engine.Geometry.Segment do
  @moduledoc """
  A directed line segment between two points a positive distance apart.

  The guarantee is the point of the type: for every segment,
  `Point.dist2(from(segment), to(segment)) > 0.0`. A function taking a `Segment`
  may therefore divide by its squared length, or invert the transform built
  from its endpoints, without checking first.

  The test is on the squared distance rather than on equality of the points,
  for two reasons. `Point.new(0.0, 0.0)` and `Point.new(-0.0, 0.0)` are not
  strictly equal, yet are the same position. And two distinct points closer
  than about `2e-162` have a squared distance that underflows to `0.0`, which
  is exactly the divisor the guarantee protects.

  The type is opaque. Build one with `new/2` or `new!/2`, and read it with
  `from/1` and `to/1`; dialyzer reports a segment built any other way.
  """

  alias Girihelix.Engine.Geometry.Point

  @enforce_keys [:from, :to]
  defstruct [:from, :to]

  @opaque t :: %__MODULE__{from: Point.t(), to: Point.t()}

  @type reason :: :coincident_points

  @doc """
  The segment from `from` to `to`, or `{:error, :coincident_points}` when the
  two points are not a positive distance apart.
  """
  @spec new(Point.t(), Point.t()) :: {:ok, t()} | {:error, :coincident_points}
  def new(%Point{} = from, %Point{} = to), do: build(from, to, Point.dist2(from, to))

  defp build(_from, _to, squared_length) when squared_length == 0.0, do: {:error, :coincident_points}

  defp build(from, to, _squared_length), do: {:ok, %__MODULE__{from: from, to: to}}

  @doc "`new/2` for a caller that knows the points are distinct, raising otherwise."
  @spec new!(Point.t(), Point.t()) :: t()
  def new!(from, to) do
    case new(from, to) do
      {:ok, segment} -> segment
      {:error, reason} -> raise ArgumentError, "cannot build a segment (#{reason})"
    end
  end

  @doc "The start point."
  @spec from(t()) :: Point.t()
  def from(%__MODULE__{from: from}), do: from

  @doc "The end point."
  @spec to(t()) :: Point.t()
  def to(%__MODULE__{to: to}), do: to
end

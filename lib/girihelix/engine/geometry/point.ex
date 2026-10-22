defmodule Girihelix.Engine.Geometry.Point do
  @moduledoc """
  A point in the plane: a pure value with tolerant equality.

  Note that `Point`'s tolerance is **not** `Loose`'s. `Point.equals/2` tests a
  squared distance below `tolerance2/0` (`1e-14`), while `Loose.equals/2` tests
  `1e-10`. Both spell "equals" and they differ by four orders of magnitude in
  squared terms — two in linear terms, a factor of a hundred — so a caller must
  know which one it wants.

  No function here can fail. Where an argument could be degenerate, the type
  rules it out instead: `parameterization_on_line/2` takes a `Segment`, whose
  endpoints are guaranteed distinct, and `center/1` takes a non-empty list.
  """

  alias Girihelix.Engine.Geometry.Segment

  @tolerance 1.0e-7
  @tolerance2 @tolerance * @tolerance

  @enforce_keys [:x, :y]
  defstruct [:x, :y]

  @type t :: %__MODULE__{x: float(), y: float()}

  @doc "Builds a point."
  @spec new(number(), number()) :: t()
  def new(x, y), do: %__MODULE__{x: x * 1.0, y: y * 1.0}

  @doc "The linear tolerance used by `equals/2`, `1e-7`."
  def tolerance, do: @tolerance

  @doc "The squared tolerance used by `equals/2`, `1e-14`."
  def tolerance2, do: @tolerance2

  @doc "The origin."
  def origin, do: new(0.0, 0.0)

  @doc "The point `(1, 0)`."
  def unit_x, do: new(1.0, 0.0)

  @doc "The point `(0, 1)`."
  def unit_y, do: new(0.0, 1.0)

  @doc "Squared magnitude."
  @spec mag2(t()) :: float()
  def mag2(%__MODULE__{x: x, y: y}), do: x * x + y * y

  @doc "Magnitude."
  @spec mag(t()) :: float()
  def mag(p), do: :math.sqrt(mag2(p))

  @doc "Squared distance between two points."
  @spec dist2(t(), t()) :: float()
  def dist2(%__MODULE__{x: ax, y: ay}, %__MODULE__{x: bx, y: by}) do
    dx = ax - bx
    dy = ay - by
    dx * dx + dy * dy
  end

  @doc "Distance between two points."
  @spec dist(t(), t()) :: float()
  def dist(a, b), do: :math.sqrt(dist2(a, b))

  @doc "Vector sum."
  @spec add(t(), t()) :: t()
  def add(%__MODULE__{x: ax, y: ay}, %__MODULE__{x: bx, y: by}), do: new(ax + bx, ay + by)

  @doc "Vector difference."
  @spec subtract(t(), t()) :: t()
  def subtract(%__MODULE__{x: ax, y: ay}, %__MODULE__{x: bx, y: by}), do: new(ax - bx, ay - by)

  @doc "Dot product."
  @spec dot(t(), t()) :: float()
  def dot(%__MODULE__{x: ax, y: ay}, %__MODULE__{x: bx, y: by}), do: ax * bx + ay * by

  @doc "Two-dimensional cross product."
  @spec cross(t(), t()) :: float()
  def cross(%__MODULE__{x: ax, y: ay}, %__MODULE__{x: bx, y: by}), do: ax * by - ay * bx

  @doc "Uniform scale."
  @spec scale(t(), number()) :: t()
  def scale(%__MODULE__{x: x, y: y}, r), do: new(x * r, y * r)

  @doc "Component-wise scale."
  @spec scale(t(), number(), number()) :: t()
  def scale(%__MODULE__{x: x, y: y}, xr, yr), do: new(x * xr, y * yr)

  @doc "A counter-clockwise quarter turn: `(x, y) -> (-y, x)`."
  @spec perp(t()) :: t()
  def perp(%__MODULE__{x: x, y: y}), do: new(-y, x)

  @doc """
  The unit vector in this direction.

  Returns the point **itself** when the magnitude is exactly zero — an exact
  comparison, not a tolerant one. Never fails, so it returns a point rather than a
  tuple.
  """
  @spec normalize(t()) :: t()
  def normalize(p), do: normalized(p, mag(p))

  # A guarded clause rather than a `0.0` pattern: a float literal in a pattern
  # matches only `+0.0`, and the comparison states the intent.
  defp normalized(p, magnitude) when magnitude == 0.0, do: p
  defp normalized(p, magnitude), do: scale(p, 1.0 / magnitude)

  @doc """
  The convex sum `(1 - t) * a + t * b`.

  `t` is **not** clamped, so values outside `[0, 1]` extrapolate. The Rosette
  construction relies on that: it passes `t = 10.0`.
  """
  @spec convex_sum(t(), t(), number()) :: t()
  def convex_sum(%__MODULE__{x: ax, y: ay}, %__MODULE__{x: bx, y: by}, t) do
    mt = 1.0 - t
    new(mt * ax + t * bx, mt * ay + t * by)
  end

  @doc """
  Tolerant value equality: a squared distance below `tolerance2/0`.

  Not transitive, and inconsistent with any hash you might build from it, so do
  not use a point as a set or map key.
  """
  @spec equals(t(), t()) :: boolean()
  def equals(a, b), do: dist2(a, b) < @tolerance2

  @doc """
  Orders by **squared magnitude**, with a `tolerance2/0` band, not
  lexicographically by coordinates.

  The band makes the relation non-transitive: `a` can compare equal to `b`, and
  `b` to `c`, while `a` compares less than `c`. Sorting through this comparator
  is therefore unstable. That is deliberate, and pinned by a test.
  `Enum.sort/2` wants a boolean predicate, so use `sorter/0` rather than passing
  this comparator directly.
  """
  @spec compare_to(t(), t()) :: -1 | 0 | 1
  def compare_to(a, b), do: order(mag2(a) - mag2(b))

  @doc """
  `compare_to/2` as the boolean predicate `Enum.sort/2` expects.

  The conversion is "not greater than", so the comparator's `tolerance2/0`
  band is preserved: two points inside it satisfy the predicate in both
  directions, exactly as the comparator reports them equal.
  """
  @spec sorter() :: (t(), t() -> boolean())
  def sorter, do: &(compare_to(&1, &2) != 1)

  defp order(diff) when diff < -@tolerance2, do: -1
  defp order(diff) when diff > @tolerance2, do: 1
  defp order(_diff), do: 0

  @doc "The angle of this point with respect to the origin, in `-pi..pi`."
  @spec angle(t()) :: float()
  def angle(%__MODULE__{x: x, y: y}), do: :math.atan2(y, x)

  @doc "The angle of the edge from `from` to `to`, in `-pi..pi`."
  @spec angle_to(t(), t()) :: float()
  def angle_to(%__MODULE__{x: ax, y: ay}, %__MODULE__{x: bx, y: by}), do: :math.atan2(by - ay, bx - ax)

  @doc """
  The angle swept from `from` to `to` about `vertex`, in `[0, 2pi)`.

  Normalised by adding `2pi` until positive rather than by taking a remainder,
  so a very negative angle iterates — only reachable
  if a caller passes angles differing by many turns.
  """
  @spec sweep(t(), t(), t()) :: float()
  def sweep(vertex, from, to) do
    unwrap(angle_to(vertex, to) - angle_to(vertex, from))
  end

  defp unwrap(result) when result < 0.0, do: unwrap(result + 2.0 * :math.pi())
  defp unwrap(result), do: result

  @doc """
  The squared distance from `p` to the **segment** `a`-`b`, not to the infinite
  line through them.

  A point beyond an endpoint gets its distance to that endpoint. When `a` and `b`
  coincide, the result is the squared distance to `b`. Always returns a distance,
  so it is not a tuple.
  """
  @spec dist2_to_line(t(), t(), t()) :: float()
  def dist2_to_line(%__MODULE__{} = p, %__MODULE__{} = a, %__MODULE__{} = b) do
    delta = subtract(b, a)
    to_segment(p, a, b, delta, dot(delta, delta))
  end

  # A degenerate segment: the distance to `b`, rather than a division by zero.
  defp to_segment(p, _a, b, _delta, squared_length) when squared_length == 0.0, do: dist2(b, p)
  defp to_segment(p, a, b, delta, squared_length), do: project(p, a, b, delta, squared_length)

  defp project(p, a, b, delta, squared_length) do
    t = dot(subtract(p, a), delta) / squared_length
    nearest(p, a, b, t)
  end

  defp nearest(p, a, b, t) when t >= 0.0 and t <= 1.0 do
    dist2(p, new(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y)))
  end

  defp nearest(p, a, _b, t) when t < 0.0, do: dist2(a, p)
  defp nearest(p, _a, b, _t), do: dist2(b, p)

  @doc "The distance from `p` to the segment `a`-`b`."
  @spec dist_to_line(t(), t(), t()) :: float()
  def dist_to_line(p, a, b), do: :math.sqrt(dist2_to_line(p, a, b))

  @doc """
  The unclamped parameter of `p` along the line through `segment`.

  `0.0` at the segment's start, `1.0` at its end, negative before the start,
  greater than `1.0` past the end. Total: a `Segment`'s endpoints are a positive
  distance apart, so the divisor, its squared length, is never zero.
  """
  @spec parameterization_on_line(t(), Segment.t()) :: float()
  def parameterization_on_line(%__MODULE__{} = p, segment) do
    a = Segment.from(segment)
    delta = subtract(Segment.to(segment), a)
    dot(subtract(p, a), delta) / dot(delta, delta)
  end

  @doc """
  The mean of a non-empty list of points.

  The non-empty requirement is in the function head, so `center([])` is rejected
  by the compiler where it is written. Every element must be a point: `nil` is
  not skipped, and raises `FunctionClauseError`.
  """
  @spec center([t(), ...]) :: t()
  def center([_ | _] = points) do
    points
    |> Enum.reduce(origin(), &add/2)
    |> scale(1.0 / length(points))
  end

  @doc """
  Subtracts `center` from each non-nil point, leaving nils in place.

  Returns a new list; the input is never shared with the result.
  """
  @spec recenter([t() | nil], t()) :: [t() | nil]
  def recenter(points, center) do
    Enum.map(points, fn
      nil -> nil
      %__MODULE__{} = point -> subtract(point, center)
    end)
  end
end

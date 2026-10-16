defmodule Girihelix.Engine.Geometry.Point do
  @moduledoc """
  A point in the plane: a pure value with tolerant equality.

  Ported from `geometry/Point.java`. The Java exists in pure and in-place
  flavours, every in-place one suffixed `D`; the `D` forms are dropped here and
  every operation returns a new value.

  Note that `Point`'s tolerance is **not** `Loose`'s. `Point.equals/2` tests a
  squared distance below `tolerance2/0` (`1e-14`), while `Loose.equals/2` tests
  `1e-10`. Both spell "equals" and they differ by four orders of magnitude in
  squared terms — two in linear terms, a factor of a hundred — so a caller must
  know which one it wants.
  """

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

  # The Java exposes ORIGIN, UNIT_X and UNIT_Y as shared mutable singletons, which
  # any caller could corrupt through setX/setY. They are functions here.

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
  comparison, not a tolerant one, matching the Java.
  """
  @spec normalize(t()) :: t()
  def normalize(p) do
    m = mag(p)

    # An explicit comparison rather than a `0.0` pattern: a float literal pattern
    # matches only `+0.0` and would miss a negative zero.
    if m == 0.0, do: p, else: scale(p, 1.0 / m)
  end

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
  therefore produces an unstable order, which is faithful to the Java and is
  pinned by a test rather than silently relied upon.
  """
  @spec compare_to(t(), t()) :: -1 | 0 | 1
  def compare_to(a, b) do
    diff = mag2(a) - mag2(b)

    cond do
      diff < -@tolerance2 -> -1
      diff > @tolerance2 -> 1
      true -> 0
    end
  end

  @doc "The angle of this point with respect to the origin, in `-pi..pi`."
  @spec angle(t()) :: float()
  def angle(%__MODULE__{x: x, y: y}), do: :math.atan2(y, x)

  @doc "The angle of the edge from `from` to `to`, in `-pi..pi`."
  @spec angle_to(t(), t()) :: float()
  def angle_to(%__MODULE__{x: ax, y: ay}, %__MODULE__{x: bx, y: by}), do: :math.atan2(by - ay, bx - ax)

  @doc """
  The angle swept from `from` to `to` about `vertex`, in `[0, 2pi)`.

  Normalised by adding `2pi` until positive rather than by taking a remainder,
  so a very negative angle iterates — faithful to the Java, and only reachable
  if a caller passes angles differing by many turns.
  """
  @spec sweep(t(), t(), t()) :: float()
  def sweep(vertex, from, to) do
    unwrap(angle_to(vertex, to) - angle_to(vertex, from))
  end

  defp unwrap(res) when res < 0.0, do: unwrap(res + 2.0 * :math.pi())
  defp unwrap(res), do: res

  @doc """
  The squared distance from `p` to the **segment** `a`-`b`, not to the infinite
  line through them.

  A point beyond an endpoint gets its distance to that endpoint. A zero-length
  segment is guarded rather than divided through: Java's division yields `NaN`,
  every comparison against `NaN` is false, and the clamp falls through to the
  second endpoint. This returns that same value explicitly — Elixir's `/` raises
  on a zero divisor, so the guard is required to reproduce it. See
  `parameterization_on_line/3`, which raises instead.
  """
  @spec dist2_to_line(t(), t(), t()) :: float()
  def dist2_to_line(%__MODULE__{} = p, %__MODULE__{} = a, %__MODULE__{} = b) do
    delta = subtract(b, a)
    denom = dot(delta, delta)

    # An explicit comparison, not a `0.0` pattern: a float literal pattern matches
    # only `+0.0`. A squared length is never negative zero in practice, but the
    # comparison states the intent and does not depend on that.
    if denom == 0.0 do
      # degenerate segment: reproduce the Java's NaN fall-through to `b`
      dist2(b, p)
    else
      project(p, a, b, denom)
    end
  end

  defp project(p, a, b, denom) do
    delta = subtract(b, a)
    t = dot(subtract(p, a), delta) / denom

    cond do
      t >= 0.0 and t <= 1.0 ->
        projection = new(a.x + t * (b.x - a.x), a.y + t * (b.y - a.y))
        dist2(p, projection)

      t < 0.0 ->
        dist2(a, p)

      true ->
        dist2(b, p)
    end
  end

  @doc "The distance from `p` to the segment `a`-`b`."
  @spec dist_to_line(t(), t(), t()) :: float()
  def dist_to_line(p, a, b), do: :math.sqrt(dist2_to_line(p, a, b))

  @doc """
  The unclamped parameter of `p` along the line through `a` and `b`.

  `0.0` at `a`, `1.0` at `b`, negative before `a`, greater than `1.0` past `b`.

  Raises on a zero-length segment. Java divides through and yields `NaN`, which
  every caller then reads as "not on the segment"; raising is a deliberate
  divergence, recorded here, because a parameter along a segment with no length
  is meaningless and a silent `NaN` is worse than an error.
  """
  @spec parameterization_on_line(t(), t(), t()) :: float()
  def parameterization_on_line(%__MODULE__{} = p, %__MODULE__{} = a, %__MODULE__{} = b) do
    delta = subtract(b, a)
    denom = dot(delta, delta)

    if denom == 0.0 do
      raise ArgumentError, "cannot parameterise along a zero-length segment"
    else
      dot(subtract(p, a), delta) / denom
    end
  end

  @doc """
  The mean of the non-nil points.

  Raises when there is nothing to average. The Java divides by a zero count and
  returns `Point(NaN, NaN)`, which is a silent coordinate poison; raising is a
  deliberate divergence, recorded in the plan.
  """
  @spec center([t() | nil]) :: t()
  def center(points) do
    {sum, count} =
      Enum.reduce(points, {origin(), 0}, fn
        nil, acc -> acc
        %__MODULE__{} = p, {sum, n} -> {add(sum, p), n + 1}
      end)

    if count == 0 do
      raise ArgumentError, "cannot average an empty set of points"
    end

    scale(sum, 1.0 / count)
  end

  @doc """
  Subtracts `center` from each non-nil point, leaving nils in place.

  Returns a new list. The Java returns its input array unchanged when the centre
  is null, which aliases the caller's data; that case cannot arise here.
  """
  @spec recenter([t() | nil], t()) :: [t() | nil]
  def recenter(points, center) do
    Enum.map(points, fn
      nil -> nil
      %__MODULE__{} = p -> subtract(p, center)
    end)
  end
end

defmodule Girihelix.Engine.Geometry.Intersect do
  @moduledoc """
  Segment-to-segment crossing. Stateless.

  Three things about it are deliberate and must not be "improved" without
  recording the change.

  **A crossing is a parameter pair, not a position.** `get_intersection_params/2`
  returns `{s, t}`, the fractions along each segment — never a `Point`, because
  they are not a location.

  **Failure is `nil`, and the reasons are indistinguishable.** Parallel segments
  and a crossing outside the segment both give `nil`, so no caller can tell which
  happened. A zero-length segment cannot occur: every entry point takes
  `Segment`s, whose endpoints are distinct. An error tuple would invent a
  distinction the algorithm deliberately does not make, so `nil` stays — and it
  is data the caller matches, not an exception.

  **Overlapping collinear segments and endpoint-touching pairs are not handled.**
  Callers that need those cases handle them
  themselves, which is exactly what the `nil` match in `Rosette` is for.
  """

  alias Girihelix.Engine.Geometry.Loose
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Segment

  # Read at compile time so the guards below can use it: a guard cannot call a
  # function, and duplicating the literal here would let the two drift apart.
  @tol Loose.tol()
  @near_slack 0.2

  @doc """
  The crossing of two segments as `{s, t}`, or `nil`.

  `s` is the fraction along `first`, `t` along `second`. Parallel segments
  return `nil`.

  The parallel test is an **absolute** `1e-7` on a quantity with units of length
  squared, through `Loose.zero/1`. It is therefore scale
  dependent: a map scaled up by 1000 will have near-parallel edges declared
  intersecting. Kept deliberately.
  """
  @spec get_intersection_params(Segment.t(), Segment.t()) :: {float(), float()} | nil
  def get_intersection_params(first, second) do
    params(Segment.from(first), Segment.to(first), Segment.from(second), Segment.to(second))
  end

  defp params(p1, q1, p2, q2) do
    d1 = Point.subtract(q1, p1)
    d2 = Point.subtract(q2, p2)
    crossing(p1, q1, p2, q2, d1, d2, d1.x * d2.y - d1.y * d2.x)
  end

  defp crossing(_p1, _q1, _p2, _q2, _d1, _d2, determinant) when abs(determinant) < @tol, do: nil

  defp crossing(p1, q1, p2, q2, d1, d2, determinant) do
    # Adapted from O'Rourke's _Computational Geometry in C_, transcribed rather
    # than simplified: the signs are easy to get wrong and a mistake here is
    # silently a swapped or negated parameter.
    {
      -(p1.x * d2.y + p2.x * (p1.y - q2.y) + q2.x * (p2.y - p1.y)) / determinant,
      (p1.x * (p2.y - q1.y) + q1.x * (p1.y - p2.y) + p2.x * d1.y) / determinant
    }
  end

  @doc """
  Keeps a parameter pair only if both parameters are within `Loose.tol/0` of
  `[0, 1]`, so a crossing a hair past an endpoint still counts.
  """
  @spec stay_on_segments({float(), float()} | nil) :: {float(), float()} | nil
  def stay_on_segments(nil), do: nil

  def stay_on_segments({s, t}) when s >= -@tol and s <= 1.0 + @tol and t >= -@tol and t <= 1.0 + @tol, do: {s, t}

  def stay_on_segments({_s, _t}), do: nil

  @doc """
  Keeps a parameter pair only if both parameters are within `0.2` of `[0, 1]`.

  A hard-coded parameter-space slack, not a distance, so it is scale invariant —
  unlike the determinant test in `get_intersection_params/2`.

  No v1 caller uses this or `get_near_intersection/2`: the figures and `Infer`
  use `get_intersection/2` and `get_true_intersection/2`. The near variant exists
  for the inference strategies outside v1, which are its intended consumers.
  """
  @spec stay_near_segments({float(), float()} | nil) :: {float(), float()} | nil
  def stay_near_segments(nil), do: nil

  def stay_near_segments({s, t})
      when s >= -@near_slack and s <= 1.0 + @near_slack and t >= -@near_slack and t <= 1.0 + @near_slack, do: {s, t}

  def stay_near_segments({_s, _t}), do: nil

  @doc """
  The crossing of two segments, as a position on the first.

  Returns the point `(1 - s) * from + s * to` on `first`, or `nil`. The `t`
  parameter is validated but never used to build the position, so the result
  always lies on the first segment — or, for `get_near_intersection/2`, up to 20% beyond it.
  """
  @spec get_intersection(Segment.t(), Segment.t()) :: Point.t() | nil
  def get_intersection(first, second) do
    interpolate(first, first |> get_intersection_params(second) |> stay_on_segments())
  end

  @doc "As `get_intersection/2`, with the wider `0.2` parameter slack."
  @spec get_near_intersection(Segment.t(), Segment.t()) :: Point.t() | nil
  def get_near_intersection(first, second) do
    interpolate(first, first |> get_intersection_params(second) |> stay_near_segments())
  end

  @doc """
  The crossing, excluding one that lands at the endpoints of **both** segments.

  This is the variant the planar map's weld uses. Two edges meeting at a shared
  vertex cross there,
  with `s` and `t` both near `0` or both near `1`; discarding that case is what
  stops the shared vertex being split into two.

  Note it does **not** reject a crossing at an endpoint of one segment that is
  interior to the other, which is why the ordinary "T" junction survives.
  """
  @spec get_true_intersection(Segment.t(), Segment.t()) :: Point.t() | nil
  def get_true_intersection(first, second) do
    resolve(first, first |> get_intersection_params(second) |> stay_on_segments())
  end

  defp interpolate(_first, nil), do: nil
  defp interpolate(first, {s, _t}), do: along(first, s)

  defp resolve(_first, nil), do: nil
  defp resolve(first, {s, t}), do: crossing_point(first, s, {at_an_end?(s), at_an_end?(t)})

  # A crossing at an end of BOTH segments is a shared vertex, not a crossing.
  defp crossing_point(_first, _s, {true, true}), do: nil
  defp crossing_point(first, s, _ends), do: along(first, s)

  defp along(segment, s), do: Point.convex_sum(Segment.from(segment), Segment.to(segment), s)

  defp at_an_end?(parameter) when parameter < @tol, do: true
  defp at_an_end?(parameter) when 1.0 - parameter < @tol, do: true
  defp at_an_end?(_parameter), do: false
end

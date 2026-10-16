defmodule Girihelix.Engine.Geometry.Intersect do
  @moduledoc """
  Segment-to-segment crossing. Stateless.

  Ported from `geometry/Intersect.java`. Three things about it are deliberate in
  the source and must not be "improved" without recording the change.

  **A crossing is a parameter pair, not a position.** `get_intersection_params/4`
  returns `{s, t}`, the fractions along each segment. The Java packs those into a
  `Point`, where they are not a location at all.

  **Failure is `nil`, and the reasons are indistinguishable.** Parallel segments, a
  crossing outside the segment, and a zero-length segment all give `nil`, so no
  caller can tell which happened. An error tuple would invent a distinction the
  source deliberately does not make, so `nil` stays — and it is data the caller
  matches, not an exception.

  **Overlapping collinear segments and endpoint-touching pairs are not handled.**
  The source says so and stops there. Callers that need those cases handle them
  themselves, which is exactly what the `nil` match in `Rosette` is for.
  """

  alias Girihelix.Engine.Geometry.Loose
  alias Girihelix.Engine.Geometry.Point

  # Read at compile time so the guards below can use it: a guard cannot call a
  # function, and duplicating the literal here would let the two drift apart.
  @tol Loose.tol()
  @near_slack 0.2

  @doc """
  The crossing of two segments as `{s, t}`, or `nil`.

  `s` is the fraction along `p1 -> q1`, `t` along `p2 -> q2`. Parallel segments —
  including a zero-length one, whose direction vector is zero — return `nil`.

  The parallel test is an **absolute** `1e-7` on a quantity with units of length
  squared, which is the source's `Loose.zero(det)`. It is therefore scale
  dependent: a map scaled up by 1000 will have near-parallel edges declared
  intersecting. Kept as-is, because it is the source's behaviour.
  """
  @spec get_intersection_params(Point.t(), Point.t(), Point.t(), Point.t()) ::
          {float(), float()} | nil
  def get_intersection_params(%Point{} = p1, %Point{} = q1, %Point{} = p2, %Point{} = q2) do
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
  unlike the determinant test in `get_intersection_params/4`.

  Nothing in the reference tree calls this or `get_near_intersection/4`. The only
  entry points the figures and `Infer` use are `get_intersection/4` and
  `get_true_intersection/4`. The near variant is ported because it is part of the
  source's public surface and the six inference strategies outside v1 are its
  intended consumers, not because any v1 caller needs it.
  """
  @spec stay_near_segments({float(), float()} | nil) :: {float(), float()} | nil
  def stay_near_segments(nil), do: nil

  def stay_near_segments({s, t})
      when s >= -@near_slack and s <= 1.0 + @near_slack and t >= -@near_slack and t <= 1.0 + @near_slack, do: {s, t}

  def stay_near_segments({_s, _t}), do: nil

  @doc """
  The crossing of two segments, as a position on the first.

  Returns the point `(1 - s) * p1 + s * q1`, or `nil`. The `t` parameter is
  validated but never used to build the position, so the result always lies on
  the first segment — or, for `get_near_intersection/4`, up to 20% beyond it.
  """
  @spec get_intersection(Point.t(), Point.t(), Point.t(), Point.t()) :: Point.t() | nil
  def get_intersection(p1, q1, p2, q2) do
    interpolate(p1, q1, p1 |> get_intersection_params(q1, p2, q2) |> stay_on_segments())
  end

  @doc "As `get_intersection/4`, with the wider `0.2` parameter slack."
  @spec get_near_intersection(Point.t(), Point.t(), Point.t(), Point.t()) :: Point.t() | nil
  def get_near_intersection(p1, q1, p2, q2) do
    interpolate(p1, q1, p1 |> get_intersection_params(q1, p2, q2) |> stay_near_segments())
  end

  @doc """
  The crossing, excluding one that lands at the endpoints of **both** segments.

  This is `mergeMap`'s variant. Two edges meeting at a shared vertex cross there,
  with `s` and `t` both near `0` or both near `1`; discarding that case is what
  stops the shared vertex being split into two.

  Note it does **not** reject a crossing at an endpoint of one segment that is
  interior to the other, which is why the ordinary "T" junction survives.
  """
  @spec get_true_intersection(Point.t(), Point.t(), Point.t(), Point.t()) :: Point.t() | nil
  def get_true_intersection(p1, q1, p2, q2) do
    resolve(p1, q1, p1 |> get_intersection_params(q1, p2, q2) |> stay_on_segments())
  end

  defp interpolate(_p1, _q1, nil), do: nil
  defp interpolate(p1, q1, {s, _t}), do: Point.convex_sum(p1, q1, s)

  defp resolve(_p1, _q1, nil), do: nil
  defp resolve(p1, q1, {s, t}), do: crossing_point(p1, q1, s, {at_an_end?(s), at_an_end?(t)})

  # A crossing at an end of BOTH segments is a shared vertex, not a crossing.
  defp crossing_point(_p1, _q1, _s, {true, true}), do: nil
  defp crossing_point(p1, q1, s, _ends), do: Point.convex_sum(p1, q1, s)

  defp at_an_end?(parameter) when parameter < @tol, do: true
  defp at_an_end?(parameter) when 1.0 - parameter < @tol, do: true
  defp at_an_end?(_parameter), do: false
end

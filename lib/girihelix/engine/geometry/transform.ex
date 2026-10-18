defmodule Girihelix.Engine.Geometry.Transform do
  @moduledoc """
  A two-dimensional affine transform: the top two rows of the homogeneous 3x3
  matrix.

      [ a  b  c ]
      [ d  e  f ]
      [ 0  0  1 ]

  `(a, b, d, e)` is the linear part and `(c, f)` the translation, so the mapping
  is `x' = a*x + b*y + c` and `y' = d*x + e*y + f`.

  **Composition order.** `compose(a, b)` applies `b` **first**, then `a`, so a
  nested composition reads outermost-first but runs innermost-first — the reason
  `rotate_around_point/2` and `reflect_through_line/1` look "backwards". The
  convention is deliberate, documented here and tested.

  **Failures are data.** Only `invert/1` and `dist_from_inverted_zero/2` can
  fail, because a singular transform is representable and has no inverse. They
  return `{:ok, result} | {:error, :non_invertible}`, and callers thread them
  with `with`. `invert!/1` is the bang variant for a caller that has already
  established invertibility.

  The constructors built from segments — `reflect_through_line/1` and
  `match_two_segments/2` — are total: a `Segment`'s endpoints are distinct, so
  the transform they invert always has an inverse.
  """

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Segment

  @enforce_keys [:a, :b, :c, :d, :e, :f]
  defstruct [:a, :b, :c, :d, :e, :f]

  @type t :: %__MODULE__{
          a: float(),
          b: float(),
          c: float(),
          d: float(),
          e: float(),
          f: float()
        }

  @type reason :: :non_invertible

  @doc "Builds a transform from its six scalars."
  @spec new(number(), number(), number(), number(), number(), number()) :: t()
  def new(a, b, c, d, e, f) do
    %__MODULE__{a: a * 1.0, b: b * 1.0, c: c * 1.0, d: d * 1.0, e: e * 1.0, f: f * 1.0}
  end

  @doc "The identity transform."
  @spec identity() :: t()
  def identity, do: scale(1.0)

  @doc """
  The all-zero matrix, which collapses everything to the origin.

  It is **not** a null transform: its determinant is zero, so `invert/1` reports
  `{:error, :non_invertible}` on it.
  """
  @spec zero() :: t()
  def zero, do: scale(0.0)

  @doc "Uniform scale."
  @spec scale(number()) :: t()
  def scale(r), do: new(r, 0.0, 0.0, 0.0, r, 0.0)

  @doc "Component-wise scale."
  @spec scale(number(), number()) :: t()
  def scale(xs, ys), do: new(xs, 0.0, 0.0, 0.0, ys, 0.0)

  @doc "Translation."
  @spec translate(number(), number()) :: t()
  def translate(x, y), do: new(1.0, 0.0, x, 0.0, 1.0, y)

  @doc "Translation by a point's coordinates."
  @spec translate_point(Point.t()) :: t()
  def translate_point(%Point{x: x, y: y}), do: translate(x, y)

  @doc """
  Rotation by `t` radians, counter-clockwise in a y-up frame.

  In the y-down screen frame this reads clockwise, which matters for the renderer
  and not for the geometry.
  """
  @spec rotate(number()) :: t()
  def rotate(t) do
    new(:math.cos(t), -:math.sin(t), 0.0, :math.sin(t), :math.cos(t), 0.0)
  end

  @doc """
  Rotation by `t` about a point.

  Applies `-pt`, then the rotation, then `+pt`, which is what the nested
  composition below spells out.
  """
  @spec rotate_around_point(Point.t(), number()) :: t()
  def rotate_around_point(%Point{x: x, y: y} = point, t) do
    compose(translate_point(point), compose(rotate(t), translate(-x, -y)))
  end

  @doc """
  Reflection in the line through `segment`.

  Maps the line onto the unit x interval, flips y, and maps back. Total: the
  segment's endpoints are distinct, so the line always exists.
  """
  @spec reflect_through_line(Segment.t()) :: t()
  def reflect_through_line(segment) do
    onto_line = match_line_segment(Segment.from(segment), Segment.to(segment))

    # The determinant of `onto_line` is the segment's squared length, which a
    # Segment guarantees is positive, so this inverse always exists.
    compose(onto_line, compose(scale(1.0, -1.0), invert!(onto_line)))
  end

  @doc """
  Composition: `compose(a, b)` applies **`b` first**, then `a`.

  For any point `v`, `apply_to(compose(a, b), v) == apply_to(a, apply_to(b, v))`.
  """
  @spec compose(t(), t()) :: t()
  def compose(%__MODULE__{a: a, b: b, c: c, d: d, e: e, f: f}, %__MODULE__{a: oa, b: ob, c: oc, d: od, e: oe, f: of}) do
    new(
      a * oa + b * od,
      a * ob + b * oe,
      a * oc + b * of + c,
      d * oa + e * od,
      d * ob + e * oe,
      d * oc + e * of + f
    )
  end

  @doc "Applies the transform to a point."
  @spec apply_to(t(), Point.t()) :: Point.t()
  def apply_to(%__MODULE__{a: a, b: b, c: c, d: d, e: e, f: f}, %Point{x: x, y: y}) do
    Point.new(a * x + b * y + c, d * x + e * y + f)
  end

  @doc "Applies the transform to a coordinate pair, with no allocation in between."
  @spec apply_coords(t(), number(), number()) :: Point.t()
  def apply_coords(%__MODULE__{a: a, b: b, c: c, d: d, e: e, f: f}, x, y) do
    Point.new(a * x + b * y + c, d * x + e * y + f)
  end

  @doc "The determinant of the transform, which is the determinant of its linear part."
  @spec determinant(t()) :: float()
  def determinant(%__MODULE__{a: a, b: b, d: d, e: e}), do: a * e - b * d

  @doc """
  The inverse transform, or `{:error, :non_invertible}`.

  Tests the determinant for **exact** equality with `0.0`, not against a
  tolerance, so a matrix with a determinant of `1e-300` inverts to enormous values
  rather than failing. The test here is `determinant == 0.0`.

  Use `invert!/1` when the caller already knows the transform is invertible.
  """
  @spec invert(t()) :: {:ok, t()} | {:error, :non_invertible}
  def invert(%__MODULE__{} = transform), do: inverted(transform, determinant(transform))

  defp inverted(%__MODULE__{}, determinant) when determinant == 0.0, do: {:error, :non_invertible}

  defp inverted(%__MODULE__{a: a, b: b, c: c, d: d, e: e, f: f}, determinant) do
    {:ok,
     new(
       e / determinant,
       -b / determinant,
       (b * f - c * e) / determinant,
       -d / determinant,
       a / determinant,
       (c * d - a * f) / determinant
     )}
  end

  @doc """
  `invert/1` for a caller that has established invertibility, raising otherwise.
  """
  @spec invert!(t()) :: t()
  def invert!(transform) do
    case invert(transform) do
      {:ok, inverse} -> inverse
      {:error, reason} -> raise ArgumentError, "non-invertible transform (#{reason})"
    end
  end

  @doc "Whether the transform reverses orientation, i.e. its determinant is negative."
  @spec flips(t()) :: boolean()
  def flips(transform), do: determinant(transform) < 0.0

  @doc """
  The transform carrying the unit interval on the positive x axis onto `p`-`q`.

  `(0, 0)` maps to `p` and `(1, 0)` maps to `q`. It is always a similarity —
  rotation composed with uniform scale — and its determinant is `|q - p|`
  squared, so it **never** flips orientation.
  """
  @spec match_line_segment(Point.t(), Point.t()) :: t()
  def match_line_segment(%Point{x: px, y: py}, %Point{x: qx, y: qy}) do
    new(qx - px, py - qy, px, qy - py, qx - px, py)
  end

  @doc """
  The transform carrying segment `source` onto segment `target`.

  Maps the start of `source` to the start of `target`, and its end to the end of
  `target`. Both factors are similarities, so the result never flips. Total: the
  source segment has positive length, so its matching transform is invertible.
  """
  @spec match_two_segments(Segment.t(), Segment.t()) :: t()
  def match_two_segments(source, target) do
    # The determinant is the source segment's squared length, which a Segment
    # guarantees is positive, so this inverse always exists.
    inverse = source |> Segment.from() |> match_line_segment(Segment.to(source)) |> invert!()

    compose(match_line_segment(Segment.from(target), Segment.to(target)), inverse)
  end

  @doc """
  The distance between the images of `(v, 0)` and `(0, 0)`.

  A renderer utility used to scale stroke widths with zoom.

  The geometry core does not need it, but the SVG emitter will. Total: it
  measures through the transform itself, not its inverse.
  """
  @spec dist_from_zero(t(), number()) :: float()
  def dist_from_zero(transform, v) do
    Point.dist(
      apply_to(transform, Point.new(v, 0.0)),
      apply_to(transform, Point.origin())
    )
  end

  @doc """
  `dist_from_zero/2` measured through the inverse.

  Returns `{:error, :non_invertible}` for a singular transform.
  """
  @spec dist_from_inverted_zero(t(), number()) :: {:ok, float()} | {:error, :non_invertible}
  def dist_from_inverted_zero(transform, v) do
    with {:ok, inverse} <- invert(transform) do
      {:ok, dist_from_zero(inverse, v)}
    end
  end
end

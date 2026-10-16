defmodule Girihelix.Engine.Geometry.Polygon do
  @moduledoc """
  A polygon: a closed list of points, with area, length and containment.

  Ported from `geometry/Polygon.java`. It is a **value**: equality is structural
  and order-sensitive, with no identity semantics. That is the opposite of the
  graph nodes in `Map`, which are identities.

  The Java's growable-array machinery — a backing array, a `size` cursor, a `grow`
  policy and an `ensureSize/1` that reallocates on every insert — is not ported.
  A list is already growable, so three of the five Java constructors have no
  counterpart here, and `addVertex`/`setVertex` are replaced by building a new
  polygon from a list.
  """

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Transform

  @enforce_keys [:points]
  defstruct [:points]

  @type t :: %__MODULE__{points: [Point.t()]}

  @doc "Builds a polygon from its vertices, in order."
  @spec new([Point.t()]) :: t()
  def new(points) when is_list(points), do: %__MODULE__{points: points}

  @doc "The vertices, in order."
  @spec points(t()) :: [Point.t()]
  def points(%__MODULE__{points: points}), do: points

  @doc "How many vertices the polygon has."
  @spec num_vertices(t()) :: non_neg_integer()
  def num_vertices(%__MODULE__{points: points}), do: length(points)

  @doc """
  The vertex at `index`.

  Raises when out of range. The Java's `getVertex` does not check against its
  `size`, so it can read a spare array slot and return `null` — a caller that
  trusts it can be handed nothing rather than an error.
  """
  @spec vertex(t(), non_neg_integer()) :: Point.t()
  def vertex(%__MODULE__{points: points}, index) do
    case Enum.fetch(points, index) do
      {:ok, point} -> point
      :error -> raise ArgumentError, "vertex index #{index} out of range"
    end
  end

  @doc "Applies a transform to every vertex, returning a new polygon."
  @spec apply_transform(t(), Transform.t()) :: t()
  def apply_transform(%__MODULE__{points: points}, %Transform{} = transform) do
    %__MODULE__{points: Enum.map(points, &Transform.apply_to(transform, &1))}
  end

  @doc """
  The shoelace area, with the sign discarded.

  Raises on an empty polygon. The Java's `% size` divides by zero and raises
  `ArithmeticException`; returning `0.0` here would turn an error into a value.
  """
  @spec area(t()) :: float()
  def area(%__MODULE__{points: []}) do
    raise ArgumentError, "an empty polygon has no area"
  end

  def area(%__MODULE__{points: points}) do
    vertices = List.to_tuple(points)
    size = tuple_size(vertices)

    total =
      Enum.reduce(0..(size - 1), 0.0, fn index, acc ->
        %Point{x: x1, y: y1} = elem(vertices, index)
        %Point{x: x2, y: y2} = elem(vertices, rem(index + 1, size))
        acc + (x1 * y2 - y1 * x2)
      end)

    abs(total) * 0.5
  end

  @doc """
  The length of the path through the vertices.

  When `closed`, the edge from the last vertex back to the first is included.
  Raises on an empty **closed** polygon, where the Java indexes out of bounds;
  an empty open path is legitimately zero.
  """
  @spec arc_length(t(), boolean()) :: float()
  def arc_length(%__MODULE__{points: []}, true) do
    raise ArgumentError, "an empty polygon has no closed perimeter"
  end

  def arc_length(%__MODULE__{points: []}, false), do: 0.0

  def arc_length(%__MODULE__{points: points}, closed) do
    open =
      points
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.reduce(0.0, fn [a, b], acc -> acc + Point.dist(a, b) end)

    if closed do
      open + Point.dist(List.first(points), List.last(points))
    else
      open
    end
  end

  @doc """
  Whether a point lies inside the polygon.

  Returns `false` for an empty polygon: it contains nothing, and the Java's
  out-of-bounds index is not a more useful answer.

  A point exactly **on** the boundary is not reported reliably either way, and the
  asymmetry is inherited from the source: the lower and left edges of the unit
  square count as inside while the upper and right edges do not, and three of its
  four corners report as outside. Pin it in a test before relying on it — see
  `point_in_poly/2`.
  """
  @spec contains_point?(t(), Point.t()) :: boolean()
  def contains_point?(%__MODULE__{points: []}, %Point{}), do: false

  def contains_point?(%__MODULE__{points: points}, %Point{} = probe), do: point_in_poly(points, probe)

  @doc """
  The even-odd containment test, over a **closed** list of points.

  From Bob Stein's *A Point about Polygons*, as the Java's comment records. A
  crossing ray is counted with a half-open straddle test in x, which is what makes
  a ray passing exactly through a vertex count once rather than twice, and the
  crossing test itself uses no division.

  Despite the Java's variable being named `outside`, the result is **true for
  inside** — a ray crosses a closed polygon an odd number of times exactly when
  the point is within it.

  **A point exactly on the boundary is not reliably classified, and the answer is
  asymmetric.** The straddle test is half-open in x, so the lower and left edges of
  a shape count as inside while the upper and right edges do not, and three of the
  unit square's four corners report as outside the square. This is faithful to the
  source and is reachable — `Infer` asks this question of intersection points that
  can land on a boundary — so it is tested rather than left to be discovered.

  The Java also accepts a `start`/`end` slice, and its index arithmetic wraps
  against the slice length rather than the array, so any `start > 0` reads the
  wrong vertices. That form is not exposed here: every call site in the reference
  tree passes `start = 0`, and a port that reproduced the bug would be
  reproducing something no caller ever asked for.
  """
  @spec point_in_poly([Point.t()], Point.t()) :: boolean()
  def point_in_poly([], %Point{}), do: false

  def point_in_poly([first | _] = points, %Point{x: x, y: y}) do
    vertices = List.to_tuple(points)
    size = tuple_size(vertices)

    {_last, inside} =
      Enum.reduce(0..(size - 1), {first, false}, fn index, {previous, inside} ->
        current = elem(vertices, rem(index + 1, size))
        {current, straddles?(previous, current, x, y, inside)}
      end)

    inside
  end

  # Normalise the edge so that (xmin, ymin) is its lower-x end, then ask whether
  # the point is above the edge at this x. Strict `>` throughout, so a point
  # exactly on an edge does not toggle.
  defp straddles?(%Point{x: ax, y: ay}, %Point{x: bx, y: by}, x, y, inside) do
    {xmin, ymin, xmax, ymax} = if ax < bx, do: {ax, ay, bx, by}, else: {bx, by, ax, ay}

    if xmin <= x and x < xmax and (x - xmin) * (ymax - ymin) > (y - ymin) * (xmax - xmin) do
      not inside
    else
      inside
    end
  end
end

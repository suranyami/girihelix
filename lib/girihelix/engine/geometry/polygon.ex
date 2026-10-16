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

  **Failures are data.** `area/1`, `arc_length/2` and `vertex/2` return
  `{:ok, result} | {:error, reason}` where the Java threw. `contains_point?/2` and
  `point_in_poly/2` cannot fail and return booleans. The closing edge is implicit:
  do not repeat the first vertex as the last.
  """

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Transform

  @enforce_keys [:points]
  defstruct [:points]

  @type t :: %__MODULE__{points: [Point.t()]}

  @type reason :: :empty_polygon | :out_of_range

  @doc """
  Builds a polygon from its vertices, in order.

  The polygon is closed implicitly — the edge from the last vertex back to the
  first is part of it — so the first vertex must not be repeated at the end.
  """
  @spec new([Point.t()]) :: t()
  def new(points) when is_list(points), do: %__MODULE__{points: points}

  @doc "The vertices, in order."
  @spec points(t()) :: [Point.t()]
  def points(%__MODULE__{points: points}), do: points

  @doc "How many vertices the polygon has."
  @spec num_vertices(t()) :: non_neg_integer()
  def num_vertices(%__MODULE__{points: points}), do: length(points)

  @doc """
  The vertex at `index`, or `{:error, :out_of_range}`.

  The Java's `getVertex` does not check against its `size`, so it can read a spare
  array slot and return `null` — a caller that trusts it can be handed nothing
  rather than data it can match.
  """
  @spec vertex(t(), non_neg_integer()) :: {:ok, Point.t()} | {:error, :out_of_range}
  def vertex(%__MODULE__{points: points}, index) do
    case Enum.fetch(points, index) do
      {:ok, point} -> {:ok, point}
      :error -> {:error, :out_of_range}
    end
  end

  @doc "Applies a transform to every vertex, returning a new polygon."
  @spec apply_transform(t(), Transform.t()) :: t()
  def apply_transform(%__MODULE__{points: points}, %Transform{} = transform) do
    %__MODULE__{points: Enum.map(points, &Transform.apply_to(transform, &1))}
  end

  @doc """
  The shoelace area, with the sign discarded.

  Returns `{:error, :empty_polygon}` for an empty polygon. The Java's `% size`
  divides by zero and raises `ArithmeticException`; returning a value here would
  turn an error into something that looks like an answer.
  """
  @spec area(t()) :: {:ok, float()} | {:error, :empty_polygon}
  def area(%__MODULE__{points: []}), do: {:error, :empty_polygon}
  def area(%__MODULE__{points: points}), do: {:ok, shoelace(points)}

  @doc """
  The length of the path through the vertices.

  When `closed` is true the edge from the last vertex back to the first is
  included. An empty **closed** polygon reports `{:error, :empty_polygon}`, where
  the Java indexes out of bounds; an empty open path is legitimately `{:ok, 0.0}`.
  """
  @spec arc_length(t(), boolean()) :: {:ok, float()} | {:error, :empty_polygon}
  def arc_length(%__MODULE__{points: []}, true), do: {:error, :empty_polygon}
  def arc_length(%__MODULE__{points: []}, false), do: {:ok, 0.0}

  def arc_length(%__MODULE__{points: points}, true) do
    {:ok, open_length(points) + Point.dist(List.first(points), List.last(points))}
  end

  def arc_length(%__MODULE__{points: points}, false), do: {:ok, open_length(points)}

  @doc """
  Whether a point lies inside the polygon.

  False for an empty polygon: it contains nothing, and the Java's out-of-bounds
  index is not a more useful answer. Cannot fail, so it returns a boolean rather
  than a tuple.

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

  defp shoelace(points) do
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

  defp open_length(points) do
    points
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(0.0, fn [a, b], acc -> acc + Point.dist(a, b) end)
  end

  # Normalise the edge so that (xmin, ymin) is its lower-x end, then ask whether
  # the point is above the edge at this x. Strict `>` throughout, so a point
  # exactly on an edge does not toggle.
  defp straddles?(previous, current, x, y, inside) do
    {xmin, ymin, xmax, ymax} = bounds(previous, current)

    flip(
      xmin <= x and x < xmax,
      (x - xmin) * (ymax - ymin) > (y - ymin) * (xmax - xmin),
      inside
    )
  end

  defp bounds(%Point{x: ax, y: ay}, %Point{x: bx, y: by}) when ax < bx, do: {ax, ay, bx, by}
  defp bounds(%Point{x: ax, y: ay}, %Point{x: bx, y: by}), do: {bx, by, ax, ay}

  defp flip(true, true, inside), do: not inside
  defp flip(_straddles, _above, inside), do: inside
end

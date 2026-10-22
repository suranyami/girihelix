defmodule Girihelix.Engine.Tilings.Feature do
  @moduledoc """
  A tile of a tiling: its catalogue id, whether it is a regular polygon, and its
  points.

  This is the value behind Taprats' tiling `feature` class: `id` comes from the
  catalogue once `assign_ids/1` has deduplicated across descriptions, `regular`
  is a symmetry order when the tile is a regular polygon — and a polygon that
  stores its own points carries `nil` — and `points` is the tile's outline in
  order.

  **A regular feature computes its points on demand.** A constructor that only
  knows a symmetry order stores no outline at all; `points/1` then generates the
  polygon that Taprats' `RegularFeature` draws: the vertices of the regular
  `n`-gon whose edge midpoint sits at radius `1 / cos(pi / n)`, starting a half
  step along the circle. `points/1` is therefore total for any feature, and
  callers never keep a second copy of the outline in sync.

  **The features themselves are plain values** — no structural invariant a
  caller can break, so `new/1` is total and returns the struct directly. The
  provisional id `-1` marks a feature that no catalogue has assigned yet.

  Equality is **tolerant**, not structural: `equal?/2` compares the `regular`
  flags exactly and the point lists position by position under `Loose.equals/2`,
  because two descriptions of the same tile may differ in their last stored
  digits.
  """

  alias Girihelix.Engine.Figures.RadialFigure
  alias Girihelix.Engine.Geometry.Loose
  alias Girihelix.Engine.Geometry.Point

  @provisional_id -1

  @enforce_keys [:id, :regular, :points]
  defstruct [:id, :regular, :points]

  @type t :: %__MODULE__{id: integer(), regular: pos_integer() | nil, points: [Point.t()]}

  @doc """
  Builds a feature with the provisional id `-1`.

  A feature that is a regular polygon of symmetry order `regular` stores no
  points; `points/1` generates them. Any other feature carries its stored
  `points` and `nil` for `regular`.
  """
  @spec new(regular: pos_integer() | nil, points: [Point.t()]) :: t()
  def new(regular: regular, points: points), do: %__MODULE__{id: @provisional_id, regular: regular, points: points}

  @doc """
  The feature's outline, in order.

  For a regular polygon, this is the generated `n`-gon of `new/1`'s doc: vertex
  `i` for `i` in `0..(n-1)` sits at radius `1 / cos(pi / n)`, at angle
  `(2i + 1) * pi / n`, which is `RadialFigure.arc((2i + 1) / (2n))` scaled.
  """
  @spec points(t()) :: [Point.t()]
  def points(%__MODULE__{regular: nil, points: points}), do: points

  def points(%__MODULE__{regular: regular}) when is_integer(regular) and regular > 0, do: regular_points(regular)

  @doc """
  Tolerant structural equality: equal `regular` flags, and equal point lists
  under `Loose.equals/2`, in order.

  Lists of different lengths are unequal, whatever their points do. Like
  `Loose.equals/2` itself, the relation is not transitive, so do not use a
  feature as a set or map key.
  """
  @spec equal?(t(), t()) :: boolean()
  def equal?(%__MODULE__{regular: regular, points: a}, %__MODULE__{regular: regular, points: b}),
    do: point_lists_equal(a, b)

  def equal?(%__MODULE__{regular: _}, %__MODULE__{regular: _}), do: false

  defp point_lists_equal([], []), do: true
  defp point_lists_equal([], [_ | _]), do: false
  defp point_lists_equal([_ | _], []), do: false

  defp point_lists_equal([pa | rest_a], [pb | rest_b]), do: Loose.equals(pa, pb) and point_lists_equal(rest_a, rest_b)

  @doc """
  Assigns catalogue ids `0..k-1` across the list.

  Each feature is compared, in order, against the representatives already
  assigned, using `equal?/2`; the first match shares that representative's id,
  and a feature matching none is appended with the next unused id. Features come
  back in input order carrying stable ids, one per distinct tile.
  """
  @spec assign_ids([t()]) :: [t()]
  def assign_ids(features) do
    {assigned, _next} = Enum.reduce(features, {[], 0}, &assign_one/2)

    assigned
    |> Enum.reverse()
    |> Enum.map(fn {feature, _id} -> feature end)
  end

  defp assign_one(feature, {assigned, next}) do
    case find_id(assigned, feature) do
      {:ok, id} -> record(assigned, feature, id, next)
      {:error, :new} -> record(assigned, feature, next, next + 1)
    end
  end

  # `{feature, id}` pairs so `find_id/2` can compare against the already-assigned
  # representatives without re-deriving their ids.
  defp record(assigned, feature, id, next), do: {[{%{feature | id: id}, id} | assigned], next}

  defp find_id([], _feature), do: {:error, :new}
  defp find_id([{rep, id} | rest], feature), do: matched(equal?(rep, feature), id, rest, feature)

  # Literal `true`/`false` clauses rather than a `case` or `if`: the branch is
  # on a computed boolean, so it splits across heads.
  defp matched(true, id, _rest, _feature), do: {:ok, id}
  defp matched(false, _id, rest, feature), do: find_id(rest, feature)

  defp regular_points(n) do
    radius = 1.0 / :math.cos(:math.pi() / n)

    Enum.map(0..(n - 1), fn i ->
      Point.scale(RadialFigure.arc((2 * i + 1) / (2 * n)), radius)
    end)
  end
end

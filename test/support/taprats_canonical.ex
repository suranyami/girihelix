defmodule Girihelix.TapratsHarness.Canonical do
  @moduledoc """

  The construct half of the Taprats harness: running a `construct` op, the
  canonical map form, and the canonical comparison.

  Java's `Prototype.construct` merges feature maps in `Hashtable` iteration
  order, so which noise-y vertex of a coincident cluster survives a merge
  (lexComparePoints treats positions within `Point.TOLERANCE` as equal) is
  unspecified. The comparison is therefore canonical: sorted rounded
  positions, sorted edge position pairs, and rings as cycles of neighbour
  positions rotated to each cycle's smallest position, with coordinates
  compared within `1.0e-12`.
  """

  alias Girihelix.Engine.Figures.Rosette
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Tilings.Construct
  alias Girihelix.Engine.Tilings.Feature
  alias Girihelix.Engine.Tilings.Parser
  alias Girihelix.TapratsHarness

  @tolerance 1.0e-12
  @tilings_dir "reference/1.1.12/tilings/"

  @type verify :: true | false | :npe | :unchecked

  @typedoc """
  The canonical form of a constructed map: vertices as rounded positions
  sorted, edges as sorted pairs of endpoint positions, rings as sorted cycles
  of neighbour positions, and the `verify` word.
  """
  @type canonical_map :: %{
          vertices: [{float(), float()}],
          edges: [{{float(), float()}, {float(), float()}}],
          rings: [[{float(), float()}]],
          verify: verify()
        }

  # -- running a construct op ---------------------------------------------------

  @doc """
  Constructs the tiling named by a `construct` operation.

  Reads `reference/1.1.12` `tilings/<name>.tiling` — the same file the Java
  driver reads — binds `Rosette.new!(sides, 0.0, 3)` to every regular feature,
  leaves polygon features unbound (as the Java driver does), constructs over
  `Construct.default_region/1` and returns the canonical dump of the welded
  map. A load or construct failure raises, like every other malformed-script
  failure.
  """
  @spec construct(String.t()) :: %{construct: canonical_map()}
  def construct(name) do
    tiling = tiling!(name)

    map = Construct.construct!(tiling, &rosette_binding/1, Construct.default_region(tiling))
    %{construct: canonical(map)}
  end

  # Like the Java driver: a load failure raises, since the scenario file names
  # a catalogue tiling that must exist.
  defp tiling!(name) do
    case Parser.parse_file(@tilings_dir <> name <> ".tiling") do
      {:ok, tiling} ->
        tiling

      {:error, reason} ->
        raise ArgumentError, "cannot load tiling #{inspect(name)}: #{inspect(reason)}"
    end
  end

  # The golden binding: `Rosette(n, 0.0, 3)` on every regular feature, and
  # nothing on polygon features.
  defp rosette_binding(%Feature{regular: nil}), do: nil

  defp rosette_binding(%Feature{regular: sides}), do: Rosette.new!(sides, 0.0, 3)

  # -- canonical form ------------------------------------------------------------

  @doc """
  The canonical form of a constructed map.

  Vertices are the rounded positions sorted; edges are sorted pairs of endpoint
  positions, each pair ordered within itself; rings are cycles of neighbour
  positions, each rotated to start at the cycle's smallest position, then the
  cycles sorted. Coordinates to `1.0e-12`.
  """
  @spec canonical(PlanarMap.t()) :: canonical_map()
  def canonical(map), do: map |> TapratsHarness.dump() |> canonical_from_dump()

  # Both sides of a golden come through here: the live map via `dump/1`, the
  # fixture via `parse_map_dump/1`.
  @doc "The canonical form of a raw index-based map dump, as parsed from a fixture."
  @spec canonical_from_dump(TapratsHarness.map_dump()) :: canonical_map()
  def canonical_from_dump(raw) do
    corners = Enum.map(raw.vertices, &round_corner/1)

    edge_endpoints =
      Enum.map(raw.edges, fn {i, j} -> {corner_at(corners, i), corner_at(corners, j)} end)

    cycles =
      raw.rings
      |> Enum.with_index()
      |> Enum.map(fn {ring, k} -> Enum.map(ring, &far_corner(&1, k, raw.edges, corners)) end)
      |> Enum.map(&normalise_cycle/1)

    %{
      vertices: Enum.sort(corners),
      edges: edge_endpoints |> Enum.map(&order_pair/1) |> Enum.sort(),
      rings: Enum.sort(cycles),
      verify: raw.verify
    }
  end

  defp corner_at(corners, index), do: Enum.fetch!(corners, index)

  defp round_corner({x, y}), do: {round12(x), round12(y)}

  # The trailing + 0.0 folds a negative zero into a positive one, so the two
  # sides of a golden cannot disagree on the sign of zero in a sort key.
  defp round12(value), do: Float.round(value, 12) + 0.0

  defp order_pair({a, b}) when a <= b, do: {a, b}
  defp order_pair({a, b}), do: {b, a}

  defp normalise_cycle([]), do: []

  defp normalise_cycle(cycle) do
    cycle
    |> rotations(cycle, length(cycle), [])
    |> Enum.min()
  end

  # `rotations/4` accumulates every rotation of `cycle`: dropping the first n
  # elements and appending them at the back.
  defp rotations(_cycle, _remaining, 0, acc), do: acc

  defp rotations(cycle, remaining, n, acc) do
    rotated = remaining ++ Enum.take(cycle, length(cycle) - length(remaining))

    rotations(cycle, tl(remaining), n - 1, [rotated | acc])
  end

  defp far_corner(edge_index, vertex_index, edges, corners) do
    {a, b} = Enum.fetch!(edges, edge_index)
    Enum.fetch!(corners, far_index(a, b, vertex_index))
  end

  defp far_index(a, b, k) when a == k, do: b
  defp far_index(a, _b, _k), do: a

  # The canonical comparison reports the first differing component: counts come
  # before positions, vertices before edges, edges before rings, and the verify
  # word last.
  @doc "The construct comparison: the first differing component, as one error or none."
  @spec construct_errors(canonical_map(), canonical_map()) :: [String.t()]
  def construct_errors(expected, actual) do
    [
      vertex_component(expected.vertices, actual.vertices),
      edge_component(expected.edges, actual.edges),
      ring_component(expected.rings, actual.rings),
      verify_errors(expected.verify, actual.verify)
    ]
    |> Enum.find(&(!match?([], &1)))
    |> List.wrap()
  end

  # The two sorted canonical lists are walked together, matching heads within
  # the coordinate tolerance rather than rank for rank. Rounding to 12 decimals
  # can split one value into two different sort spellings on the two sides — a
  # raw coordinate carrying construction noise straddles a rounding boundary,
  # seen on 3-8-4-6 — so entries of the same vertex can sit at neighbouring
  # ranks, and the walk records the entries it had to skip past. The skipped
  # entries from the two sides are then paired against each other by the same
  # walk, until nothing is left or nothing more matches.
  defp walked(label, close, expected, actual) do
    {skipped_expected, skipped_actual} = walk_skips(close, expected, actual, [], [])
    reconcile(label, close, skipped_expected, skipped_actual)
  end

  defp reconcile(_label, _close, [], []), do: []

  defp reconcile(label, _close, [expected | _rest], []),
    do: ["#{label}: expected #{inspect(expected)} has no partner on the actual side"]

  defp reconcile(label, _close, [], [actual | _rest]),
    do: ["#{label}: got #{inspect(actual)} with no partner on the expected side"]

  defp reconcile(label, close, skipped_expected, skipped_actual) do
    {rest_expected, rest_actual} = walk_skips(close, skipped_expected, skipped_actual, [], [])

    progressed(
      length(rest_expected) < length(skipped_expected),
      label,
      close,
      rest_expected,
      rest_actual
    )
  end

  defp progressed(true, label, close, rest_expected, rest_actual) do
    reconcile(label, close, rest_expected, rest_actual)
  end

  defp progressed(false, label, _close, [expected_rest | _rest], [actual_rest | _rests]) do
    ["#{label}: expected #{inspect(expected_rest)}, got #{inspect(actual_rest)}"]
  end

  # The skip walk itself: heads that agree are consumed, and whichever head is
  # first in sort order is skipped into the leftovers when they disagree.
  defp walk_skips(_close, [], [], skipped_expected, skipped_actual) do
    {Enum.reverse(skipped_expected), Enum.reverse(skipped_actual)}
  end

  defp walk_skips(_close, [], actual, skipped_expected, skipped_actual) do
    {Enum.reverse(skipped_expected), Enum.reverse(skipped_actual, actual)}
  end

  defp walk_skips(_close, expected, [], skipped_expected, skipped_actual) do
    {Enum.reverse(skipped_expected, expected), Enum.reverse(skipped_actual)}
  end

  defp walk_skips(close, [expected | expected_rest], [actual | actual_rest], skipped_expected, skipped_actual) do
    expected
    |> close.(actual)
    |> skip_or_match(
      close,
      expected,
      expected_rest,
      actual,
      actual_rest,
      skipped_expected,
      skipped_actual
    )
  end

  defp skip_or_match(true, close, _expected, expected_rest, _actual, actual_rest, skipped_expected, skipped_actual) do
    walk_skips(close, expected_rest, actual_rest, skipped_expected, skipped_actual)
  end

  defp skip_or_match(false, close, expected, expected_rest, actual, actual_rest, skipped_expected, skipped_actual) do
    skip_left(
      expected < actual,
      close,
      expected,
      expected_rest,
      actual,
      actual_rest,
      skipped_expected,
      skipped_actual
    )
  end

  defp skip_left(true, close, expected, expected_rest, actual, actual_rest, skipped_expected, skipped_actual) do
    walk_skips(
      close,
      expected_rest,
      [actual | actual_rest],
      [expected | skipped_expected],
      skipped_actual
    )
  end

  defp skip_left(false, close, expected, expected_rest, actual, actual_rest, skipped_expected, skipped_actual) do
    walk_skips(close, [expected | expected_rest], actual_rest, skipped_expected, [
      actual | skipped_actual
    ])
  end

  defp vertex_component(expected, actual) when length(expected) == length(actual) do
    walked("construct vertex", &corners_close/2, expected, actual)
  end

  defp vertex_component(expected, actual),
    do: ["construct vertex count: expected #{length(expected)}, got #{length(actual)}"]

  defp edge_component(expected, actual) when length(expected) == length(actual) do
    walked("construct edge", &edge_close/2, expected, actual)
  end

  defp edge_component(expected, actual), do: ["construct edge count: expected #{length(expected)}, got #{length(actual)}"]

  defp ring_component(expected, actual) when length(expected) == length(actual) do
    walked("construct ring", &ring_close/2, expected, actual)
  end

  defp ring_component(expected, actual), do: ["construct ring count: expected #{length(expected)}, got #{length(actual)}"]

  # A whole cycle matches when every position matches. A mismatched cycle is
  # reported as one error, so the first differing component reads at a glance.
  defp ring_close(expected, actual) when length(expected) == length(actual) do
    expected
    |> Enum.zip(actual)
    |> Enum.all?(fn {e, a} -> corners_close(e, a) end)
  end

  defp ring_close(_expected, _actual), do: false

  defp corners_close({ex, ey}, {ax, ay}) when abs(ex - ax) < @tolerance and abs(ey - ay) < @tolerance, do: true

  defp corners_close(_expected, _actual), do: false

  defp edge_close({e1, e2}, {a1, a2}), do: corners_close(e1, a1) and corners_close(e2, a2)

  # -- verify word ------------------------------------------------------------

  @doc """
  The `verify` word check shared by every dump comparison: the word is
  skipped when `actual.verify` is `:unchecked`, or when `expected.verify` is
  not `true`.
  """
  @spec verify_errors(verify(), verify()) :: [String.t()]
  def verify_errors(_expected, :unchecked), do: []
  def verify_errors(true, true), do: []
  def verify_errors(true, actual), do: ["verify: expected true, got #{inspect(actual)}"]
  def verify_errors(_expected, _actual), do: []
end

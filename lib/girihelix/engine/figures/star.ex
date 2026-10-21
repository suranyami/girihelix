defmodule Girihelix.Engine.Figures.Star do
  @moduledoc """
  The classic `[n/d]s` star construction.

  The unit is a symmetric chain of the crossings of one base chord with rotated
  copies of itself. `n` is the symmetry order, `d` the continuous skip and `s`
  how many crossings the unit takes. The chain grows from `(1, 0)` along the
  chord to `arc(clamp_d * don)`; each crossing is inserted with its mirror in
  the x axis. When `clamp_s == di` the unit closes at the rotated apex, adding
  one edge for an integral `d` or the extra `cent` vertex and two edges
  otherwise.

  **`outer_s` and `clamp_s` use the pre-increment `di`.** The `dfrac ≈ 1` snap
  rounds `di` up after both have been taken, so that path is one step short and
  its closure cannot fire. That is the behaviour to reproduce, and it is pinned
  by a test.

  **The closure crossing uses the raw `d`, not `clamp_d`.** When a star is
  clamped, its ordinary chord crossings use the clamped skip while `cent` still
  uses the requested one, so the closure geometry differs from the rest of the
  unit. The `figure-star-clamped` golden pins it.

  **A failed intersection raises.** The two unguarded sites raise
  `ArgumentError` naming `degenerate_crossing` rather than substituting a point.
  The canonical crash case is `(n, d, s) = (8, 7.02, 3)`, where the closure's
  `cent` intersection is nil; a unit test and the `figure-star-crash` golden pin
  it.
  """

  @behaviour Girihelix.Engine.Figures.RadialFigure

  import Girihelix.Engine.Steps, only: [step: 4]

  alias Girihelix.Engine.Figures.RadialFigure
  alias Girihelix.Engine.Geometry.Intersect
  alias Girihelix.Engine.Geometry.Loose
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Segment
  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Steps

  @enforce_keys [:n, :d, :clamp_d, :s]
  defstruct [:n, :d, :clamp_d, :s]

  @type t :: %__MODULE__{n: pos_integer(), d: float(), clamp_d: float(), s: non_neg_integer()}
  @type reason :: :invalid_order | :invalid_step_count
  @type state :: map()

  # Read at compile time so the snap's guards can use it: a guard cannot call a
  # function, and duplicating the literal here would let the two drift apart.
  @tol Loose.tol()

  @doc """
  A star of order `n`, skip `d` and step count `s`.

  `d` is stored raw beside its clamped value, and `s` as
  `clamp_s = min(s, di)` using the pre-snap `di`. `n < 3` and `s < 0` are
  refused rather than raising.
  """
  @spec new(pos_integer(), float(), integer()) :: {:ok, t()} | {:error, reason()}
  def new(n, d, s), do: build(n, d, s)

  defp build(n, _d, _s) when n < 3, do: {:error, :invalid_order}
  defp build(_n, _d, s) when s < 0, do: {:error, :invalid_step_count}

  defp build(n, d, s) do
    clamp_d = clamp_d(n, d)

    {:ok, %__MODULE__{n: n, d: d * 1.0, clamp_d: clamp_d, s: clamp_s(s, trunc(:math.floor(clamp_d)))}}
  end

  @doc "`new/3` for a caller that has established the parameters, raising otherwise."
  @spec new!(pos_integer(), float(), integer()) :: t()
  def new!(n, d, s) do
    case new(n, d, s) do
      {:ok, star} -> star
      {:error, reason} -> raise ArgumentError, "star: #{reason}"
    end
  end

  @doc "`max(1.0, min(d, 0.5 * n - 0.01))`: the skip stays just inside half the order."
  @spec clamp_d(pos_integer(), float()) :: float()
  def clamp_d(n, d), do: max(1.0, min(d * 1.0, 0.5 * n - 0.01))

  @doc "`min(s, di)`: the stored step count cannot exceed the skip's integer part."
  @spec clamp_s(integer(), integer()) :: non_neg_integer()
  def clamp_s(s, di), do: min(s, di)

  @doc "The state `steps/3` starts from: parameters only, every derived field empty."
  @spec start(pos_integer(), float(), integer()) :: state()
  def start(n, d, s) do
    %{
      n: n,
      d: d,
      s: s,
      figure: nil,
      map: nil,
      clamp_d: nil,
      clamp_s: nil,
      did: nil,
      di: nil,
      dfrac: nil,
      is_int: nil,
      outer_s: nil,
      a: nil,
      b: nil,
      points: [],
      top: nil,
      bottom: nil
    }
  end

  @doc "The five stages that build the unit."
  @spec steps(pos_integer(), float(), integer()) :: [Steps.Step.t()]
  def steps(_n, _d, _s) do
    [
      step(
        :clamp,
        "clamp d and s",
        "Builds the struct, snaps dfrac, records di, is_int and outer_s.",
        &clamp/1
      ),
      step(:chord, "the base chord", "Sets a = (1, 0) and b = arc(clamp_d * don).", &chord/1),
      step(
        :crossings,
        "the crossings",
        "Intersects the base chord with one rotated copy per step.",
        &crossings/1
      ),
      step(
        :assemble,
        "mirror and insert",
        "Inserts the tip, each crossing and its mirror, and the two chains.",
        &assemble/1
      ),
      step(
        :closure,
        "close the unit",
        "Adds the rotated-apex edge, or cent and two edges.",
        &closure/1
      )
    ]
  end

  @doc "The built map."
  @spec result(state()) :: PlanarMap.t()
  def result(%{map: map}), do: map

  @impl RadialFigure
  @spec build_unit(t()) :: PlanarMap.t()
  def build_unit(%__MODULE__{n: n, d: d, s: s}) do
    n
    |> steps(d, s)
    |> Steps.run!(start(n, d, s))
    |> Steps.final()
    |> result()
  end

  @impl RadialFigure
  @spec n(t()) :: pos_integer()
  def n(%__MODULE__{n: n}), do: n

  # -- the stages -------------------------------------------------------------

  defp clamp(state) do
    figure = new!(state.n, state.d, state.s)
    did = :math.floor(figure.clamp_d)
    {di, dfrac, is_int} = snap(did, figure.clamp_d - did)
    di_pre = trunc(did)

    %{
      state
      | figure: figure,
        clamp_d: figure.clamp_d,
        clamp_s: clamp_s(state.s, di_pre),
        did: did,
        di: di,
        dfrac: dfrac,
        is_int: is_int,
        outer_s: min(state.s, di_pre - 1)
    }
  end

  # The three snap heads, in this order: the strict `<` matters.
  defp snap(did, dfrac) when dfrac < @tol, do: {trunc(did), 0.0, true}
  defp snap(did, dfrac) when 1.0 - dfrac < @tol, do: {trunc(did) + 1, 0.0, true}
  defp snap(did, dfrac), do: {trunc(did), dfrac, false}

  defp chord(state) do
    b = RadialFigure.arc(state.clamp_d * RadialFigure.don(state.n))
    %{state | a: Point.new(1.0, 0.0), b: b}
  end

  defp crossings(state) do
    base = Segment.new!(state.a, state.b)
    don = RadialFigure.don(state.n)

    points =
      Enum.map(1..state.outer_s//1, fn idx ->
        ar = RadialFigure.arc(idx * don)
        br = RadialFigure.arc((idx - state.clamp_d) * don)
        intersection!(base, Segment.new!(ar, br))
      end)

    %{state | points: points}
  end

  defp assemble(state) do
    {map, top, bottom} = RadialFigure.mirrored_chain(state.a, state.points)
    %{state | map: map, top: top, bottom: bottom}
  end

  defp closure(%{clamp_s: clamp_s, di: di} = state) when clamp_s != di, do: state

  defp closure(state) do
    apex = state.map |> PlanarMap.position!(state.top) |> rotate(state.n)
    {map, vertex} = PlanarMap.insert_vertex(state.map, apex)
    close_apex(%{state | map: map}, vertex)
  end

  defp close_apex(%{is_int: true, map: map, top: top} = state, apex) do
    %{state | map: PlanarMap.insert_edge!(map, top, apex)}
  end

  defp close_apex(%{map: map, top: top, a: a} = state, apex) do
    don = RadialFigure.don(state.n)
    ar = RadialFigure.arc(state.did * don)
    br = RadialFigure.arc(-state.dfrac * don)

    # The closure crossing uses the raw d, not clamp_d.
    cent = intersection!(Segment.new!(ar, br), Segment.new!(a, RadialFigure.arc(state.d * don)))

    {map, vertex} = PlanarMap.insert_vertex(map, cent)
    map = PlanarMap.insert_edge!(map, top, vertex)
    %{state | map: PlanarMap.insert_edge!(map, vertex, apex)}
  end

  defp rotate(point, n), do: Transform.apply_to(RadialFigure.tr(n), point)

  defp intersection!(first, second) do
    case Intersect.get_intersection(first, second) do
      nil -> raise ArgumentError, "star: degenerate_crossing"
      point -> point
    end
  end
end

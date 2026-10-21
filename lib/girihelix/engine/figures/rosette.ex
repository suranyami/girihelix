defmodule Girihelix.Engine.Figures.Rosette do
  @moduledoc """
  Lee's rosette, a port of Taprats' `Rosette.java`.

  `n` is the symmetry order, `q` the blend weight that swings the key ray and
  `s` how many rotated copies of the key line the unit intersects. The unit is
  a mirror-symmetric chain from `(1, 0)`: the key point, then one crossing per
  step, each inserted with its x-axis mirror. The whole figure is that unit
  replicated under the symmetry ladder.

  **The constructor stores the clamped `q` and `s`.** The source stores the raw
  `q` in the field and clamps only inside `buildUnit`, but that clamp is
  idempotent, so storing the clamped value changes no geometry and keeps the
  struct's contract (`|q| <= 0.99`) true for every reader. `s` is clamped with
  Java's integer division, `min(s, (n - 1) / 2)`.

  **A parallel crossing is skipped, not substituted.** When a step's key line is
  parallel to its rotated mirror the source's `Intersect` returns `null`, and
  the source drops that point and carries on; the FIXME documents it. The port
  reproduces the skip and records the count in the build state's `skipped`
  field. Only a null **key** point, which the source would dereference, raises
  `ArgumentError` naming `degenerate_key`.
  """

  @behaviour Girihelix.Engine.Figures.RadialFigure

  import Girihelix.Engine.Steps, only: [step: 4]

  alias Girihelix.Engine.Figures.RadialFigure
  alias Girihelix.Engine.Geometry.Intersect
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Segment
  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Steps

  @enforce_keys [:n, :q, :s]
  defstruct [:n, :q, :s]

  @type t :: %__MODULE__{n: pos_integer(), q: float(), s: non_neg_integer()}
  @type reason :: :invalid_order | :invalid_step_count
  @type state :: map()

  @q_limit 0.99

  @doc """
  A rosette of order `n`, blend `q` and step count `s`.

  `q` is clamped to `[-0.99, 0.99]` and `s` to `min(s, (n - 1) / 2)` with
  integer division, and the clamped values are stored. `n < 3` and `s < 0` are
  refused rather than raising.
  """
  @spec new(pos_integer(), float(), integer()) :: {:ok, t()} | {:error, reason()}
  def new(n, q, s), do: build(n, q, s)

  defp build(n, _q, _s) when n < 3, do: {:error, :invalid_order}
  defp build(_n, _q, s) when s < 0, do: {:error, :invalid_step_count}
  defp build(n, q, s), do: {:ok, %__MODULE__{n: n, q: clamp_q(q), s: clamp_s(n, s)}}

  @doc "`new/3` for a caller that has established the parameters, raising otherwise."
  @spec new!(pos_integer(), float(), integer()) :: t()
  def new!(n, q, s) do
    case new(n, q, s) do
      {:ok, rosette} -> rosette
      {:error, reason} -> raise ArgumentError, "rosette: #{reason}"
    end
  end

  @doc "The source's `min(max(q, -0.99), 0.99)`."
  @spec clamp_q(float()) :: float()
  def clamp_q(q), do: min(max(q * 1.0, -@q_limit), @q_limit)

  @doc "The source's `min(s, (n - 1) / 2)` with Java's integer division."
  @spec clamp_s(pos_integer(), integer()) :: non_neg_integer()
  def clamp_s(n, s), do: min(s, div(n - 1, 2))

  @doc "A copy of `rosette` with `q` clamped, as `setQ` would store it."
  @spec with_q(t(), float()) :: t()
  def with_q(%__MODULE__{} = rosette, q), do: %{rosette | q: clamp_q(q)}

  @doc "A copy of `rosette` with `s` clamped, as `setS` does."
  @spec with_s(t(), integer()) :: t()
  def with_s(%__MODULE__{} = rosette, s), do: %{rosette | s: clamp_s(rosette.n, s)}

  @doc "The state `steps/3` starts from: parameters only, every derived field empty."
  @spec start(pos_integer(), float(), integer()) :: state()
  def start(n, q, s) do
    %{
      n: n,
      q: q,
      s: s,
      figure: nil,
      map: nil,
      frame: nil,
      q_clamp: nil,
      s_clamp: nil,
      points: [],
      top: nil,
      bottom: nil,
      skipped: 0
    }
  end

  @doc "The six stages that build the unit."
  @spec steps(pos_integer(), float(), integer()) :: [Steps.Step.t()]
  def steps(_n, _q, _s) do
    [
      step(
        :clamp,
        "clamp q and s",
        "Builds the struct and records q_clamp and s_clamp.",
        &clamp/1
      ),
      step(
        :frame,
        "Lee's outer geometry",
        "Sets the tip, r_outer, up_outer, bisector, th and the stable ray.",
        &frame/1
      ),
      step(:blend, "blend th", "Swings th toward the vertical or the stable angle.", &blend/1),
      step(:key, "the key line", "Intersects the tip ray with up_outer-bisector.", &key/1),
      step(
        :walk,
        "the rotated crossings",
        "Intersects the key line with rotated mirrors.",
        &walk/1
      ),
      step(
        :assemble,
        "mirror and insert",
        "Inserts the tip, each point and its mirror, and the two chains.",
        &assemble/1
      )
    ]
  end

  @doc "The built map."
  @spec result(state()) :: PlanarMap.t()
  def result(%{map: map}), do: map

  @impl RadialFigure
  @spec build_unit(t()) :: PlanarMap.t()
  def build_unit(%__MODULE__{n: n, q: q, s: s}) do
    n
    |> steps(q, s)
    |> Steps.run!(start(n, q, s))
    |> Steps.final()
    |> result()
  end

  @impl RadialFigure
  @spec n(t()) :: pos_integer()
  def n(%__MODULE__{n: n}), do: n

  # -- the stages -------------------------------------------------------------

  defp clamp(state) do
    figure = new!(state.n, state.q, state.s)

    %{state | figure: figure, q_clamp: clamp_q(figure.q), s_clamp: clamp_s(state.n, figure.s)}
  end

  defp frame(state) do
    n = state.n
    don = RadialFigure.don(n)
    tip = Point.new(1.0, 0.0)
    rtip = RadialFigure.arc(don)

    r_outer = 1.0 / :math.cos(:math.pi() * don)
    up_outer = Point.scale(RadialFigure.arc(0.5 * don), r_outer)
    bisector = up_outer |> Point.subtract(Point.new(0.0, r_outer)) |> Point.scale(0.5)
    th = Point.angle_to(tip, rtip)

    stable_isect = Point.add(up_outer, Point.scale(Point.normalize(up_outer), -up_outer.y))
    stable_angle = Point.angle_to(tip, stable_isect)

    frame = %{
      tip: tip,
      rtip: rtip,
      r_outer: r_outer,
      up_outer: up_outer,
      bisector: bisector,
      th: th,
      stable_isect: stable_isect,
      stable_angle: stable_angle
    }

    %{state | frame: frame}
  end

  # The two source branches, in its order: the strict non-negative head first.
  defp blend(%{frame: frame, q_clamp: q_clamp} = state) when q_clamp >= 0.0 do
    th = frame.th * (1.0 - q_clamp) + :math.pi() * 0.5 * q_clamp
    %{state | frame: %{frame | th: th}}
  end

  defp blend(%{frame: frame, q_clamp: q_clamp} = state) do
    th = frame.th * (1.0 + q_clamp) - frame.stable_angle * q_clamp
    %{state | frame: %{frame | th: th}}
  end

  defp key(%{frame: frame} = state) do
    qtip = Point.new(1.0 + :math.cos(frame.th), :math.sin(frame.th))
    key_point = key_point!(frame.tip, qtip, frame.up_outer, frame.bisector)
    key_end = Point.convex_sum(key_point, frame.stable_isect, 10.0)

    %{state | frame: Map.merge(frame, %{qtip: qtip, key_point: key_point, key_end: key_end})}
  end

  defp key_point!(tip, qtip, up_outer, bisector) do
    case Intersect.get_intersection(Segment.new!(tip, qtip), Segment.new!(up_outer, bisector)) do
      nil -> raise ArgumentError, "rosette: degenerate_key"
      point -> point
    end
  end

  # The mirrored key line is rotated in place each step: `Tr^idx` accumulates
  # through the carried points, it is never recomputed from the original.
  defp walk(%{frame: frame, n: n, s_clamp: s_clamp} = state) do
    key_line = Segment.new!(frame.key_point, frame.key_end)
    tr = RadialFigure.tr(n)
    mirror = {RadialFigure.mirror(frame.key_point), RadialFigure.mirror(frame.key_end)}

    {walked, _last} =
      Enum.map_reduce(1..s_clamp//1, mirror, fn _idx, {from, to} ->
        from = Transform.apply_to(tr, from)
        to = Transform.apply_to(tr, to)
        {Intersect.get_intersection(key_line, Segment.new!(from, to)), {from, to}}
      end)

    %{
      state
      | points: [frame.key_point | Enum.reject(walked, &is_nil/1)],
        skipped: Enum.count(walked, &is_nil/1)
    }
  end

  defp assemble(%{frame: frame, points: points} = state) do
    {map, top, bottom} = RadialFigure.mirrored_chain(frame.tip, points)
    %{state | map: map, top: top, bottom: bottom}
  end
end

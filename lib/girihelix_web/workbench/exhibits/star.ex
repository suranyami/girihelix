defmodule GirihelixWeb.Workbench.Exhibits.Star do
  @moduledoc """
  The classic `[n/d]s` star construction, stage by stage.

  The whole figure is the unit replicated under the symmetry ladder; the unit is
  the heavier chain drawn over it. The canvas marks the construction's starting
  point `(1, 0)`, draws the base chord `a → b` as a guide, marks every crossing
  the current frame has found, and on the `:closure` frame draws what closed the
  unit: the rotated-apex edge for an integral `d`, or the `cent` point for a
  fractional one, both in a distinct stroke.

  Frame zero draws the tip alone, and every intermediate frame draws only what
  its state has: the clamps and the chord before the crossings, the unit before
  the replicated figure. The whole figure is replicated from the unit the state
  holds rather than rebuilt, so a failed run's retained frames still draw.

  The panel reports the requested and clamped `d`, the snap's `di` and `frac`,
  the integral test, the stored and outer `s`, whether the closure fired, and
  the shared vertex, edge and verification rows.
  """

  @behaviour GirihelixWeb.Workbench.Exhibit

  alias Girihelix.Engine.Figures.Figure
  alias Girihelix.Engine.Figures.RadialFigure
  alias Girihelix.Engine.Figures.Star, as: StarFigure
  alias Girihelix.Engine.Geometry.Intersect
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Segment
  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Viewport
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibit
  alias GirihelixWeb.Workbench.Exhibits.Figures
  alias GirihelixWeb.Workbench.Exhibits.Format
  alias GirihelixWeb.Workbench.Param

  # The construction starts here, and the point is static even at frame zero.
  @closure_opts [width: 3.0, dash: "6 3"]
  @cent_opts [stroke: "currentColor", width: 2.0, opacity: 1.0]

  @impl true
  @spec slug() :: String.t()
  def slug, do: "star"

  @impl true
  @spec title() :: String.t()
  def title, do: "Star"

  @impl true
  def byline, do: "the [n/d]s construction"
  @impl true
  @spec summary() :: String.t()
  def summary, do: "A chord and its rotated copies, mirrored into a symmetric unit."

  @impl true
  @spec category() :: atom()
  def category, do: :figures

  @impl true
  @spec params() :: [Param.t()]
  def params do
    [
      %Param{
        name: :n,
        type: :integer,
        range: 3..24,
        default: 8,
        doc: "The star's symmetry order."
      },
      %Param{
        name: :d,
        type: :float,
        range: 1..10,
        step: 0.1,
        default: 3.0,
        doc: "The continuous skip."
      },
      %Param{
        name: :s,
        type: :integer,
        range: 1..6,
        default: 2,
        doc: "How many crossings the unit takes."
      }
    ]
  end

  @impl true
  @spec initial(map()) :: StarFigure.state()
  def initial(%{n: n, d: d, s: s}), do: StarFigure.start(n, d, s)

  @impl true
  @spec steps(map()) :: [Steps.Step.t()]
  def steps(%{n: n, d: d, s: s}), do: StarFigure.steps(n, d, s)

  @impl true
  @spec draw(Steps.Frame.t(), map()) :: Exhibit.drawing()
  def draw(%Steps.Frame{state: state} = frame, _params) do
    whole = Figures.whole_map(state)
    {:both, ops(state, whole, frame), rows(state, whole)}
  end

  @impl true
  @spec reproduce(map()) :: String.t()
  def reproduce(%{n: n, d: d, s: s}) do
    "Girihelix.Engine.Figures.Star.build_unit(" <>
      "Girihelix.Engine.Figures.Star.new!(#{Integer.to_string(n)}, " <>
      "#{Format.coordinate(d)}, #{Integer.to_string(s)}))"
  end

  @impl true
  @spec viewport(map()) :: Viewport.t()
  def viewport(%{n: n, d: d, s: s}) do
    Figures.viewport_for(fn -> n |> StarFigure.new!(d, s) |> Figure.map() end)
  end

  # The state's `map` is the unit; the whole figure is that unit replicated.
  # Replaying `Figure.map/1` would rebuild the unit and can re-raise a failure a
  # retained frame has already survived: for `n = 3` the closure raises after
  # `:assemble`, leaving a non-nil unit in the last frame of a failed run.
  defp ops(state, nil, _frame), do: partial_ops(state)

  defp ops(state, whole, frame) do
    Figures.map_ops(whole) ++
      Figures.unit_ops(state.map) ++ partial_ops(state) ++ closure_ops(frame, state)
  end

  defp partial_ops(state) do
    [Figures.tip_op()] ++ chord_ops(state) ++ crossing_ops(state)
  end

  defp chord_ops(%{a: %Point{} = a, b: %Point{} = b}) do
    from = Format.pair(a)
    to = Format.pair(b)
    [{:guide, from, to, []}, {:label, Format.midpoint(from, to), "base chord", []}]
  end

  defp chord_ops(_state), do: []

  defp crossing_ops(%{points: points}), do: Enum.map(points, &Figures.construction_op/1)

  defp closure_ops(%Steps.Frame{step: %Steps.Step{id: :closure}}, state), do: closure(state)
  defp closure_ops(_frame, _state), do: []

  defp closure(%{clamp_s: nil}), do: []
  defp closure(%{di: nil}), do: []
  defp closure(%{clamp_s: clamp_s, di: di}) when clamp_s != di, do: []
  defp closure(%{is_int: true} = state), do: apex_ops(state)
  defp closure(state), do: cent_ops(state)

  # An integral `d` closes on the rotated apex: the edge the engine inserted.
  defp apex_ops(%{map: map, top: top, n: n}) do
    from = PlanarMap.position!(map, top)
    apex = Transform.apply_to(RadialFigure.tr(n), from)
    pair_from = Format.pair(from)
    pair_apex = Format.pair(apex)

    [
      {:line, pair_from, pair_apex, @closure_opts},
      {:label, Format.midpoint(pair_from, pair_apex), "closure", []}
    ]
  end

  # A fractional `d` closes through `cent`, the crossing of the two chords the
  # engine computes with the raw `d`. The engine has already proved it exists.
  defp cent_ops(state) do
    case cent(state) do
      nil -> []
      point -> [{:point, Format.pair(point), 5.0, @cent_opts}]
    end
  end

  defp cent(%{n: n, did: did, dfrac: dfrac, d: d, a: %Point{} = a}) do
    don = RadialFigure.don(n)
    ar = RadialFigure.arc(did * don)
    br = RadialFigure.arc(-dfrac * don)
    Intersect.get_intersection(Segment.new!(ar, br), Segment.new!(a, RadialFigure.arc(d * don)))
  end

  defp rows(state, whole) do
    [
      {"n", Integer.to_string(state.n)},
      {"d requested", Format.coordinate(state.d)},
      {"d clamped", Figures.number(state.clamp_d)},
      {"di", Figures.integer(state.di)},
      {"frac", Figures.number(state.dfrac)},
      {"is integer", yes_no(state.is_int)},
      {"s stored", Figures.integer(state.clamp_s)},
      {"outer s", Figures.integer(state.outer_s)},
      {"closure", closure_name(state)}
    ] ++ Figures.rows_for(whole)
  end

  defp closure_name(%{clamp_s: nil}), do: "no"
  defp closure_name(%{di: nil}), do: "no"
  defp closure_name(%{clamp_s: clamp_s, di: di}) when clamp_s == di, do: "yes"
  defp closure_name(_state), do: "no"

  defp yes_no(nil), do: "n/a"
  defp yes_no(true), do: "yes"
  defp yes_no(false), do: "no"
end

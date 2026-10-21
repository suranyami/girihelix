defmodule GirihelixWeb.Workbench.Exhibits.Rosette do
  @moduledoc """
  Lee's rosette construction, stage by stage.

  The whole figure is the unit replicated under the symmetry ladder; the unit is
  the heavier chain drawn over it. The canvas marks the construction's starting
  point `(1, 0)`, draws the outer frame's `up_outer → bisector` guide, the
  `tip → qtip` ray once `:key` has found it, the key line, the stable ray when
  `q` is negative, and every walk point the current frame has found.

  Frame zero draws the tip alone, and every intermediate frame draws only what
  its state has: the frame's guides after `:frame`, the key line after `:key`,
  and the replicated figure only after `:assemble`. The whole figure is
  replicated from the unit the state holds rather than rebuilt, so a failed
  run's retained frames still draw.

  The panel reports the requested and clamped `q`, the requested and stored `s`,
  the key point, the walk's emitted and skipped step counts, and the shared
  vertex, edge and verification rows.
  """

  @behaviour GirihelixWeb.Workbench.Exhibit

  alias Girihelix.Engine.Figures.RadialFigure
  alias Girihelix.Engine.Figures.Rosette, as: RosetteFigure
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Viewport
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibit
  alias GirihelixWeb.Workbench.Exhibits.Figures
  alias GirihelixWeb.Workbench.Exhibits.Format
  alias GirihelixWeb.Workbench.Param

  # The construction starts here, and the point is static even at frame zero.
  @tip {1.0, 0.0}
  @construction_radius 3.0
  @construction_opts [opacity: 0.6]

  @impl true
  @spec slug() :: String.t()
  def slug, do: "rosette"

  @impl true
  @spec title() :: String.t()
  def title, do: "Rosette — Lee's key line and its rotated copies"

  @impl true
  @spec summary() :: String.t()
  def summary, do: "A blended key ray mirrored into a unit and replicated n times."

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
        doc: "The rosette's symmetry order."
      },
      %Param{
        name: :q,
        type: :float,
        range: -2..2,
        step: 0.05,
        default: 0.0,
        doc: "The blend weight for the key ray; the engine clamps it to ±0.99."
      },
      %Param{
        name: :s,
        type: :integer,
        range: 1..6,
        default: 3,
        doc: "How many rotated copies of the key line the unit intersects."
      }
    ]
  end

  @impl true
  @spec initial(map()) :: RosetteFigure.state()
  def initial(%{n: n, q: q, s: s}), do: RosetteFigure.start(n, q, s)

  @impl true
  @spec steps(map()) :: [Steps.Step.t()]
  def steps(%{n: n, q: q, s: s}), do: RosetteFigure.steps(n, q, s)

  @impl true
  @spec draw(Steps.Frame.t(), map()) :: Exhibit.drawing()
  def draw(%Steps.Frame{state: state}, _params) do
    whole = whole_map(state)
    {:both, ops(state, whole), rows(state, whole)}
  end

  @impl true
  @spec reproduce(map()) :: String.t()
  def reproduce(%{n: n, q: q, s: s}) do
    "Girihelix.Engine.Figures.Rosette.build_unit(" <>
      "Girihelix.Engine.Figures.Rosette.new!(#{Integer.to_string(n)}, " <>
      "#{Format.coordinate(q)}, #{Integer.to_string(s)}))"
  end

  @impl true
  @spec viewport(map()) :: Viewport.t()
  def viewport(_params), do: %Viewport{left: -1.25, top: 1.25, width: 2.5, scale: 400.0}

  # The state's `map` is the unit; the whole figure is that unit replicated.
  # Replaying `Figure.map/1` would rebuild it and could re-raise a failure a
  # retained frame has survived.
  defp whole_map(%{map: nil}), do: nil

  defp whole_map(%{map: unit, n: n}), do: PlanarMap.replicate!(PlanarMap.new(), unit, RadialFigure.ladder(n))

  defp ops(state, nil), do: partial_ops(state)

  defp ops(state, whole) do
    Figures.map_ops(whole) ++ Figures.unit_ops(state.map) ++ partial_ops(state)
  end

  defp partial_ops(state) do
    [tip_op()] ++ frame_ops(state) ++ walk_ops(state)
  end

  defp tip_op, do: {:point, @tip, 4.0, []}

  defp frame_ops(%{frame: nil}), do: []

  defp frame_ops(%{frame: frame, q_clamp: q_clamp}) do
    [{:guide, Format.pair(frame.up_outer), Format.pair(frame.bisector), []}] ++
      qtip_ops(frame) ++ key_ops(frame) ++ stable_ops(frame, q_clamp)
  end

  defp qtip_ops(frame) do
    case Map.fetch(frame, :qtip) do
      {:ok, qtip} -> [{:guide, Format.pair(frame.tip), Format.pair(qtip), []}]
      :error -> []
    end
  end

  defp key_ops(frame) do
    case {Map.fetch(frame, :key_point), Map.fetch(frame, :key_end)} do
      {{:ok, key_point}, {:ok, key_end}} ->
        [{:guide, Format.pair(key_point), Format.pair(key_end), []}]

      _missing ->
        []
    end
  end

  defp stable_ops(_frame, nil), do: []

  defp stable_ops(frame, q_clamp) when q_clamp < 0.0 do
    [{:guide, Format.pair(frame.tip), Format.pair(frame.stable_isect), []}]
  end

  defp stable_ops(_frame, _q_clamp), do: []

  defp walk_ops(%{points: points}), do: Enum.map(points, &construction_op/1)

  defp construction_op(point), do: {:point, Format.pair(point), @construction_radius, @construction_opts}

  defp rows(state, whole) do
    [
      {"n", Integer.to_string(state.n)},
      {"q requested", Format.coordinate(state.q)},
      {"q clamped", number(state.q_clamp)},
      {"s requested", Integer.to_string(state.s)},
      {"s stored", integer(state.s_clamp)},
      {"key point", key_point_text(state)},
      {"steps emitted", Integer.to_string(emitted(state.points))},
      {"steps skipped", Integer.to_string(state.skipped)}
    ] ++ Figures.rows_for(whole)
  end

  defp key_point_text(%{frame: nil}), do: "n/a"

  defp key_point_text(%{frame: frame}) do
    case Map.fetch(frame, :key_point) do
      {:ok, point} -> point_text(point)
      :error -> "n/a"
    end
  end

  defp point_text(%Point{x: x, y: y}), do: "#{Format.coordinate(x)}, #{Format.coordinate(y)}"

  # `points` holds the key point followed by the walk's successful crossings.
  defp emitted([]), do: 0
  defp emitted(points), do: length(points) - 1

  defp number(nil), do: "n/a"
  defp number(value), do: Format.coordinate(value)

  defp integer(nil), do: "n/a"
  defp integer(value), do: Integer.to_string(value)
end

defmodule GirihelixWeb.Workbench.Exhibits.Connect do
  @moduledoc """
  A radial child whose scaled-out edges are made to meet, stage by stage.

  There is no `s` control: the exhibit derives it from the child exactly as the
  engine's constructor does, and reports it in the panel. The canvas dashes the
  child's unit, strokes the current folded or normalised map solid, and draws
  the half-step rotation as a labelled guide from the apex.

  Frame zero draws the tip alone. The child's unit is rebuilt only once the
  frame holds a map, so a retained frame from a failed run still draws without
  replaying the build that raised.

  The panel reports the child kind, the derived `s`, the fallback flag and the
  pre-normalisation maximum x, plus the shared vertex, edge and verification
  rows.
  """

  @behaviour GirihelixWeb.Workbench.Exhibit

  alias Girihelix.Engine.Figures.ConnectFigure
  alias Girihelix.Engine.Figures.Figure
  alias Girihelix.Engine.Figures.RadialFigure
  alias Girihelix.Engine.Figures.ScaleFigure
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.Engine.Render.Viewport
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibit
  alias GirihelixWeb.Workbench.Exhibits.Figures
  alias GirihelixWeb.Workbench.Exhibits.Format
  alias GirihelixWeb.Workbench.Param

  @child_opts [dash: "6 3", opacity: 0.5]

  @impl true
  @spec slug() :: String.t()
  def slug, do: "connect"

  @impl true
  @spec title() :: String.t()
  def title, do: "Connect — the solved scale"

  @impl true
  @spec summary() :: String.t()
  def summary, do: "A child scaled so its extended tip edges meet, with no s to choose."

  @impl true
  @spec category() :: atom()
  def category, do: :figures

  @impl true
  @spec params() :: [Param.t()]
  def params, do: Figures.child_params([])

  # The stored scale is the derived one, so the panel and the transport show the
  # number the solver found rather than a requested value. Deriving it can raise
  # on degenerate in-range geometry, which must not crash the page: the fallback
  # is one, exactly as the engine's own no-crossing path stores.
  @impl true
  @spec initial(map()) :: ConnectFigure.state()
  def initial(params) do
    child = Figures.build_child(params)
    ConnectFigure.start(child, derived_s(child))
  end

  @impl true
  @spec steps(map()) :: [Steps.Step.t()]
  def steps(params) do
    child = Figures.build_child(params)
    # The arguments are ignored (the sequence is static), so the placeholder s
    # is never read. Deriving it here again would reintroduce the raise site and
    # do dead work; a degenerate child now fails visibly in :scale_clip instead.
    ConnectFigure.steps(child, 1.0)
  end

  @impl true
  @spec draw(Steps.Frame.t(), map()) :: Exhibit.drawing()
  def draw(%Steps.Frame{state: state}, params) do
    {:both, ops(state), rows(state, params)}
  end

  @impl true
  @spec reproduce(map()) :: String.t()
  def reproduce(params) do
    "Girihelix.Engine.Figures.ConnectFigure.build_unit(" <>
      "Girihelix.Engine.Figures.ConnectFigure.new!(" <> child_call(params) <> "))"
  end

  @impl true
  @spec viewport(map()) :: Viewport.t()
  def viewport(_params), do: %Viewport{left: -1.25, top: 1.25, width: 2.5, scale: 400.0}

  defp child_call(%{child: :star, n: n, d: d, child_s: s}) do
    "Girihelix.Engine.Figures.Star.new!(#{Integer.to_string(n)}, " <>
      "#{Format.coordinate(d)}, #{Integer.to_string(s)})"
  end

  defp child_call(%{child: :rosette, n: n, q: q, child_s: s}) do
    "Girihelix.Engine.Figures.Rosette.new!(#{Integer.to_string(n)}, " <>
      "#{Format.coordinate(q)}, #{Integer.to_string(s)})"
  end

  # `ArgumentError` is the engine's degenerate-geometry failure; keep the rescue
  # narrow so a real bug still surfaces. `normalise_s/1` is what the constructor
  # applies to the solved value.
  defp derived_s(child) do
    child
    |> ConnectFigure.compute_scale()
    |> ScaleFigure.normalise_s()
  rescue
    ArgumentError -> 1.0
  end

  defp ops(state) do
    [Figures.tip_op()] ++ child_ops(state) ++ map_ops(state) ++ half_step_ops(state)
  end

  defp child_ops(%{map: nil}), do: []

  defp child_ops(%{child: child}) do
    unit = Figure.unit(child)
    Figures.map_ops(unit, @child_opts) ++ Figures.map_label(unit, "child unit")
  end

  defp map_ops(%{map: nil}), do: []
  defp map_ops(%{map: map}), do: Figures.map_ops(map)

  defp half_step_ops(%{map: nil}), do: []
  defp half_step_ops(%{fallback: true}), do: []

  defp half_step_ops(%{figure: %module{} = figure}) do
    apex = Point.new(1.0, 0.0)

    rotated =
      Transform.apply_to(Transform.rotate(:math.pi() * RadialFigure.don(module.n(figure))), apex)

    from = Format.pair(apex)
    to = Format.pair(rotated)

    [{:guide, from, to, []}, {:label, Format.midpoint(from, to), "half step", []}]
  end

  defp rows(state, params) do
    [
      {"child", Atom.to_string(params.child)},
      {"derived s", Format.coordinate(state.s)},
      {"fallback", flag(state.fallback)}
    ] ++ List.insert_at(Figures.rows_for(state.map), -1, {"max x", value(state.max_x)})
  end

  defp value(nil), do: "-"
  defp value(number), do: Format.coordinate(number)

  defp flag(nil), do: "-"
  defp flag(true), do: "yes"
  defp flag(false), do: "no"
end

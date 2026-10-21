defmodule GirihelixWeb.Workbench.Exhibits.Scale do
  @moduledoc """
  A radial child scaled by `s` and clipped to the unit n-gon, stage by stage.

  The canvas dashes the child's unit, strokes the current scaled map solid,
  draws the clipping n-gon, the tip ray and the clipped endpoint, and marks the
  map's vertices as the construction adds them. At `s = 1` the scaling stages
  are a passthrough, so the dashed child and the solid map coincide: that is
  the exhibit's control case.

  Frame zero draws the tip alone, and every intermediate frame draws only what
  its state has: the child's unit once `:child` has built it, the border and
  ray from `:clip`, the endpoint and the rotated crossings from there on. The
  child's unit is rebuilt only when the frame already holds a map, because a
  child whose own build raised must leave the retained frames drawable.

  The panel reports the child kind, the requested and stored `s`, the
  passthrough flag, the tip, its below-axis neighbour and the endpoint, plus
  the shared vertex, edge and verification rows.
  """

  @behaviour GirihelixWeb.Workbench.Exhibit

  alias Girihelix.Engine.Figures.Figure
  alias Girihelix.Engine.Figures.ScaleFigure
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Viewport
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibit
  alias GirihelixWeb.Workbench.Exhibits.Figures
  alias GirihelixWeb.Workbench.Exhibits.Format
  alias GirihelixWeb.Workbench.Param

  @child_opts [dash: "6 3", opacity: 0.5]
  @border_opts [dash: "4 3", opacity: 0.6]

  @impl true
  @spec slug() :: String.t()
  def slug, do: "scale"

  @impl true
  @spec title() :: String.t()
  def title, do: "Scale — the child unit scaled and clipped"

  @impl true
  @spec summary() :: String.t()
  def summary, do: "A child figure scaled out and clipped back to the unit n-gon."

  @impl true
  @spec category() :: atom()
  def category, do: :figures

  @impl true
  @spec params() :: [Param.t()]
  def params do
    Figures.child_params([
      %Param{
        name: :s,
        type: :float,
        range: 0..3,
        step: 0.1,
        default: 1.5,
        doc: "The scale; a value within 1e-7 of one is a passthrough."
      }
    ])
  end

  @impl true
  @spec initial(map()) :: ScaleFigure.state()
  def initial(params), do: ScaleFigure.start(Figures.build_child(params), params.s)

  @impl true
  @spec steps(map()) :: [Steps.Step.t()]
  def steps(params), do: ScaleFigure.steps(Figures.build_child(params), params.s)

  @impl true
  @spec draw(Steps.Frame.t(), map()) :: Exhibit.drawing()
  def draw(%Steps.Frame{state: state}, params) do
    {:both, ops(state), rows(state, params)}
  end

  @impl true
  @spec reproduce(map()) :: String.t()
  def reproduce(%{s: s} = params) do
    "Girihelix.Engine.Figures.ScaleFigure.build_unit(" <>
      "Girihelix.Engine.Figures.ScaleFigure.new!(" <>
      child_call(params) <> ", #{Format.coordinate(s)}))"
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

  defp ops(state) do
    [Figures.tip_op()] ++
      child_ops(state) ++
      map_ops(state) ++
      vertex_ops(state) ++ border_ops(state) ++ ray_ops(state) ++ endpoint_ops(state)
  end

  # The child is rebuilt only after `:child` has already built its unit into the
  # state: a child whose build raised leaves `map` nil, and its retained frame
  # must draw without replaying the failure.
  defp child_ops(%{map: nil}), do: []

  defp child_ops(%{child: child}) do
    unit = Figure.unit(child)
    Figures.map_ops(unit, @child_opts) ++ Figures.map_label(unit, "child unit")
  end

  defp map_ops(%{map: nil}), do: []
  defp map_ops(%{map: map}), do: Figures.map_ops(map)

  defp vertex_ops(%{map: nil}), do: []
  defp vertex_ops(%{map: map}), do: Figures.vertex_ops(map)

  defp border_ops(%{border: nil}), do: []

  defp border_ops(%{border: border}) do
    points = Enum.map(border, &Format.pair/1)

    [
      {:polygon, points, :stroke, @border_opts},
      {:label, Enum.at(points, div(length(points), 2)), "clip border", []}
    ]
  end

  defp ray_ops(%{tip_pos: nil}), do: []
  defp ray_ops(%{below: nil}), do: []

  defp ray_ops(%{tip_pos: tip_pos, below: below, map: map}) do
    direction =
      tip_pos
      |> Point.subtract(PlanarMap.position!(map, below))
      |> Point.normalize()

    from = Format.pair(tip_pos)
    to = tip_pos |> Point.add(Point.scale(direction, 100.0)) |> Format.pair()
    label_at = tip_pos |> Point.add(Point.scale(direction, 0.5)) |> Format.pair()

    [{:guide, from, to, []}, {:label, label_at, "tip ray", []}]
  end

  defp endpoint_ops(%{endpoint: nil}), do: []
  defp endpoint_ops(%{endpoint: endpoint}), do: [{:point, Format.pair(endpoint), 5.0, []}]

  defp rows(state, params) do
    [
      {"child", Atom.to_string(params.child)},
      {"s requested", Format.coordinate(state.requested_s)},
      {"s stored", stored_s(state.figure)},
      {"passthrough", flag(state.passthrough)},
      {"tip", point_text(state.tip_pos)},
      {"below-axis neighbour", below_text(state)},
      {"endpoint", point_text(state.endpoint)}
    ] ++ Figures.rows_for(state.map)
  end

  defp stored_s(nil), do: "-"
  defp stored_s(%{s: s}), do: Format.coordinate(s)

  defp below_text(%{below: nil}), do: "-"

  defp below_text(%{below: below, map: map}), do: map |> PlanarMap.position!(below) |> point_text()

  defp point_text(nil), do: "-"
  defp point_text(%Point{x: x, y: y}), do: "#{Format.coordinate(x)}, #{Format.coordinate(y)}"

  defp flag(nil), do: "-"
  defp flag(true), do: "yes"
  defp flag(false), do: "no"
end

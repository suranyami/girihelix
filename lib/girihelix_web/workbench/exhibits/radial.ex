defmodule GirihelixWeb.Workbench.Exhibits.Radial do
  @moduledoc """
  The symmetry ladder itself, in one step.

  Unlike the other figure exhibits this one is about replication, not the unit's
  construction: its single `:replicate` step builds the child's unit and then
  the coalesced map under `RadialFigure.ladder/1`. The canvas draws the
  coalesced map faintly beneath, every copy from the unit's own edges mapped
  through one ladder transform and labelled `Tr^k` at its bounding-box centre,
  and the unit heavily over them.

  Each copy comes from the unit rather than from the coalesced map because
  replication has already merged the copies' shared vertices.

  Frame zero draws the tip alone; the copies appear only after `:replicate`.
  The panel reports the kind, the order, the unit's and the map's counts, the
  transform count and the verification verdict.
  """

  @behaviour GirihelixWeb.Workbench.Exhibit

  import Girihelix.Engine.Steps, only: [step: 4]

  alias Girihelix.Engine.Figures.Figure
  alias Girihelix.Engine.Figures.RadialFigure
  alias Girihelix.Engine.Figures.Rosette, as: RosetteFigure
  alias Girihelix.Engine.Figures.Star, as: StarFigure
  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Viewport
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibit
  alias GirihelixWeb.Workbench.Exhibits.Figures
  alias GirihelixWeb.Workbench.Exhibits.Format
  alias GirihelixWeb.Workbench.Param

  @map_opts [opacity: 0.25]

  @impl true
  @spec slug() :: String.t()
  def slug, do: "radial"

  @impl true
  @spec title() :: String.t()
  def title, do: "Radial — the symmetry ladder"

  @impl true
  @spec summary() :: String.t()
  def summary, do: "One unit copied n times under the ladder, and the map those copies coalesce into."

  @impl true
  @spec category() :: atom()
  def category, do: :figures

  @impl true
  @spec params() :: [Param.t()]
  def params do
    [
      %Param{
        name: :kind,
        type: :enum,
        options: [:star, :rosette],
        default: :rosette,
        doc: "The figure whose unit is replicated."
      },
      %Param{
        name: :n,
        type: :integer,
        range: 3..24,
        default: 8,
        doc: "The symmetry order, and so the number of ladder transforms."
      },
      %Param{
        name: :d,
        type: :float,
        range: 1..10,
        step: 0.1,
        default: 3.0,
        doc: "The star's continuous skip; read only for a star kind."
      },
      %Param{
        name: :q,
        type: :float,
        range: -2..2,
        step: 0.05,
        default: 0.0,
        doc: "The rosette's blend weight; the engine clamps it to ±0.99."
      },
      %Param{
        name: :s,
        type: :integer,
        range: 1..6,
        default: 3,
        doc: "How many crossings the unit takes."
      }
    ]
  end

  @impl true
  @spec initial(map()) :: map()
  def initial(%{n: n} = params) do
    %{
      figure: build_figure(params),
      map: nil,
      unit: nil,
      transforms: RadialFigure.ladder(n)
    }
  end

  @impl true
  @spec steps(map()) :: [Steps.Step.t()]
  def steps(_params) do
    [
      step(
        :replicate,
        "replicate the unit",
        "Builds the unit, then its coalesced map under the ladder.",
        &replicate/1
      )
    ]
  end

  @impl true
  @spec draw(Steps.Frame.t(), map()) :: Exhibit.drawing()
  def draw(%Steps.Frame{state: state}, params) do
    {:both, ops(state), rows(state, params)}
  end

  @impl true
  @spec reproduce(map()) :: String.t()
  def reproduce(%{kind: :star, n: n, d: d, s: s}) do
    "Girihelix.Engine.Figures.RadialFigure.map(" <>
      "Girihelix.Engine.Figures.Star.new!(#{Integer.to_string(n)}, " <>
      "#{Format.coordinate(d)}, #{Integer.to_string(s)}))"
  end

  def reproduce(%{kind: :rosette, n: n, q: q, s: s}) do
    "Girihelix.Engine.Figures.RadialFigure.map(" <>
      "Girihelix.Engine.Figures.Rosette.new!(#{Integer.to_string(n)}, " <>
      "#{Format.coordinate(q)}, #{Integer.to_string(s)}))"
  end

  @impl true
  @spec viewport(map()) :: Viewport.t()
  def viewport(_params), do: %Viewport{left: -1.25, top: 1.25, width: 2.5, scale: 400.0}

  defp build_figure(%{kind: :star, n: n, d: d, s: s}), do: StarFigure.new!(n, d, s)
  defp build_figure(%{kind: :rosette, n: n, q: q, s: s}), do: RosetteFigure.new!(n, q, s)

  defp replicate(state), do: %{state | unit: Figure.unit(state.figure), map: Figure.map(state.figure)}

  defp ops(state), do: [Figures.tip_op()] ++ drawn_ops(state)

  defp drawn_ops(%{map: nil}), do: []

  defp drawn_ops(%{map: map, unit: nil}), do: Figures.map_ops(map, @map_opts)

  defp drawn_ops(%{map: map, unit: unit, transforms: transforms}) do
    Figures.map_ops(map, @map_opts) ++ copy_ops(unit, transforms) ++ Figures.unit_ops(unit)
  end

  # Each copy is the unit's own edge walk mapped through one ladder transform,
  # so the label sits at the copy's bounding-box centre rather than at a merged
  # vertex the coalesced map no longer distinguishes.
  defp copy_ops(unit, transforms) do
    transforms
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {transform, k} -> copy_ops(unit, transform, k) end)
  end

  defp copy_ops(unit, transform, k) do
    copies =
      Map.new(PlanarMap.vertices(unit), fn vertex ->
        {vertex, Transform.apply_to(transform, PlanarMap.position!(unit, vertex))}
      end)

    lines =
      Enum.map(PlanarMap.edges(unit), fn edge ->
        {from, to} = PlanarMap.endpoints!(unit, edge)

        {:line, copies |> Map.fetch!(from) |> Format.pair(), copies |> Map.fetch!(to) |> Format.pair(), []}
      end)

    lines ++
      [
        {:label, copies |> Map.values() |> Enum.map(&Format.pair/1) |> bbox_centre(), "Tr^#{k}", []}
      ]
  end

  defp bbox_centre([{_x, _y} | _] = points) do
    {xs, ys} = Enum.unzip(points)
    {(Enum.min(xs) + Enum.max(xs)) / 2.0, (Enum.min(ys) + Enum.max(ys)) / 2.0}
  end

  defp rows(state, params) do
    [
      {"kind", Atom.to_string(params.kind)},
      {"n", Integer.to_string(params.n)},
      {"unit vertices", count(state.unit, &PlanarMap.num_vertices/1)},
      {"unit edges", count(state.unit, &PlanarMap.num_edges/1)},
      {"transforms", Integer.to_string(length(state.transforms))}
    ] ++ Figures.rows_for(state.map)
  end

  defp count(nil, _counter), do: "-"
  defp count(map, counter), do: Integer.to_string(counter.(map))
end

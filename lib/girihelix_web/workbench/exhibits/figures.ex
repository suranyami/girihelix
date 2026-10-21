defmodule GirihelixWeb.Workbench.Exhibits.Figures do
  @moduledoc """
  The drawing ops, panel rows and parameter declarations the figure exhibits
  share.

  A figure exhibit draws two maps at once: the **whole figure**, replicated
  under the symmetry ladder, and the **unit** the ladder copies. Sharing one
  edge walker means every exhibit draws both the same way, in map edge order:
  `map_ops/1` strokes the whole figure and `unit_ops/1` overlays the unit
  heavier so the two read together. `map_ops/2` carries the line options a
  diagnostic copy needs, such as the faint coalesced map `radial` draws.

  `vertex_ops/2` marks a map's vertices at the design's default radius. Its
  options style construction vertices instead: `radius: 3.0` and
  `opts: [opacity: 0.6]` mark a point that is not a final vertex.

  Every figure exhibit also emits a statically-known marker — `tip_op/0` — so
  frame zero and a failed run's retained frames still draw, and
  `construction_op/1` marks a point a construction found but did not make a
  vertex. `number/1` and `integer/1` spell a row value that may not exist yet.

  `whole_map/1` replicates the unit a frame already holds rather than rebuilding
  it: replaying a builder can re-raise a failure a retained frame survived.
  `child_params/1` declares the shared `child`, `n`, `q`, `d` and `child_s`
  parameters, and `build_child/1` builds the declared child from a typed map.

  `rows_for/1` reports the counts and the verification verdict. A `nil` map is
  a frame before `:assemble`: there is nothing to count or verify yet, so its
  rows are honest placeholders rather than a zero that would read as a result.

  This is workbench code, not engine code: it uses `PlanarMap`'s public API and
  the draw ops, never the map's internals.
  """

  alias Girihelix.Engine.Figures.RadialFigure
  alias Girihelix.Engine.Figures.Rosette, as: RosetteFigure
  alias Girihelix.Engine.Figures.Star, as: StarFigure
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Op
  alias GirihelixWeb.Workbench.Exhibits.Format
  alias GirihelixWeb.Workbench.Param

  @default_vertex_radius 4.0
  @tip {1.0, 0.0}
  @construction_radius 3.0
  @construction_opts [opacity: 0.6]

  @doc "The point every figure construction starts from, static at frame zero."
  @spec tip_op() :: Op.t()
  def tip_op, do: {:point, @tip, 4.0, []}

  @doc "A construction point that is not a final vertex, marked faintly."
  @spec construction_op(Girihelix.Engine.Geometry.Point.t()) :: Op.t()
  def construction_op(point), do: {:point, Format.pair(point), @construction_radius, @construction_opts}

  @doc "One line per map edge, in edge order."
  @spec map_ops(PlanarMap.t(), keyword()) :: [Op.t()]
  def map_ops(map, opts \\ []), do: edge_ops(map, opts)

  @doc "The unit's edges as heavier lines over the whole figure."
  @spec unit_ops(PlanarMap.t()) :: [Op.t()]
  def unit_ops(map), do: edge_ops(map, width: 2.0)

  @doc "A label at the midpoint of a map's first edge, naming a diagnostic copy."
  @spec map_label(PlanarMap.t(), String.t()) :: [Op.t()]
  def map_label(map, text) do
    case PlanarMap.edges(map) do
      [] ->
        []

      [edge | _] ->
        {from, to} = PlanarMap.endpoints!(map, edge)

        [{:label, Format.midpoint(pair_at(map, from), pair_at(map, to)), text, []}]
    end
  end

  @doc """
  One marker per map vertex.

  Options:

    * `:radius` — the marker radius in SVG units; default `#{@default_vertex_radius}`.
    * `:opts` — the draw op's options; default `[]`.
  """
  @spec vertex_ops(PlanarMap.t(), keyword()) :: [Op.t()]
  def vertex_ops(map, opts \\ []) do
    radius = Keyword.get(opts, :radius, @default_vertex_radius)
    style = Keyword.get(opts, :opts, [])

    Enum.map(PlanarMap.vertices(map), fn vertex ->
      {:point, map |> PlanarMap.position!(vertex) |> Format.pair(), radius, style}
    end)
  end

  @doc """
  The whole figure, replicated from the unit the state holds.

  `nil` is a frame that has not built the unit yet. Replicating the held unit
  rather than calling the figure's builder means a retained failure frame can
  still be drawn: the builder's failure is never replayed.
  """
  @spec whole_map(map()) :: PlanarMap.t() | nil
  def whole_map(%{map: nil}), do: nil

  def whole_map(%{map: unit, n: n}), do: PlanarMap.replicate!(PlanarMap.new(), unit, RadialFigure.ladder(n))

  @doc """
  The shared `vertices`, `edges` and `verify` rows.

  `nil` is a frame that has not assembled a map yet.
  """
  @spec rows_for(PlanarMap.t() | nil) :: [{String.t(), String.t()}]
  def rows_for(nil), do: [{"vertices", "0"}, {"edges", "0"}, {"verify", "n/a"}]

  def rows_for(map) do
    [
      {"vertices", Integer.to_string(PlanarMap.num_vertices(map))},
      {"edges", Integer.to_string(PlanarMap.num_edges(map))},
      {"verify", verdict(PlanarMap.verify(map))}
    ]
  end

  @doc """
  The `child`, `n`, `q`, `d` and `child_s` parameters, then `extra`.

  `q` is read only by a rosette child and `d` only by a star child; both are
  declared so the control panel can switch between them.
  """
  @spec child_params([Param.t()]) :: [Param.t()]
  def child_params(extra) when is_list(extra) do
    [
      %Param{
        name: :child,
        type: :enum,
        options: [:rosette, :star],
        default: :rosette,
        doc: "The radial figure to wrap."
      },
      %Param{
        name: :n,
        type: :integer,
        range: 3..12,
        default: 8,
        doc: "The child's symmetry order."
      },
      %Param{
        name: :q,
        type: :float,
        range: -2..2,
        step: 0.05,
        default: 0.0,
        doc: "The rosette child's blend weight; the engine clamps it to ±0.99."
      },
      %Param{
        name: :d,
        type: :float,
        range: 1..10,
        step: 0.1,
        default: 3.0,
        doc: "The star child's continuous skip."
      },
      %Param{
        name: :child_s,
        type: :integer,
        range: 1..6,
        default: 3,
        doc: "How many crossings the child's unit takes."
      }
    ] ++ extra
  end

  @doc "The child figure a typed parameter map declares."
  @spec build_child(map()) :: StarFigure.t() | RosetteFigure.t()
  def build_child(%{child: :star, n: n, d: d, child_s: s}), do: StarFigure.new!(n, d, s)
  def build_child(%{child: :rosette, n: n, q: q, child_s: s}), do: RosetteFigure.new!(n, q, s)

  @doc "A row's number, or `n/a` when the frame has not set it."
  @spec number(number() | nil) :: String.t()
  def number(nil), do: "n/a"
  def number(value), do: Format.coordinate(value)

  @doc "A row's integer, or `n/a` when the frame has not set it."
  @spec integer(integer() | nil) :: String.t()
  def integer(nil), do: "n/a"
  def integer(value), do: Integer.to_string(value)

  defp edge_ops(map, opts) do
    Enum.map(PlanarMap.edges(map), fn edge ->
      {from, to} = PlanarMap.endpoints!(map, edge)

      {:line, pair_at(map, from), pair_at(map, to), opts}
    end)
  end

  defp pair_at(map, vertex), do: map |> PlanarMap.position!(vertex) |> Format.pair()

  defp verdict(:ok), do: "ok"
  defp verdict({:error, _problems}), do: "failed"
end

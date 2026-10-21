defmodule Girihelix.Engine.Figures.ConnectFigure do
  @moduledoc """
  A radial figure whose scaled-out edges are made to meet, a port of Taprats'
  `ConnectFigure.java`.

  The scale is **derived from the child**, not passed: `compute_scale/1` builds
  the child's unit, extends the tip's ray away from its lower neighbour, and
  intersects that ray with one rotated copy of the mirrored ray. The crossing's
  distance from the origin gives `s = cos(PI/n) / |isection|`, which puts the
  extended edges' meeting point on the unit n-gon's inradius. A child with no
  tip, no lower neighbour or no crossing stores `1.0`, which makes the scaling
  stage a no-op.

  Building the unit runs `ScaleFigure.build_unit/2` and then reshapes it so the
  apex returns to `(1, 0)`: the half strictly above the x axis is copied down by
  one symmetry step and its originals deleted, leaving the axis vertices as the
  seam; unless `s` is `1.0` the whole map then turns by half a step; finally it
  is scaled so the maximum x is `1`.

  **The child is never touched.** Both the scale derivation and the build ask
  the child for a fresh unit, so the child struct and its map are unchanged.
  """

  @behaviour Girihelix.Engine.Figures.RadialFigure

  import Girihelix.Engine.Steps, only: [step: 4]

  alias Girihelix.Engine.Figures.Figure
  alias Girihelix.Engine.Figures.RadialFigure
  alias Girihelix.Engine.Figures.ScaleFigure
  alias Girihelix.Engine.Geometry.Intersect
  alias Girihelix.Engine.Geometry.Loose
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Segment
  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Steps

  @enforce_keys [:child, :s]
  defstruct [:child, :s]

  @type t :: %__MODULE__{child: RadialFigure.t(), s: float()}
  @type reason :: :not_radial
  @type state :: map()

  # Read at compile time so the fold's guards can use it: a guard cannot call a
  # function, and duplicating the literal here would let the two drift apart.
  @tol Loose.tol()

  @doc """
  Wraps `child` at the scale derived from it.

  A non-radial child is refused with `{:error, :not_radial}` rather than
  raising. The scale is normalised by `ScaleFigure.normalise_s/1`.
  """
  @spec new(Figure.t()) :: {:ok, t()} | {:error, reason()}
  def new(child), do: check_new(Figure.radial?(child), child)

  defp check_new(true, child), do: {:ok, build(child, compute_scale(child))}
  defp check_new(false, _child), do: {:error, :not_radial}

  @doc "`new/1` for a caller that has established the child is radial, raising otherwise."
  @spec new!(Figure.t()) :: t()
  def new!(child) do
    case new(child) do
      {:ok, connect} -> connect
      {:error, reason} -> raise ArgumentError, "connect: #{reason}"
    end
  end

  defp build(child, s), do: %__MODULE__{child: child, s: ScaleFigure.normalise_s(s)}

  @doc "A copy of `connect` with the scale re-derived from its child."
  @spec child_changed(t()) :: t()
  def child_changed(%__MODULE__{child: child}), do: build(child, compute_scale(child))

  @doc """
  The scale that makes the extended tip edges meet on the unit n-gon's inradius.

  The tip is the vertex at `(1, 0)` by `Loose.equals/2`; its lower neighbour is
  the first in ring order with `y < 0.0` strictly. The moving segment is the
  mirror of the **full-length** ray, rotated one symmetry step. `1.0` on any
  failure: no tip with a lower neighbour, or a null crossing.
  """
  @spec compute_scale(RadialFigure.t()) :: float()
  def compute_scale(%module{} = child) do
    map = Figure.unit(child)
    n = module.n(child)
    tr = RadialFigure.tr(n)
    tip_pos = Point.new(1.0, 0.0)

    map
    |> PlanarMap.vertices()
    |> Enum.reduce_while(1.0, fn vertex, fallback ->
      case scale_at(map, vertex, tip_pos, tr, n) do
        nil -> {:cont, fallback}
        scale -> {:halt, scale}
      end
    end)
  end

  # `nil` when the vertex is not a tip candidate or has no lower neighbour: the
  # source keeps scanning instead of stopping.
  defp scale_at(map, vertex, tip_pos, tr, n) do
    case lower_neighbour(map, vertex, tip_pos) do
      nil -> nil
      below -> crossing_scale(map, below, tip_pos, tr, n)
    end
  end

  defp lower_neighbour(map, vertex, tip_pos) do
    tip_candidate(Loose.equals(PlanarMap.position!(map, vertex), tip_pos), map, vertex)
  end

  defp tip_candidate(true, map, vertex), do: first_below(map, vertex)
  defp tip_candidate(false, _map, _vertex), do: nil

  defp first_below(map, vertex) do
    map
    |> PlanarMap.ring!(vertex)
    |> Enum.map(&far_vertex(map, &1, vertex))
    |> Enum.find(fn other -> PlanarMap.position!(map, other).y < 0.0 end)
  end

  defp far_vertex(map, edge, vertex) do
    case PlanarMap.endpoints!(map, edge) do
      {^vertex, other} -> other
      {other, _second} -> other
    end
  end

  defp crossing_scale(map, below, tip_pos, tr, n) do
    seg_end =
      tip_pos
      |> Point.subtract(PlanarMap.position!(map, below))
      |> Point.normalize()
      |> Point.scale(100.0)
      |> Point.add(tip_pos)

    fixed = Segment.new!(tip_pos, seg_end)

    moving =
      Segment.new!(
        Transform.apply_to(tr, tip_pos),
        Transform.apply_to(tr, RadialFigure.mirror(seg_end))
      )

    case Intersect.get_intersection(fixed, moving) do
      nil -> 1.0
      isect -> :math.cos(:math.pi() / n) / Point.mag(isect)
    end
  end

  @doc "The state `steps/2` starts from: parameters only, every derived field empty."
  @spec start(RadialFigure.t(), float()) :: state()
  def start(child, s) do
    %{
      child: child,
      s: s,
      figure: nil,
      map: nil,
      fallback: nil,
      max_x: nil
    }
  end

  @doc "The five stages that build the unit."
  @spec steps(RadialFigure.t(), float()) :: [Steps.Step.t()]
  def steps(_child, _s) do
    [
      step(:clamp, "normalise s", "Builds the wrapper and snaps s within 1e-7 of one.", &clamp/1),
      step(
        :scale_clip,
        "the scaled and clipped unit",
        "Runs ScaleFigure's build over the child and s.",
        &scale_clip/1
      ),
      step(
        :fold,
        "fold the top half under",
        "Copies the half above the axis down one step and deletes the originals.",
        &fold/1
      ),
      step(
        :half_step,
        "the half-step rotation",
        "Turns the map by PI/n, skipped when s is one.",
        &half_step/1
      ),
      step(
        :normalise,
        "scale to unit",
        "Scales the map so its maximum x is one.",
        &normalise/1
      )
    ]
  end

  @doc "The built map."
  @spec result(state()) :: PlanarMap.t()
  def result(%{map: map}), do: map

  @impl RadialFigure
  @spec build_unit(t()) :: PlanarMap.t()
  def build_unit(%__MODULE__{child: child, s: s}), do: build_unit(child, s)

  @doc "The unit of `child` at `s`, folded back to an apex at `(1, 0)`."
  @spec build_unit(RadialFigure.t(), float()) :: PlanarMap.t()
  def build_unit(child, s) do
    child
    |> steps(s)
    |> Steps.run!(start(child, s))
    |> Steps.final()
    |> result()
  end

  @impl RadialFigure
  @spec n(t()) :: pos_integer()
  def n(%__MODULE__{child: %module{} = child}), do: module.n(child)

  # -- the stages -------------------------------------------------------------

  defp clamp(state) do
    s = ScaleFigure.normalise_s(state.s)
    %{state | figure: build(state.child, s), s: s, fallback: s == 1.0}
  end

  defp scale_clip(state), do: %{state | map: ScaleFigure.build_unit(state.child, state.s)}

  defp fold(state), do: %{state | map: rotate_half(state.map, n(state.figure))}

  defp half_step(%{fallback: true} = state), do: state

  defp half_step(state) do
    don = RadialFigure.don(n(state.figure))
    %{state | map: PlanarMap.transform!(state.map, Transform.rotate(:math.pi() * don))}
  end

  defp normalise(state) do
    case max_x(state.map) do
      nil -> %{state | max_x: nil}
      max_x -> %{state | map: PlanarMap.scale(state.map, factor(max_x)), max_x: max_x}
    end
  end

  defp max_x(map) do
    map
    |> PlanarMap.vertices()
    |> Enum.map(&PlanarMap.position!(map, &1).x)
    |> Enum.max(fn -> nil end)
  end

  defp factor(max_x) when max_x == 0.0, do: raise(ArgumentError, "connect: zero_extent")
  defp factor(max_x), do: 1.0 / max_x

  # -- the fold ---------------------------------------------------------------

  # Five passes, as the source: select the movers, insert their rotated copies,
  # collect the edges wholly among movers, insert the permuted edges, then delete
  # the originals strictly above the axis. The band |y| <= 1e-7 stays: those
  # vertices are duplicated in place rather than moved, which is the seam.
  defp rotate_half(map, n) do
    tp = Transform.rotate(-2.0 * :math.pi() * RadialFigure.don(n))

    movers =
      map
      |> PlanarMap.vertices()
      |> Enum.filter(fn vertex -> PlanarMap.position!(map, vertex).y + @tol > 0.0 end)
      |> Map.new(fn vertex -> {vertex, vertex} end)

    {map, movers} = insert_copies(map, movers, tp)
    map = permute_edges(map, mover_edges(map, movers), movers)
    delete_originals(map, Map.keys(movers))
  end

  defp insert_copies(map, movers, tp) do
    Enum.reduce(movers, {map, movers}, fn {vertex, _self}, {map, movers} ->
      {map, copy} =
        PlanarMap.insert_vertex(map, Transform.apply_to(tp, PlanarMap.position!(map, vertex)))

      {map, Map.put(movers, vertex, copy)}
    end)
  end

  defp mover_edges(map, movers) do
    Enum.filter(PlanarMap.edges(map), fn edge ->
      {v1, v2} = PlanarMap.endpoints!(map, edge)
      Map.has_key?(movers, v1) and Map.has_key?(movers, v2)
    end)
  end

  defp permute_edges(map, edges, movers) do
    Enum.reduce(edges, map, fn edge, map ->
      {v1, v2} = PlanarMap.endpoints!(map, edge)
      PlanarMap.insert_edge!(map, Map.fetch!(movers, v1), Map.fetch!(movers, v2))
    end)
  end

  defp delete_originals(map, movers) do
    movers
    |> Enum.filter(fn vertex -> PlanarMap.position!(map, vertex).y > @tol end)
    |> Enum.reduce(map, fn vertex, map -> PlanarMap.remove_vertex!(map, vertex) end)
  end
end

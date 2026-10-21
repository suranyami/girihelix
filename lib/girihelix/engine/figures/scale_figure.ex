defmodule Girihelix.Engine.Figures.ScaleFigure do
  @moduledoc """
  A radial figure scaled by `s` and clipped to the unit n-gon, a port of
  Taprats' `ScaleFigure.java`.

  The child is stored **by reference**: this struct aliases the caller's figure
  and never mutates it. Every build asks the child for a fresh unit and scales
  that map, so the child's own unit is untouched.

  **`s` is normalised at construction.** A value within `1e-7` of `1.0` is
  stored as exactly `1.0`, which is the source's `Loose.equals` passthrough and
  makes the step ids' work observable: `:child` returns the child's unit and
  every later stage is a no-op.

  **The non-passthrough build clips instead of scaling the cell.** The unit is
  scaled about the origin, then the edge from the tip at `(s, 0)` outwards is
  clipped against the *unscaled* unit n-gon; rotated copies of that clipped edge
  fill the rest of the unit's half-wedge, each with its x-axis mirror. The tip
  is found by `Loose.equals/2` on positions (squared distance under `1e-10`),
  not by the map's own vertex coalescing. A missing tip or lower neighbour is
  an `ArgumentError` naming `no_tip` or `no_lower_neighbour`, where the source
  would dereference `null`.

  **The zero-length extension is skipped, not built.** When no n-gon edge is
  hit the endpoint falls back to the tip, so the source's intersection segment
  has zero length and its determinant is zero; the source's `getIntersection`
  returns `null` and its loop breaks. The port skips the loop for that case, so
  no zero-length `Segment` is built, and still runs the endpoint insertion.
  """

  @behaviour Girihelix.Engine.Figures.RadialFigure

  import Girihelix.Engine.Steps, only: [step: 4]

  alias Girihelix.Engine.Figures.Figure
  alias Girihelix.Engine.Figures.RadialFigure
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

  # Read at compile time so the normalise guard can use it: a guard cannot call
  # a function, and duplicating the literal here would let the two drift apart.
  @tol Loose.tol()

  @doc """
  Wraps the radial figure `child` at scale `s`.

  A non-radial child is refused with `{:error, :not_radial}` rather than
  raising. `s` is normalised by `normalise_s/1`.
  """
  @spec new(Figure.t(), float()) :: {:ok, t()} | {:error, reason()}
  def new(child, s), do: check_new(Figure.radial?(child), child, s)

  defp check_new(true, child, s), do: {:ok, %__MODULE__{child: child, s: normalise_s(s)}}
  defp check_new(false, _child, _s), do: {:error, :not_radial}

  @doc "`new/2` for a caller that has established the child is radial, raising otherwise."
  @spec new!(Figure.t(), float()) :: t()
  def new!(child, s) do
    case new(child, s) do
      {:ok, figure} -> figure
      {:error, reason} -> raise ArgumentError, "scale: #{reason}"
    end
  end

  @doc """
  `s` with a value within `Loose.tol/0` of one snapped to exactly `1.0`.

  The source's `Loose.equals(s, 1.0)` is `abs(s - 1.0) < 1e-7`, strictly less.
  """
  @spec normalise_s(float()) :: float()
  def normalise_s(s) when is_number(s), do: normalise(s * 1.0)

  defp normalise(s) when abs(s - 1.0) < @tol, do: 1.0
  defp normalise(s), do: s

  @doc "A copy of `figure` with `s` normalised, as `setS` would store it."
  @spec with_s(t(), float()) :: t()
  def with_s(%__MODULE__{} = figure, s), do: %{figure | s: normalise_s(s)}

  @doc """
  A copy of `figure` with `child` replaced, rechecking that the child is radial.

  The source's `childChanged` sets a derived scale; this constructor does not
  derive one, so `s` is kept.
  """
  @spec with_child(t(), Figure.t()) :: {:ok, t()} | {:error, reason()}
  def with_child(%__MODULE__{} = figure, child), do: check_child(Figure.radial?(child), figure, child)

  defp check_child(true, figure, child), do: {:ok, %{figure | child: child}}
  defp check_child(false, _figure, _child), do: {:error, :not_radial}

  @doc "The state `steps/2` starts from: parameters only, every derived field empty."
  @spec start(RadialFigure.t(), float()) :: state()
  def start(child, s) do
    %{
      child: child,
      requested_s: s,
      figure: nil,
      map: nil,
      passthrough: nil,
      tip: nil,
      tip_pos: nil,
      below: nil,
      endpoint: nil,
      border: nil,
      last_top: nil,
      last_bottom: nil
    }
  end

  @doc "The six stages that build the unit."
  @spec steps(RadialFigure.t(), float()) :: [Steps.Step.t()]
  def steps(_child, _s) do
    [
      step(:clamp, "normalise s", "Builds the wrapper and snaps s within 1e-7 of one.", &clamp/1),
      step(
        :child,
        "the child's unit",
        "Builds the child's unit into a fresh map.",
        &child_unit/1
      ),
      step(
        :scale,
        "find the tip and scale",
        "Finds the vertex at (1, 0), then scales every position by s.",
        &scale/1
      ),
      step(
        :clip,
        "clip the tip ray",
        "Extends the tip ray away from the lower neighbour and clips it against the unit n-gon.",
        &clip/1
      ),
      step(
        :extend,
        "the rotated copies",
        "Intersects the clipped edge with rotated mirrors of itself, inserting each crossing and its mirror.",
        &extend/1
      ),
      step(
        :endpoint,
        "the endpoint",
        "Inserts the endpoint and closes both chains unless it coalesced onto the chain head.",
        &endpoint_step/1
      )
    ]
  end

  @doc "The built map."
  @spec result(state()) :: PlanarMap.t()
  def result(%{map: map}), do: map

  @impl RadialFigure
  @spec build_unit(t()) :: PlanarMap.t()
  def build_unit(%__MODULE__{child: child, s: s}), do: build_unit(child, s)

  @doc "The unit of `child` scaled by `s` and clipped to the unit n-gon."
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
    figure = new!(state.child, state.requested_s)
    %{state | figure: figure, passthrough: Loose.equals(figure.s, 1.0)}
  end

  # The passthrough and the clipped build both start from the child's own fresh
  # unit; only what comes after differs.
  defp child_unit(state), do: %{state | map: Figure.unit(state.child)}

  defp scale(%{passthrough: true} = state), do: state

  defp scale(state) do
    tip = find_tip!(state.map)
    map = PlanarMap.scale(state.map, state.figure.s)

    %{
      state
      | map: map,
        tip: tip,
        tip_pos: PlanarMap.position!(map, tip),
        last_top: tip,
        last_bottom: tip
    }
  end

  # The vertices are in the map's tolerant lexicographic order, so among
  # candidates the smallest-x one wins, as the source's scan does.
  defp find_tip!(map) do
    target = Point.new(1.0, 0.0)

    map
    |> PlanarMap.vertices()
    |> Enum.find(&Loose.equals(PlanarMap.position!(map, &1), target))
    |> tip_or_raise()
  end

  defp tip_or_raise(nil), do: raise(ArgumentError, "scale: no_tip")
  defp tip_or_raise(tip), do: tip

  defp clip(%{passthrough: true} = state), do: state

  defp clip(state) do
    border = RadialFigure.unit_ngon(n(state.figure))
    below = below!(state.map, state.tip)
    bpos = PlanarMap.position!(state.map, below)

    seg_end =
      state.tip_pos
      |> Point.subtract(bpos)
      |> Point.normalize()
      |> Point.scale(100.0)
      |> Point.add(state.tip_pos)

    %{state | border: border, below: below, endpoint: first_hit(state.tip_pos, seg_end, border)}
  end

  # The adjacency is in the ring's order from its head: the upper neighbour
  # first for the standard children, so the lower one is found next.
  defp below!(map, tip) do
    map
    |> PlanarMap.ring!(tip)
    |> Enum.map(&far_vertex(map, &1, tip))
    |> Enum.find(fn vertex -> PlanarMap.position!(map, vertex).y < 0.0 end)
    |> below_or_raise()
  end

  defp below_or_raise(nil), do: raise(ArgumentError, "scale: no_lower_neighbour")
  defp below_or_raise(vertex), do: vertex

  defp far_vertex(map, edge, vertex) do
    case PlanarMap.endpoints!(map, edge) do
      {^vertex, other} -> other
      {other, _second} -> other
    end
  end

  # The first hit in edge order, not the nearest one; the fallback is the tip,
  # the source's degenerate zero-length extension.
  defp first_hit(tip_pos, seg_end, border) do
    ray = Segment.new!(tip_pos, seg_end)
    n = length(border)

    Enum.find_value(0..(n - 1), tip_pos, fn index ->
      poly_a = Enum.at(border, index)
      poly_b = Enum.at(border, rem(index + 1, n))
      Intersect.get_intersection(ray, Segment.new!(poly_a, poly_b))
    end)
  end

  # With the endpoint at the tip the fixed segment is zero-length: the
  # source's determinant is zero and every intersection is null, so its loop
  # breaks on the first pass. Skipping the loop is the same outcome without a
  # `Segment` that cannot exist.
  defp extend(%{passthrough: true} = state), do: state

  defp extend(%{endpoint: endpoint, tip_pos: tip_pos} = state) when endpoint == tip_pos, do: state

  defp extend(state) do
    tr = RadialFigure.tr(n(state.figure))
    fixed = Segment.new!(state.tip_pos, state.endpoint)

    rotated = {
      Transform.apply_to(tr, state.tip_pos),
      Transform.apply_to(tr, RadialFigure.mirror(state.endpoint))
    }

    {map, last_top, last_bottom, _rotated} =
      Enum.reduce_while(
        0..(div(n(state.figure) + 1, 2) - 1),
        {state.map, state.tip, state.tip, rotated},
        fn _index, {map, last_top, last_bottom, {neg_start, neg_end}} ->
          case Intersect.get_intersection(fixed, Segment.new!(neg_start, neg_end)) do
            nil ->
              {:halt, {map, last_top, last_bottom, {neg_start, neg_end}}}

            isect ->
              {map, iv} = PlanarMap.insert_vertex(map, isect)
              map = PlanarMap.insert_edge!(map, last_top, iv)
              {map, mirror_iv} = PlanarMap.insert_vertex(map, RadialFigure.mirror(isect))
              map = PlanarMap.insert_edge!(map, last_bottom, mirror_iv)

              next = {Transform.apply_to(tr, neg_start), Transform.apply_to(tr, neg_end)}
              {:cont, {map, iv, mirror_iv, next}}
          end
        end
      )

    %{state | map: map, last_top: last_top, last_bottom: last_bottom}
  end

  defp endpoint_step(%{passthrough: true} = state), do: state

  defp endpoint_step(state) do
    {map, iv} = PlanarMap.insert_vertex(state.map, state.endpoint)
    place_endpoint(map, iv, state)
  end

  # Reference equality in the source, which `insert_vertex/2` answers as handle
  # equality: the endpoint coalesced onto the vertex the chain already reached.
  defp place_endpoint(map, iv, %{last_top: last_top} = state) when iv == last_top, do: %{state | map: map}

  defp place_endpoint(map, iv, state) do
    map = PlanarMap.insert_edge!(map, state.last_top, iv)
    {map, mirror_iv} = PlanarMap.insert_vertex(map, RadialFigure.mirror(state.endpoint))
    map = PlanarMap.insert_edge!(map, state.last_bottom, mirror_iv)
    %{state | map: map}
  end
end

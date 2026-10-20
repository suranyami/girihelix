defmodule Girihelix.Engine.PlanarMap do
  @moduledoc """
  A planar straight-line graph: vertices at points, edges between them, and for
  every vertex a ring of its edges in counter-clockwise order.

  A vertex or an edge is a `non_neg_integer()` handle. Handles are never reused
  within a map, and only the map holds the state behind them: a caller keeps
  handles, never positions or rings. Every function that takes a handle returns
  `{:ok, result}` or `{:error, :unknown_vertex | :unknown_edge}`, and has a `!`
  twin that raises `ArgumentError` naming the reason.

  The type is opaque, and only this module builds, matches or updates it.

  The map's invariant is that no two edges cross and no vertex lies on an edge it
  does not end. Keeping it is the caller's precondition: `insert_edge/3` is
  unchecked, so it accepts a crossing edge, a parallel edge, and an edge from a
  vertex to itself (which appears twice in that vertex's ring, at angle `0.5`).

  `vertices/1` and `edges/1` list handles in a fixed order: vertices
  lexicographically by position, edges by minimum x. Both orders compare with a
  `1.0e-7` tolerance, and a tolerance comparator is not transitive. Points are
  the same vertex when both coordinate differences are under `1.0e-7`, a square
  window. The shortcomings that follow from this and from the map's other
  deliberate behaviours are recorded in `docs/algorithm-analysis.md`.
  """

  import Girihelix.Engine.Steps, only: [step: 4]

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.Engine.PlanarMap.Order
  alias Girihelix.Engine.PlanarMap.Ring
  alias Girihelix.Engine.PlanarMap.Split
  alias Girihelix.Engine.Steps

  @enforce_keys [:vertices, :edges, :vertex_order, :edge_order, :next]
  defstruct [:vertices, :edges, :vertex_order, :edge_order, :next]

  @opaque t :: %__MODULE__{
            vertices: %{vertex() => %{pos: Point.t(), ring: Ring.t()}},
            edges: %{edge() => {vertex(), vertex()}},
            vertex_order: [vertex()],
            edge_order: [edge()],
            next: non_neg_integer()
          }

  @type vertex :: non_neg_integer()
  @type edge :: non_neg_integer()
  @type reason :: :unknown_vertex | :unknown_edge

  @doc "An empty map."
  @spec new() :: t()
  def new, do: %__MODULE__{vertices: %{}, edges: %{}, vertex_order: [], edge_order: [], next: 0}

  # -- insertion --------------------------------------------------------------

  @doc """
  The vertex at `point`: the existing one when a vertex lies within the
  `1.0e-7` square window of it, otherwise a new vertex.

  Either way, when the vertex lies on an edge it does not end, that edge is split
  at it into two. At most one edge is split per call: a vertex on two crossing
  edges splits only the first in edge order.
  """
  @spec insert_vertex(t(), Point.t()) :: {t(), vertex()}
  def insert_vertex(%__MODULE__{} = map, %Point{} = point) do
    entries = Enum.map(map.vertex_order, &{&1, map.vertices[&1].pos})
    {map, vertex} = place_vertex(Order.find_or_insert(entries, point), map, point)
    {split_at(map, vertex), vertex}
  end

  defp split_at(map, vertex) do
    point = map.vertices[vertex].pos

    candidates =
      Enum.map(map.edge_order, fn edge ->
        {v1, v2} = Map.fetch!(map.edges, edge)
        {edge, map.vertices[v1].pos, map.vertices[v2].pos}
      end)

    split_edge(Split.first_splittable(candidates, point), map, vertex)
  end

  defp split_edge(nil, map, _vertex), do: map

  defp split_edge(edge, map, vertex) do
    {v1, v2} = Map.fetch!(map.edges, edge)
    new_edge = map.next
    far_edge = find_neighbour(map, v2, v1)
    vpos = map.vertices[vertex].pos

    %{
      map
      | edges: map.edges |> Map.put(new_edge, {vertex, v2}) |> Map.put(edge, {v1, vertex}),
        next: new_edge + 1
    }
    |> update_ring(v2, &Ring.swap(&1, far_edge, new_edge))
    |> reorder_split(edge, new_edge)
    |> register(vertex, {edge, Ring.angle(vpos, map.vertices[v1].pos)})
    |> register(vertex, {new_edge, Ring.angle(vpos, map.vertices[v2].pos)})
  end

  defp update_ring(map, vertex, fun) do
    %{map | vertices: Map.update!(map.vertices, vertex, &%{&1 | ring: fun.(&1.ring)})}
  end

  # The split edge leaves the edge order and both halves go back in by minimum x,
  # the new far half first.
  defp reorder_split(map, edge, new_edge) do
    %{map | edge_order: List.delete(map.edge_order, edge)}
    |> insert_in_order(new_edge)
    |> insert_in_order(edge)
  end

  defp insert_in_order(map, edge) do
    keys = Enum.map(map.edge_order, &min_x(map, &1))
    index = Order.edge_insert_index(keys, min_x(map, edge))
    %{map | edge_order: List.insert_at(map.edge_order, index, edge)}
  end

  defp place_vertex({:found, vertex}, map, _point), do: {map, vertex}

  defp place_vertex({:insert_at, index}, map, point) do
    vertex = map.next

    {%{
       map
       | vertices: Map.put(map.vertices, vertex, %{pos: point, ring: []}),
         vertex_order: List.insert_at(map.vertex_order, index, vertex),
         next: vertex + 1
     }, vertex}
  end

  @doc """
  Adds an edge between two vertices, without any check of the result: it may
  cross another edge, repeat one, or join a vertex to itself.
  """
  @spec insert_edge(t(), vertex(), vertex()) :: {:ok, t()} | {:error, :unknown_vertex}
  def insert_edge(%__MODULE__{} = map, v1, v2) do
    with {:ok, p1} <- position(map, v1),
         {:ok, p2} <- position(map, v2) do
      {:ok, add_edge(map, v1, p1, v2, p2)}
    end
  end

  @doc "`insert_edge/3`, raising `ArgumentError` on an unknown vertex."
  @spec insert_edge!(t(), vertex(), vertex()) :: t()
  def insert_edge!(map, v1, v2), do: map |> insert_edge(v1, v2) |> unwrap!()

  defp add_edge(map, v1, p1, v2, p2) do
    edge = map.next
    keys = Enum.map(map.edge_order, &min_x(map, &1))
    index = Order.edge_insert_index(keys, min(p1.x, p2.x))

    %{
      map
      | edges: Map.put(map.edges, edge, {v1, v2}),
        edge_order: List.insert_at(map.edge_order, index, edge),
        next: edge + 1
    }
    |> register(v1, {edge, Ring.angle(p1, p2)})
    |> register(v2, {edge, Ring.angle(p2, p1)})
  end

  defp register(map, vertex, entry) do
    %{
      map
      | vertices: Map.update!(map.vertices, vertex, &%{&1 | ring: Ring.insert(&1.ring, entry)})
    }
  end

  defp min_x(map, edge) do
    {v1, v2} = Map.fetch!(map.edges, edge)
    min(map.vertices[v1].pos.x, map.vertices[v2].pos.x)
  end

  # -- removal and rigid motions -----------------------------------------------

  @doc """
  Removes `vertex` and every edge at it. The far end of each such edge loses it
  from its ring, and a ring whose head was that edge takes the edge before it as
  its new head. Every handle of the removed vertex and edges is unknown after.
  """
  @spec remove_vertex(t(), vertex()) :: {:ok, t()} | {:error, :unknown_vertex}
  def remove_vertex(%__MODULE__{} = map, vertex) do
    with {:ok, %{ring: ring}} <- fetch_vertex(map, vertex) do
      removed =
        ring |> Ring.edges() |> Enum.reduce(map, &remove_edge(&2, &1, vertex))

      {:ok,
       %{
         removed
         | vertices: Map.delete(removed.vertices, vertex),
           vertex_order: List.delete(removed.vertex_order, vertex)
       }}
    end
  end

  @doc "`remove_vertex/2`, raising `ArgumentError` on an unknown vertex."
  @spec remove_vertex!(t(), vertex()) :: t()
  def remove_vertex!(map, vertex), do: map |> remove_vertex(vertex) |> unwrap!()

  # An edge at a self-edge's vertex is listed twice in its ring; the second
  # visit finds it already gone.
  defp remove_edge(map, edge, vertex) do
    remove_known_edge(map, edge, Map.fetch(map.edges, edge), vertex)
  end

  defp remove_known_edge(map, _edge, :error, _vertex), do: map

  defp remove_known_edge(map, edge, {:ok, ends}, vertex) do
    update_ring(
      %{map | edges: Map.delete(map.edges, edge), edge_order: List.delete(map.edge_order, edge)},
      far_end(ends, vertex),
      &Ring.remove(&1, edge)
    )
  end

  @doc """
  Applies `transform` to every position, recomputes the ring angles, and puts
  both orders back in sequence.

  Rings keep their order. A transform that flips (negative determinant) leaves
  every ring in its old rotational order, undetected. Angles are recomputed
  vertex by vertex against neighbours that may not have moved yet, so a later
  insertion can land where the true angles would not put it.
  """

  @spec transform(t(), Transform.t()) :: t()
  def transform(%__MODULE__{} = map, %Transform{} = transform) do
    moved = Enum.reduce(map.vertex_order, map, &move_vertex(&2, &1, transform))

    sort_edges(%{
      moved
      | vertex_order: Order.sort(moved.vertex_order, &moved.vertices[&1].pos, &Order.compare_points/2)
    })
  end

  defp move_vertex(map, vertex, transform) do
    pos = Transform.apply_to(transform, map.vertices[vertex].pos)
    moved = %{map | vertices: Map.update!(map.vertices, vertex, &%{&1 | pos: pos})}

    update_ring(moved, vertex, fn ring ->
      Ring.reangle(ring, fn edge ->
        Ring.angle(pos, moved.vertices[far_end(moved.edges[edge], vertex)].pos)
      end)
    end)
  end

  @doc "Scales every position about the origin. No angle or order is recomputed."
  @spec scale(t(), number()) :: t()
  def scale(map, factor), do: move_all(map, Transform.scale(factor))

  @doc "Translates every position. No angle or order is recomputed."
  @spec translate(t(), number(), number()) :: t()
  def translate(map, x, y), do: move_all(map, Transform.translate(x, y))

  defp move_all(%__MODULE__{} = map, transform) do
    %{
      map
      | vertices:
          Map.new(map.vertices, fn {vertex, entry} ->
            {vertex, %{entry | pos: Transform.apply_to(transform, entry.pos)}}
          end)
    }
  end

  # -- replication ------------------------------------------------------------

  @doc """
  Copies `unit` into `receiver` once under each of `transforms`, and returns the
  result. It is the last state of `replicate_steps/2`.

  Each copy puts a vertex at the transformed position of every unit vertex,
  reusing a receiver vertex within the `1.0e-7` window, and joins the copies by
  an edge for every unit edge. Nothing is checked or split: a copied vertex that
  lands on an edge splits nothing, and two unit vertices that land on one
  receiver vertex give a self-edge. The unit is not changed.
  """
  @spec replicate(t(), t(), [Transform.t()]) :: t()
  def replicate(%__MODULE__{} = receiver, %__MODULE__{} = unit, transforms) do
    unit |> replicate_steps(transforms) |> Steps.run!(receiver) |> Steps.final()
  end

  @doc """
  The stages of `replicate/3` as a step sequence over the receiver map: one
  `:copy` step per transform, then one `:sort_edges` step. With no transforms
  there is only the sort.
  """
  @spec replicate_steps(t(), [Transform.t()]) :: [Steps.Step.t()]
  def replicate_steps(%__MODULE__{} = unit, transforms) do
    copies =
      transforms
      |> Enum.with_index(1)
      |> Enum.map(fn {transform, k} ->
        step(
          :copy,
          "copy under transform #{k}",
          "Puts a vertex at the transformed position of every unit vertex, reusing any receiver vertex already there, then appends an edge for every unit edge.",
          &copy_unit(&1, unit, transform)
        )
      end)

    copies ++
      [
        step(
          :sort_edges,
          "sort edges",
          "Puts the appended edges in minimum-x order, keeping the order of edges that compare equal.",
          &sort_edges/1
        )
      ]
  end

  defp copy_unit(map, unit, transform) do
    {mapped, map} =
      Enum.reduce(unit.vertex_order, {%{}, map}, fn vertex, {mapped, map} ->
        {map, copy} =
          find_or_create(map, Transform.apply_to(transform, unit.vertices[vertex].pos))

        {Map.put(mapped, vertex, copy), map}
      end)

    Enum.reduce(unit.edge_order, map, fn edge, map ->
      {v1, v2} = Map.fetch!(unit.edges, edge)
      append_edge(map, Map.fetch!(mapped, v1), Map.fetch!(mapped, v2))
    end)
  end

  defp find_or_create(map, point) do
    entries = Enum.map(map.vertex_order, &{&1, map.vertices[&1].pos})
    place_vertex(Order.find_or_insert(entries, point), map, point)
  end

  defp append_edge(map, v1, v2) do
    edge = map.next
    p1 = map.vertices[v1].pos
    p2 = map.vertices[v2].pos

    %{
      map
      | edges: Map.put(map.edges, edge, {v1, v2}),
        edge_order: map.edge_order ++ [edge],
        next: edge + 1
    }
    |> register(v1, {edge, Ring.angle(p1, p2)})
    |> register(v2, {edge, Ring.angle(p2, p1)})
  end

  defp sort_edges(map), do: %{map | edge_order: Order.sort(map.edge_order, &min_x(map, &1), &Order.compare_min_x/2)}

  # -- queries ----------------------------------------------------------------

  @doc "The number of vertices."
  @spec num_vertices(t()) :: non_neg_integer()
  def num_vertices(%__MODULE__{vertices: vertices}), do: map_size(vertices)

  @doc "The number of edges."
  @spec num_edges(t()) :: non_neg_integer()
  def num_edges(%__MODULE__{edges: edges}), do: map_size(edges)

  @doc "Every vertex, in the map's vertex order."
  @spec vertices(t()) :: [vertex()]
  def vertices(%__MODULE__{vertex_order: order}), do: order

  @doc "Every edge, in the map's edge order."
  @spec edges(t()) :: [edge()]
  def edges(%__MODULE__{edge_order: order}), do: order

  @doc "Where `vertex` lies."
  @spec position(t(), vertex()) :: {:ok, Point.t()} | {:error, :unknown_vertex}
  def position(map, vertex), do: map |> fetch_vertex(vertex) |> map_ok(fn %{pos: pos} -> pos end)

  @doc "`position/2`, raising `ArgumentError` on an unknown vertex."
  @spec position!(t(), vertex()) :: Point.t()
  def position!(map, vertex), do: map |> position(vertex) |> unwrap!()

  @doc "The two endpoints of `edge`, in the order it was inserted with."
  @spec endpoints(t(), edge()) :: {:ok, {vertex(), vertex()}} | {:error, :unknown_edge}
  def endpoints(%__MODULE__{edges: edges}, edge), do: edges |> Map.fetch(edge) |> tag_error(:unknown_edge)

  @doc "`endpoints/2`, raising `ArgumentError` on an unknown edge."
  @spec endpoints!(t(), edge()) :: {vertex(), vertex()}
  def endpoints!(map, edge), do: map |> endpoints(edge) |> unwrap!()

  @doc "The edges at `vertex` in counter-clockwise order, starting from the ring's head."
  @spec ring(t(), vertex()) :: {:ok, [edge()]} | {:error, :unknown_vertex}
  def ring(map, vertex), do: map |> fetch_vertex(vertex) |> map_ok(fn %{ring: ring} -> Ring.edges(ring) end)

  @doc "`ring/2`, raising `ArgumentError` on an unknown vertex."
  @spec ring!(t(), vertex()) :: [edge()]
  def ring!(map, vertex), do: map |> ring(vertex) |> unwrap!()

  @doc """
  The first edge in `vertex`'s ring, from the head, whose far end is `other`, or
  `nil` when there is none.
  """
  @spec neighbour(t(), vertex(), vertex()) :: {:ok, edge() | nil} | {:error, :unknown_vertex}
  def neighbour(%__MODULE__{} = map, vertex, other) do
    with {:ok, _ring} <- ring(map, vertex) do
      {:ok, find_neighbour(map, vertex, other)}
    end
  end

  defp find_neighbour(map, vertex, other) do
    map.vertices[vertex].ring
    |> Ring.edges()
    |> Enum.find(&(far_end(map.edges[&1], vertex) == other))
  end

  @doc "`neighbour/3`, raising `ArgumentError` on an unknown vertex."
  @spec neighbour!(t(), vertex(), vertex()) :: edge() | nil
  def neighbour!(map, vertex, other), do: map |> neighbour(vertex, other) |> unwrap!()

  defp far_end({vertex, other}, vertex), do: other
  defp far_end({other, _second}, _vertex), do: other

  @doc """
  The edges either side of `edge` in `vertex`'s ring, as `{before, after}`, or
  `nil` when the ring does not hold `edge`. In a ring of one or two edges both
  sides are the same edge.
  """
  @spec before_and_after(t(), vertex(), edge()) ::
          {:ok, {edge(), edge()} | nil} | {:error, reason()}
  def before_and_after(%__MODULE__{} = map, vertex, edge) do
    with {:ok, %{ring: ring}} <- fetch_vertex(map, vertex),
         {:ok, _endpoints} <- endpoints(map, edge) do
      {:ok, Ring.before_and_after(ring, edge)}
    end
  end

  @doc "`before_and_after/3`, raising `ArgumentError` on an unknown handle."
  @spec before_and_after!(t(), vertex(), edge()) :: {edge(), edge()} | nil
  def before_and_after!(map, vertex, edge), do: map |> before_and_after(vertex, edge) |> unwrap!()

  # -- helpers ----------------------------------------------------------------

  defp fetch_vertex(%__MODULE__{vertices: vertices}, vertex),
    do: vertices |> Map.fetch(vertex) |> tag_error(:unknown_vertex)

  defp tag_error({:ok, _value} = ok, _reason), do: ok
  defp tag_error(:error, reason), do: {:error, reason}

  defp map_ok({:ok, value}, fun), do: {:ok, fun.(value)}
  defp map_ok({:error, _reason} = error, _fun), do: error

  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, reason}), do: raise(ArgumentError, "planar map: #{reason}")
end

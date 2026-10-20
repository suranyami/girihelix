defmodule Girihelix.Engine.PlanarMap do
  @moduledoc """
  A planar straight-line graph: vertices at points, edges between them, and for
  every vertex a ring of its edges in counter-clockwise order.

  A vertex or an edge is a `non_neg_integer()` handle. Handles are never reused
  within a map, and only the map holds the state behind them: a caller keeps
  handles, never positions or rings. Every function that takes a handle returns
  `{:ok, result}` or `{:error, :unknown_vertex | :unknown_edge}`, and has a `!`
  twin that raises `ArgumentError` naming the reason.

  `transform/2`, `replicate/3` and `weld/2` sort the vertex or edge order with
  Java's list sort, as Taprats does. Where Java would throw because the
  tolerance comparator broke its contract, and Taprats would crash, they return
  `{:error, :inconsistent_order}`; their `!` twins raise it. `scale/2` and
  `translate/3` never sort, and return the map bare.

  The type is opaque, and only this module builds, matches or updates it.

  A handle belongs to no map in particular. A handle from a different map that
  happens to exist in this one cannot be told apart: it resolves to this map's
  vertex or edge of the same number.

  Coordinates are assumed well below about `1.0e150` in magnitude. Beyond that a
  squared distance overflows, and Erlang float arithmetic raises where an
  infinity would carry on. Nothing guards against it.

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
  alias Girihelix.Engine.PlanarMap.Check
  alias Girihelix.Engine.PlanarMap.Order
  alias Girihelix.Engine.PlanarMap.Ring
  alias Girihelix.Engine.PlanarMap.Split
  alias Girihelix.Engine.PlanarMap.Verify
  alias Girihelix.Engine.PlanarMap.Weld
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
  @type reason :: :unknown_vertex | :unknown_edge | :inconsistent_order

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

  @doc """
  Adds an edge like `insert_edge/3`, but refuses one that would meet the map
  anywhere other than at its own two end vertices: a crossing, a T-junction, an
  overlap, a repeat of an existing edge, a self-edge, or a pass through another
  vertex.
  """
  @spec insert_edge_checked(t(), vertex(), vertex()) ::
          {:ok, t()} | {:error, :unknown_vertex | :crosses}
  def insert_edge_checked(%__MODULE__{} = map, v1, v2) do
    with {:ok, grown} <- insert_edge(map, v1, v2) do
      checked(Check.crosses?(map, v1, v2), grown)
    end
  end

  defp checked(true, _grown), do: {:error, :crosses}
  defp checked(false, grown), do: {:ok, grown}

  @doc "`insert_edge_checked/3`, raising `ArgumentError` naming the reason."
  @spec insert_edge_checked!(t(), vertex(), vertex()) :: t()
  def insert_edge_checked!(map, v1, v2), do: map |> insert_edge_checked(v1, v2) |> unwrap!()

  @doc """
  Checks the map's structure, for tests. `:ok` when sound, else
  `{:error, problems}`; see `Girihelix.Engine.PlanarMap.Verify` for the problems.
  """
  @spec verify(t()) :: :ok | {:error, [Verify.problem()]}
  def verify(%__MODULE__{} = map), do: map |> Verify.problems() |> verdict()

  defp verdict([]), do: :ok
  defp verdict(problems), do: {:error, problems}

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

  Returns `{:error, :inconsistent_order}` where either sort meets a broken
  comparator contract.
  """
  @spec transform(t(), Transform.t()) :: {:ok, t()} | {:error, :inconsistent_order}
  def transform(%__MODULE__{} = map, %Transform{} = transform) do
    moved = Enum.reduce(map.vertex_order, map, &move_vertex(&2, &1, transform))

    with {:ok, order} <-
           Order.sort(moved.vertex_order, &moved.vertices[&1].pos, &Order.compare_points/2) do
      sort_edges(%{moved | vertex_order: order})
    end
  end

  @doc "As `transform/2`, but returns the bare map and raises `ArgumentError` naming the reason."
  @spec transform!(t(), Transform.t()) :: t()
  def transform!(map, transform), do: map |> transform(transform) |> unwrap!()

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

  Returns `{:error, :inconsistent_order}` where the final edge sort meets a
  broken comparator contract.
  """
  @spec replicate(t(), t(), [Transform.t()]) :: {:ok, t()} | {:error, :inconsistent_order}
  def replicate(%__MODULE__{} = receiver, %__MODULE__{} = unit, transforms) do
    unit
    |> replicate_steps(transforms)
    |> Steps.run!(replicate_start(receiver))
    |> Steps.final()
    |> replicate_result()
  end

  @doc "As `replicate/3`, but returns the bare map and raises `ArgumentError` naming the reason."
  @spec replicate!(t(), t(), [Transform.t()]) :: t()
  def replicate!(receiver, unit, transforms), do: receiver |> replicate(unit, transforms) |> unwrap!()

  @typedoc """
  The state `replicate_steps/2` runs over: the receiver map, and the failure of
  the final sort, if it failed.
  """
  @type replicate_state :: %{receiver: t(), failure: nil | :inconsistent_order}

  @doc "The state `replicate_steps/2` starts from."
  @spec replicate_start(t()) :: replicate_state()
  def replicate_start(%__MODULE__{} = receiver), do: %{receiver: receiver, failure: nil}

  @doc "The outcome of a finished `t:replicate_state/0`."
  @spec replicate_result(replicate_state()) :: {:ok, t()} | {:error, :inconsistent_order}
  def replicate_result(%{failure: nil, receiver: receiver}), do: {:ok, receiver}
  def replicate_result(%{failure: reason}), do: {:error, reason}

  @doc """
  The stages of `replicate/3` as a step sequence over a `t:replicate_state/0`:
  one `:copy` step per transform, then one `:sort_edges` step. With no
  transforms there is only the sort. If the sort meets a broken comparator
  contract, the last frame keeps the edges in appended order and records the
  failure.
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
          &%{&1 | receiver: copy_unit(&1.receiver, unit, transform)}
        )
      end)

    copies ++
      [
        step(
          :sort_edges,
          "sort edges",
          "Puts the appended edges in minimum-x order with Java's list sort, recording a failure where Java would throw.",
          &sort_receiver/1
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

  defp sort_edges(map), do: map.edge_order |> Order.sort(&min_x(map, &1), &Order.compare_min_x/2) |> with_edge_order(map)

  defp with_edge_order({:ok, order}, map), do: {:ok, %{map | edge_order: order}}
  defp with_edge_order({:error, _reason} = error, _map), do: error

  # The final step of both sequences: the receiver sorted, or left in appended
  # order with the failure recorded.
  defp sort_receiver(%{receiver: receiver} = state), do: receiver |> sort_edges() |> record_sort(state)

  defp record_sort({:ok, sorted}, state), do: %{state | receiver: sorted}
  defp record_sort({:error, reason}, state), do: %{state | failure: reason}

  # -- welding ----------------------------------------------------------------

  @typedoc """
  The state `weld_steps/0` runs over: both maps, the other map's vertices as
  they were before welding, the crossings found, where each other-map vertex
  went in the receiver, and the failure of the final sort, if it failed.
  """
  @type weld_state :: %{
          receiver: t(),
          other: t(),
          originals: [vertex()],
          crossings: [Point.t()],
          mapping: %{vertex() => vertex()},
          failure: nil | :inconsistent_order
        }

  @doc """
  Welds `other` into `receiver`, and returns the result with a map from every
  vertex of `other` to the receiver vertex it became. It is the last state of
  `weld_steps/0`, run from `weld_start/2`.

  Wherever an edge of `other` crosses an edge of `receiver`, both are split at a
  new vertex. Vertices then unify where they compare equal within the `1.0e-7`
  window, the receiver's vertex surviving, and every edge of `other` is copied
  across. Only crossings between the two maps are found. Overlapping collinear
  edges are neither split nor merged, so a shared side becomes two parallel
  edges, and welding a map with itself doubles every edge. Unification walks
  the two vertex orders once, so of several `other` vertices within the window
  of one receiver vertex only the first is unified with it. `other` is not
  changed.

  Returns `{:error, :inconsistent_order}` where the final edge sort meets a
  broken comparator contract.
  """
  @spec weld(t(), t()) :: {:ok, {t(), %{vertex() => vertex()}}} | {:error, :inconsistent_order}
  def weld(%__MODULE__{} = receiver, %__MODULE__{} = other) do
    weld_steps() |> Steps.run!(weld_start(receiver, other)) |> Steps.final() |> weld_result()
  end

  @doc "As `weld/2`, but returns the bare result and raises `ArgumentError` naming the reason."
  @spec weld!(t(), t()) :: {t(), %{vertex() => vertex()}}
  def weld!(receiver, other), do: receiver |> weld(other) |> unwrap!()

  @doc "The state `weld_steps/0` starts from."
  @spec weld_start(t(), t()) :: weld_state()
  def weld_start(%__MODULE__{} = receiver, %__MODULE__{} = other) do
    %{
      receiver: receiver,
      other: other,
      originals: vertices(other),
      crossings: [],
      mapping: %{},
      failure: nil
    }
  end

  @doc """
  The stages of `weld/2` as a step sequence over a `t:weld_state/0`:
  `:find_crossings`, `:force_vertices`, `:unify_vertices` and `:copy_edges`.
  If the final sort meets a broken comparator contract, the last frame keeps
  the edges in appended order and records the failure.
  """
  @spec weld_steps() :: [Steps.Step.t()]
  def weld_steps do
    [
      step(
        :find_crossings,
        "find crossings",
        "Finds every point where an edge of the other map crosses an edge of the receiver.",
        &find_crossings/1
      ),
      step(
        :force_vertices,
        "force vertices",
        "Puts a vertex at every crossing in the receiver and then in the other map, splitting the edges there.",
        &force_vertices/1
      ),
      step(
        :unify_vertices,
        "unify vertices",
        "Merges the two vertex orders: a vertex of the other map equal to the receiver vertex reached becomes that vertex, and any other becomes a new receiver vertex.",
        &unify_vertices/1
      ),
      step(
        :copy_edges,
        "copy edges",
        "Copies every edge of the other map between the receiver vertices its ends became, then puts the edges in minimum-x order with Java's list sort, recording a failure where Java would throw.",
        &copy_edges/1
      )
    ]
  end

  @doc """
  The outcome of a finished `t:weld_state/0`: the welded receiver and the
  mapping, restricted to the other map's vertices from before welding, or the
  failure of the final sort.
  """
  @spec weld_result(weld_state()) ::
          {:ok, {t(), %{vertex() => vertex()}}} | {:error, :inconsistent_order}
  def weld_result(%{failure: nil, receiver: receiver, originals: originals, mapping: mapping}),
    do: {:ok, {receiver, Map.take(mapping, originals)}}

  def weld_result(%{failure: reason}), do: {:error, reason}

  defp find_crossings(%{receiver: receiver, other: other} = state),
    do: %{state | crossings: Weld.crossings(edge_ends(other), edge_ends(receiver))}

  defp edge_ends(map) do
    Enum.map(map.edge_order, fn edge ->
      {v1, v2} = Map.fetch!(map.edges, edge)
      {map.vertices[v1].pos, map.vertices[v2].pos}
    end)
  end

  defp force_vertices(%{crossings: crossings} = state) do
    Enum.reduce(crossings, state, fn point, %{receiver: receiver, other: other} = acc ->
      {receiver, _vertex} = insert_vertex(receiver, point)
      {other, _vertex} = insert_vertex(other, point)
      %{acc | receiver: receiver, other: other}
    end)
  end

  defp unify_vertices(%{receiver: receiver, other: other} = state) do
    plan = Weld.merge_plan(positioned(receiver), positioned(other))
    {order, receiver, mapping} = Enum.reduce(plan, {[], receiver, %{}}, &unify(&1, &2, other))
    %{state | receiver: %{receiver | vertex_order: Enum.reverse(order)}, mapping: mapping}
  end

  defp positioned(map), do: Enum.map(map.vertex_order, &{&1, map.vertices[&1].pos})

  defp unify({:mine, m}, {order, receiver, mapping}, _other), do: {[m | order], receiver, mapping}

  defp unify({:same, m, y}, {order, receiver, mapping}, _other), do: {[m | order], receiver, Map.put(mapping, y, m)}

  defp unify({:yours, y}, {order, receiver, mapping}, other) do
    vertex = receiver.next

    receiver = %{
      receiver
      | vertices: Map.put(receiver.vertices, vertex, %{pos: other.vertices[y].pos, ring: []}),
        next: vertex + 1
    }

    {[vertex | order], receiver, Map.put(mapping, y, vertex)}
  end

  defp copy_edges(%{receiver: receiver, other: other, mapping: mapping} = state) do
    copied =
      Enum.reduce(other.edge_order, receiver, fn edge, acc ->
        {v1, v2} = Map.fetch!(other.edges, edge)
        append_edge(acc, Map.fetch!(mapping, v1), Map.fetch!(mapping, v2))
      end)

    sort_receiver(%{state | receiver: copied})
  end

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
  `nil` when there is none. Both vertices must exist.
  """
  @spec neighbour(t(), vertex(), vertex()) :: {:ok, edge() | nil} | {:error, :unknown_vertex}
  def neighbour(%__MODULE__{} = map, vertex, other) do
    with {:ok, _ring} <- ring(map, vertex),
         {:ok, _position} <- position(map, other) do
      {:ok, find_neighbour(map, vertex, other)}
    end
  end

  defp find_neighbour(map, vertex, other) do
    map.vertices[vertex].ring
    |> Ring.edges()
    |> Enum.find(&(far_end(map.edges[&1], vertex) == other))
  end

  @doc "`neighbour/3`, raising `ArgumentError` when either vertex is unknown."
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

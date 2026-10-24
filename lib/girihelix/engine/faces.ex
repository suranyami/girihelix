defmodule Girihelix.Engine.Faces do
  @moduledoc """
  Discovers a planar map's faces and two-colours them, so that faces sharing an
  edge get opposite colours.

  A face is its corner points in traversal order, with no repeated closing
  point. It is not a polygon: a face can have two corners, for example between
  two parallel edges.

  ## Discovery

  Every edge is walked from each of its ends, skipping a side that an earlier
  walk already registered. A walk that enters a vertex of degree one is
  abandoned and registers nothing.

  A clockwise face is the contour around the whole map rather than a real face,
  so it is left out of the result. **Its edges are still registered**, which
  means the colouring can reach it. It is coloured like any other face, and can
  then be a conflicting neighbour of a real face. That is why a map like a
  square split by a diagonal reports `{:error, :filling_conflict}`.

  The walk stops at the first return to its starting vertex, so a face that
  visits a vertex twice before closing yields a partial face. The walk has no
  iteration cap; a map whose ring order does not lead back to its start does
  not terminate.

  ## Colouring

  Faces are coloured from a stack. The first discovered face seeds an island,
  that island is drained, and each remaining island is then seeded in
  discovery order from its own first discovered face. Every island is
  therefore coloured.

  A face with no coloured neighbour is black, so each island's first face is
  black. This differs from Taprats, which seeds only the first face: faces
  that meet only at a vertex share no edge and so form separate islands, and
  seeding one leaves every other island uncoloured. In a flower tiling that
  leaves all but one rosette blank.

  A neighbour that is on the stack but not yet coloured contributes no
  constraint, so an inconsistent colouring is detected only when a face meets
  two differently coloured neighbours. That check is order-dependent and can
  miss a violation; `{:error, :filling_conflict}` means a conflict was seen,
  not that the map is provably two-colourable. A recorded conflict stops any
  further seeding.

  A map with no kept face at all returns `{:error, :no_faces}`.
  """

  import Girihelix.Engine.Steps, only: [step: 4]

  alias Girihelix.Engine.Faces.Walk
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Steps

  @type face :: [Point.t()]
  @type colouring :: %{black: [face()], white: [face()]}
  @type reason :: :filling_conflict | :no_faces
  @type face_state :: :undone | :processing | :black | :white

  @typedoc """
  The state the discovery and colouring steps run over: the two direction
  tables, every discovered face (including rejected outer contours), the kept
  faces in discovery order, the colouring stack, and the failure if any.
  """
  @type state :: %{
          map: PlanarMap.t(),
          v1: %{PlanarMap.edge() => non_neg_integer()},
          v2: %{PlanarMap.edge() => non_neg_integer()},
          infos: %{non_neg_integer() => %{vertices: [PlanarMap.vertex()], state: face_state()}},
          order: [non_neg_integer()],
          next: non_neg_integer(),
          stack: [non_neg_integer()],
          failure: nil | reason(),
          result: colouring()
        }

  @doc """
  Discovers and two-colours the faces of `map`.

  Faces within each colour are in discovery order.
  """
  @spec extract_faces(PlanarMap.t()) :: {:ok, colouring()} | {:error, reason()}
  def extract_faces(map) do
    steps()
    |> Steps.run!(start(map))
    |> Steps.final()
    |> result()
  end

  @doc "As `extract_faces/1`, but returns the colouring and raises `ArgumentError` naming the reason."
  @spec extract_faces!(PlanarMap.t()) :: colouring()
  def extract_faces!(map), do: map |> extract_faces() |> unwrap!()

  @doc "The state `extract_faces/1` starts from."
  @spec start(PlanarMap.t()) :: state()
  def start(map) do
    %{
      map: map,
      v1: %{},
      v2: %{},
      infos: %{},
      order: [],
      next: 0,
      stack: [],
      failure: nil,
      result: %{black: [], white: []}
    }
  end

  @doc """
  The stages of `extract_faces/1` as a step sequence over a `t:state/0`:
  `:discover`, `:colour` and `:collect`.
  """
  @spec steps() :: [Steps.Step.t()]
  def steps do
    [
      step(
        :discover,
        "discover faces",
        "Walks every edge from each end, registering each face's edges and keeping every anti-clockwise one.",
        &discover/1
      ),
      step(
        :colour,
        "colour faces",
        "Colours every island of faces from its first discovered face, recording a conflict or an empty map.",
        &colour/1
      ),
      step(
        :collect,
        "collect colours",
        "Turns every kept face into its corner points and groups them by colour.",
        &collect/1
      )
    ]
  end

  @doc "The outcome of a finished `t:state/0`: the two colour lists, or the recorded failure."
  @spec result(state()) :: {:ok, colouring()} | {:error, reason()}
  def result(%{failure: nil, result: result}), do: {:ok, result}
  def result(%{failure: reason}), do: {:error, reason}

  # -- discovery --------------------------------------------------------------

  defp discover(%{failure: reason} = state) when not is_nil(reason), do: state

  defp discover(%{map: map} = state) do
    Enum.reduce(PlanarMap.edges(map), state, fn edge, state ->
      {v1, v2} = PlanarMap.endpoints!(map, edge)
      state |> discover_side(v1, edge, :v1) |> discover_side(v2, edge, :v2)
    end)
  end

  defp discover_side(%{v1: v1} = state, _from, edge, :v1) when is_map_key(v1, edge), do: state
  defp discover_side(%{v2: v2} = state, _from, edge, :v2) when is_map_key(v2, edge), do: state
  defp discover_side(state, from, edge, _side), do: handle_vertex(state, from, edge)

  defp handle_vertex(%{map: map} = state, from, edge) do
    case Walk.walk(map, from, edge) do
      nil -> state
      vertices -> register(state, vertices)
    end
  end

  # Every walked face is registered, including a rejected outer contour: the
  # colouring must reach it exactly as it does here.
  defp register(%{map: map} = state, vertices) do
    points = Enum.map(vertices, &PlanarMap.position!(map, &1))
    id = state.next

    state =
      %{
        state
        | infos: Map.put(state.infos, id, %{vertices: vertices, state: :undone}),
          next: id + 1
      }

    state
    |> register_edges(vertices, id)
    |> keep(id, Walk.clockwise?(points))
  end

  defp keep(state, _id, true), do: state
  defp keep(%{order: order} = state, id, false), do: %{state | order: order ++ [id]}

  defp register_edges(state, vertices, id) do
    count = length(vertices)

    vertices
    |> Enum.with_index()
    |> Enum.reduce(state, fn {from, index}, state ->
      to = Enum.at(vertices, rem(index + 1, count))
      state.map |> PlanarMap.neighbour!(from, to) |> register_direction(state, from, id)
    end)
  end

  defp register_direction(conn, %{map: map} = state, from, id) do
    {v1, _v2} = PlanarMap.endpoints!(map, conn)
    put_direction(state, conn, id, from == v1)
  end

  defp put_direction(%{v1: v1} = state, conn, id, true), do: %{state | v1: Map.put(v1, conn, id)}
  defp put_direction(%{v2: v2} = state, conn, id, false), do: %{state | v2: Map.put(v2, conn, id)}

  # -- colouring --------------------------------------------------------------

  defp colour(%{failure: reason} = state) when not is_nil(reason), do: state
  defp colour(%{order: []} = state), do: %{state | failure: :no_faces}

  defp colour(%{order: [seed | _]} = state) do
    state |> seed_component(seed) |> colour_remaining()
  end

  defp seed_component(state, id) do
    %{state | stack: [id]} |> put_state(id, :processing) |> drain()
  end

  defp colour_remaining(%{failure: reason} = state) when not is_nil(reason), do: state

  defp colour_remaining(%{order: order} = state) do
    Enum.reduce(order, state, &colour_if_undone/2)
  end

  defp colour_if_undone(_id, %{failure: reason} = state) when not is_nil(reason), do: state

  defp colour_if_undone(id, state) do
    case state.infos[id].state do
      :undone -> seed_component(state, id)
      _coloured -> state
    end
  end

  defp drain(%{failure: reason} = state) when not is_nil(reason), do: state
  defp drain(%{stack: []} = state), do: state

  defp drain(%{stack: [id | rest]} = state), do: drain(colour_one(%{state | stack: rest}, id))

  defp colour_one(state, id), do: state |> scan(state.infos[id].vertices) |> finish_scan(id)

  defp finish_scan({_col, %{failure: reason} = state}, _id) when not is_nil(reason), do: state
  defp finish_scan({col, state}, id), do: finish_colour(state, col, id)

  defp scan(state, vertices) do
    count = length(vertices)

    Enum.reduce_while(0..(count - 1), {nil, state}, fn index, acc ->
      from = Enum.at(vertices, index)
      to = Enum.at(vertices, rem(index + 1, count))
      step_twin(acc, twin(state, from, to))
    end)
  end

  defp step_twin({col, state}, nil), do: {:cont, {col, state}}

  defp step_twin({col, state}, other) do
    case state.infos[other].state do
      :undone -> {:cont, {col, push_processing(state, other)}}
      :processing -> {:cont, {col, state}}
      :black -> black_neighbour(state, col)
      :white -> white_neighbour(state, col)
    end
  end

  # `col` names our own required colour: a black neighbour forces white (1), a
  # white neighbour forces black (0). Seeing the opposite colour twice is the
  # conflict.
  defp black_neighbour(state, 0), do: {:halt, {0, %{state | failure: :filling_conflict}}}
  defp black_neighbour(state, _col), do: {:cont, {1, state}}

  defp white_neighbour(state, 1), do: {:halt, {1, %{state | failure: :filling_conflict}}}
  defp white_neighbour(state, _col), do: {:cont, {0, state}}

  defp finish_colour(state, 1, id), do: put_state(state, id, :white)
  defp finish_colour(state, _col, id), do: put_state(state, id, :black)

  defp push_processing(state, id), do: put_state(%{state | stack: [id | state.stack]}, id, :processing)

  defp put_state(state, id, new_state) do
    %{state | infos: Map.update!(state.infos, id, &%{&1 | state: new_state})}
  end

  defp twin(%{map: map} = state, from, to), do: map |> PlanarMap.neighbour!(from, to) |> lookup_twin(state, from)

  defp lookup_twin(nil, _state, _from), do: nil

  defp lookup_twin(conn, %{map: map} = state, from) do
    {v1, _v2} = PlanarMap.endpoints!(map, conn)
    direction_table(state, conn, from == v1)
  end

  defp direction_table(%{v2: v2}, conn, true), do: Map.get(v2, conn)
  defp direction_table(%{v1: v1}, conn, false), do: Map.get(v1, conn)

  # -- collection -------------------------------------------------------------

  defp collect(%{failure: reason} = state) when not is_nil(reason), do: state

  defp collect(%{map: map, order: order, infos: infos} = state) do
    result =
      Enum.reduce(order, %{black: [], white: []}, fn id, acc ->
        points = Enum.map(infos[id].vertices, &PlanarMap.position!(map, &1))
        add_colour(acc, infos[id].state, points)
      end)

    %{state | result: result}
  end

  defp add_colour(acc, :white, points), do: %{acc | white: acc.white ++ [points]}
  defp add_colour(acc, :black, points), do: %{acc | black: acc.black ++ [points]}
  defp add_colour(acc, _undecided, _points), do: acc

  defp unwrap!({:ok, colouring}), do: colouring
  defp unwrap!({:error, reason}), do: raise(ArgumentError, "faces: #{reason}")
end

defmodule Girihelix.TapratsHarness do
  @moduledoc """
  The Elixir half of the Taprats reference harness: it parses operation
  scripts and dumps, and compares two dumps.

  The harness, its scenarios (`reference/oracle/scenarios/`) and its fixtures
  (`reference/oracle/fixtures/`) are local-only and git-ignored. Golden tests
  that use them are tagged `:taprats` and skipped where the fixtures are
  absent. The script and dump formats are specified in the planar map design
  and plan under `docs/`.

  Malformed script or dump input raises `ArgumentError` naming the offending
  line. That is deliberate: the input is a local test file, so a malformed
  line is a bug in the file, not data a caller supplied, and there is nobody
  to return an error tuple to.
  """

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.Engine.PlanarMap

  @tolerance 1.0e-12
  @fixtures_dir "reference/oracle/fixtures"
  @scenarios_dir "reference/oracle/scenarios"

  @type verify :: true | false | :npe | :unchecked
  @type dump :: %{
          vertices: [{float(), float()}],
          edges: [{non_neg_integer(), non_neg_integer()}],
          rings: [[non_neg_integer()]],
          verify: verify()
        }
  @type op :: tuple()

  @doc "The directory holding the Taprats fixtures."
  @spec fixtures_dir() :: String.t()
  def fixtures_dir, do: @fixtures_dir

  @doc "True when the local-only fixtures are present."
  @spec available?() :: boolean()
  def available?, do: File.dir?(@fixtures_dir)

  @doc "Reads the scenario and the fixture called `name`."
  @spec load(String.t()) :: {[op()], dump()}
  def load(name) do
    ops = @scenarios_dir |> Path.join(name <> ".ops") |> File.read!() |> parse_script()
    dump = @fixtures_dir |> Path.join(name <> ".dump") |> File.read!() |> parse_dump()
    {ops, dump}
  end

  # -- running a script -------------------------------------------------------

  @doc """
  Runs a parsed script against `Girihelix.Engine.PlanarMap` and returns the dump
  of the map named by the final `dump` op. Per-map vertex indices refer to the
  results of that map's `vertex` ops, in order. An unknown op raises
  `ArgumentError`.
  """
  @spec run_script([op()]) :: dump()
  def run_script(ops), do: run(ops, %{})

  defp run([{:dump, name}], state), do: state |> state_of(name) |> Map.fetch!(:map) |> dump()
  defp run([op | rest], state), do: run(rest, step(op, state))

  defp step({:vertex, name, x, y}, state) do
    %{map: map, handles: handles} = state_of(state, name)
    {map, vertex} = PlanarMap.insert_vertex(map, Point.new(x, y))
    Map.put(state, name, %{map: map, handles: handles ++ [vertex]})
  end

  defp step({:edge, name, i, j}, state) do
    %{map: map, handles: handles} = state_of(state, name)
    map = PlanarMap.insert_edge!(map, Enum.fetch!(handles, i), Enum.fetch!(handles, j))
    Map.put(state, name, %{map: map, handles: handles})
  end

  defp step({:remove, name, i}, state) do
    %{map: map, handles: handles} = state_of(state, name)
    map = PlanarMap.remove_vertex!(map, Enum.fetch!(handles, i))
    Map.put(state, name, %{map: map, handles: handles})
  end

  defp step({:replicate, name, other, transforms}, state) do
    %{map: unit} = state_of(state, other)
    update_map(state, name, &PlanarMap.replicate(&1, unit, transforms))
  end

  defp step({:weld, name, other}, state) do
    %{map: other_map} = state_of(state, other)
    update_map(state, name, &(&1 |> PlanarMap.weld(other_map) |> elem(0)))
  end

  defp step({:transform, name, transform}, state), do: update_map(state, name, &PlanarMap.transform(&1, transform))

  defp step({:scale, name, r}, state), do: update_map(state, name, &PlanarMap.scale(&1, r))

  defp step({:translate, name, x, y}, state), do: update_map(state, name, &PlanarMap.translate(&1, x, y))

  defp step(op, _state), do: raise(ArgumentError, "script op not yet supported: #{inspect(op)}")

  defp update_map(state, name, fun) do
    entry = state_of(state, name)
    Map.put(state, name, %{entry | map: fun.(entry.map)})
  end

  defp state_of(state, name), do: Map.get(state, name, %{map: PlanarMap.new(), handles: []})

  @doc """
  The dump of a map: vertices and edges in the map's order, edges as vertex-order
  indices, rings as edge-order indices from each ring's head. `verify` is
  whether `PlanarMap.verify/1` finds no problem.
  """
  @spec dump(PlanarMap.t()) :: dump()
  def dump(map) do
    vertices = PlanarMap.vertices(map)
    vertex_index = index_of(vertices)
    edge_index = index_of(PlanarMap.edges(map))

    %{
      vertices: Enum.map(vertices, &(map |> PlanarMap.position!(&1) |> then(fn p -> {p.x, p.y} end))),
      edges:
        Enum.map(PlanarMap.edges(map), fn edge ->
          {v1, v2} = PlanarMap.endpoints!(map, edge)
          {Map.fetch!(vertex_index, v1), Map.fetch!(vertex_index, v2)}
        end),
      rings:
        Enum.map(vertices, fn v ->
          map |> PlanarMap.ring!(v) |> Enum.map(&Map.fetch!(edge_index, &1))
        end),
      verify: PlanarMap.verify(map) == :ok
    }
  end

  defp index_of(handles), do: handles |> Enum.with_index() |> Map.new()

  # -- script parsing ---------------------------------------------------------

  @doc "Parses an operation script into one tuple per operation."
  @spec parse_script(String.t()) :: [op()]
  def parse_script(text) do
    text
    |> String.split("\n")
    |> Enum.map(&strip_comment/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_op/1)
  end

  # Like the Java driver: everything from the first `#` on is a comment.
  defp strip_comment(line), do: line |> String.split("#", parts: 2) |> hd() |> String.trim()

  defp parse_op(line), do: line |> String.split() |> op(line)

  defp op(["dump", map], _line), do: {:dump, map}
  defp op([map, "vertex", x, y], line), do: {:vertex, map, number(x, line), number(y, line)}
  defp op([map, "edge", i, j], line), do: {:edge, map, index(i, line), index(j, line)}
  defp op([map, "remove", i], line), do: {:remove, map, index(i, line)}
  defp op([map, "transform" | spec], line), do: {:transform, map, transform(spec, line)}
  defp op([map, "scale", r], line), do: {:scale, map, number(r, line)}
  defp op([map, "translate", x, y], line), do: {:translate, map, number(x, line), number(y, line)}
  defp op([map, "weld", other], _line), do: {:weld, map, other}
  defp op([map, "replicate", other], _line), do: {:replicate, map, other, []}

  defp op([map, "replicate", other | spec], line) do
    transforms =
      spec
      |> Enum.join(" ")
      |> String.split(";")
      |> Enum.map(&(&1 |> String.split() |> transform(line)))

    {:replicate, map, other, transforms}
  end

  defp op(_tokens, line), do: bad_line("script", line)

  defp transform(["m", a, b, c, d, e, f], line) do
    [a, b, c, d, e, f]
    |> Enum.map(&number(&1, line))
    |> then(fn [a, b, c, d, e, f] -> Transform.new(a, b, c, d, e, f) end)
  end

  defp transform(["rot", r], line), do: r |> number(line) |> Transform.rotate()
  defp transform(["tr", x, y], line), do: Transform.translate(number(x, line), number(y, line))
  defp transform(["sc", r], line), do: r |> number(line) |> Transform.scale()
  defp transform(_tokens, line), do: bad_line("script", line)

  # -- dump parsing -----------------------------------------------------------

  @doc "Parses a dump, in Java's float spelling, into a `t:dump/0`."
  @spec parse_dump(String.t()) :: dump()
  def parse_dump(text) do
    items =
      text
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&dump_item/1)

    %{
      vertices: for({:v, point} <- items, do: point),
      edges: for({:e, pair} <- items, do: pair),
      rings: for({:r, ring} <- items, do: ring),
      verify:
        items
        |> Enum.find_value(fn
          {:verify, word} -> word
          _ -> nil
        end)
        |> verify_word()
    }
  end

  defp dump_item(line), do: line |> String.split() |> dump_item(line)

  defp dump_item(["vertices", _n], _line), do: :count
  defp dump_item(["edges", _m], _line), do: :count
  defp dump_item(["rings"], _line), do: :count
  defp dump_item(["v", x, y], line), do: {:v, {number(x, line), number(y, line)}}
  defp dump_item(["e", i, j], line), do: {:e, {index(i, line), index(j, line)}}
  defp dump_item(["r", _i | keys], line), do: {:r, Enum.map(keys, &index(&1, line))}
  defp dump_item(["verify", word], _line), do: {:verify, word}
  defp dump_item(_tokens, line), do: bad_line("dump", line)

  defp verify_word("true"), do: true
  defp verify_word("false"), do: false
  defp verify_word("npe"), do: :npe
  defp verify_word(other), do: bad_line("dump verify word", inspect(other))

  # -- comparison -------------------------------------------------------------

  @doc """
  Compares two dumps. Counts, edges and rings are exact, and coordinates are
  within `1.0e-12`. The `verify` word is skipped when `actual.verify` is
  `:unchecked`, or when `expected.verify` is not `true`.
  """
  @spec compare(dump(), dump()) :: :ok | {:error, [String.t()]}
  def compare(expected, actual) do
    errors =
      vertex_errors(expected.vertices, actual.vertices) ++
        exact_errors("edges", expected.edges, actual.edges) ++
        exact_errors("rings", expected.rings, actual.rings) ++
        verify_errors(expected.verify, actual.verify)

    result(errors)
  end

  defp result([]), do: :ok
  defp result(errors), do: {:error, errors}

  defp vertex_errors(expected, actual) when length(expected) != length(actual),
    do: ["vertex count: expected #{length(expected)}, got #{length(actual)}"]

  defp vertex_errors(expected, actual) do
    expected
    |> Enum.zip(actual)
    |> Enum.with_index()
    |> Enum.flat_map(fn {{e, a}, i} -> point_errors(i, e, a) end)
  end

  defp point_errors(_i, {ex, ey}, {ax, ay}) when abs(ex - ax) < @tolerance and abs(ey - ay) < @tolerance, do: []

  defp point_errors(i, expected, actual), do: ["vertex #{i}: expected #{inspect(expected)}, got #{inspect(actual)}"]

  defp exact_errors(_label, same, same), do: []

  defp exact_errors(label, expected, actual), do: ["#{label}: expected #{inspect(expected)}, got #{inspect(actual)}"]

  defp verify_errors(_expected, :unchecked), do: []
  defp verify_errors(true, true), do: []
  defp verify_errors(true, actual), do: ["verify: expected true, got #{inspect(actual)}"]
  defp verify_errors(_expected, _actual), do: []

  # -- numbers ----------------------------------------------------------------

  defp number(token, line), do: token |> Float.parse() |> number_result(line)

  defp number_result({value, ""}, _line), do: value
  defp number_result(_other, line), do: bad_line("number in", line)

  defp index(token, line), do: token |> Integer.parse() |> index_result(line)

  defp index_result({value, ""}, _line) when value >= 0, do: value
  defp index_result(_other, line), do: bad_line("index in", line)

  defp bad_line(what, line), do: raise(ArgumentError, "malformed #{what} line: #{line}")
end

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

  alias Girihelix.Engine.Faces
  alias Girihelix.Engine.Figures.Figure
  alias Girihelix.Engine.Figures.Star
  alias Girihelix.Engine.FillRegion
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.Engine.PlanarMap

  @tolerance 1.0e-12
  @fixtures_dir "reference/oracle/fixtures"
  @scenarios_dir "reference/oracle/scenarios"

  @type verify :: true | false | :npe | :unchecked
  @type corner :: {float(), float()}
  @type map_dump :: %{
          vertices: [corner()],
          edges: [{non_neg_integer(), non_neg_integer()}],
          rings: [[non_neg_integer()]],
          verify: verify()
        }
  @type faces_dump :: %{
          faces:
            {:ok, %{black: [[corner()]], white: [[corner()]]}}
            | {:error, :filling | :empty}
        }
  @type cells_dump :: %{cells: {:ok, [{integer(), integer()}]} | {:error, :too_many}}
  @type figure_expr ::
          {:star, integer(), float(), integer()}
          | {:rosette, integer(), float(), integer()}
          | {:scale, figure_expr(), float()}
          | {:connect, figure_expr()}
  @type figure_dump :: %{figure: {:ok, map_dump()} | {:error, :null}}
  @type dump :: map_dump() | faces_dump() | cells_dump() | figure_dump()
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

  defp run([{:faces, name}], state) do
    state |> state_of(name) |> Map.fetch!(:map) |> Faces.extract_faces() |> faces_dump()
  end

  defp run([{:fill, region, t1, t2}], _state), do: region |> FillRegion.fill(t1, t2) |> fill_dump()

  defp run([{:figure, kind, expr}], _state), do: build_figure({:figure, kind, expr})

  defp run([op | rest], state), do: run(rest, step(op, state))

  @doc """
  Builds and dumps the figure named by a `figure` operation.

  The map body is `dump/1`'s, so the figure and map dumps cannot drift. Any
  exception raised by the port maps to `{:error, :null}`, which is the
  source's `NullPointerException` outcome for those parameters. An expression
  this task cannot build yet raises `ArgumentError`.
  """
  @spec build_figure({:figure, :map | :unit, figure_expr()}) :: figure_dump()
  def build_figure({:figure, kind, {:star, n, d, s}}) do
    %{figure: {:ok, kind |> build_star(n, d, s) |> dump()}}
  rescue
    _exception -> %{figure: {:error, :null}}
  end

  def build_figure({:figure, _kind, expr}) do
    raise ArgumentError, "figure not yet buildable: #{inspect(expr)}"
  end

  defp build_star(:map, n, d, s), do: n |> Star.new!(d, s) |> Figure.map()
  defp build_star(:unit, n, d, s), do: n |> Star.new!(d, s) |> Figure.unit()

  defp faces_dump({:ok, colouring}) do
    %{faces: {:ok, %{black: face_corners(colouring.black), white: face_corners(colouring.white)}}}
  end

  defp faces_dump({:error, :filling_conflict}), do: %{faces: {:error, :filling}}
  defp faces_dump({:error, :no_faces}), do: %{faces: {:error, :empty}}

  defp face_corners(faces), do: Enum.map(faces, fn face -> Enum.map(face, fn %Point{x: x, y: y} -> {x, y} end) end)

  defp fill_dump({:ok, cells}), do: %{cells: {:ok, cells}}
  defp fill_dump({:error, :too_many_units}), do: %{cells: {:error, :too_many}}

  defp fill_dump({:error, :degenerate_basis}), do: raise(ArgumentError, "a golden fill scenario has a degenerate basis")

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
    update_map(state, name, &PlanarMap.replicate!(&1, unit, transforms))
  end

  defp step({:weld, name, other}, state) do
    %{map: other_map} = state_of(state, other)
    update_map(state, name, &(&1 |> PlanarMap.weld!(other_map) |> elem(0)))
  end

  defp step({:transform, name, transform}, state), do: update_map(state, name, &PlanarMap.transform!(&1, transform))

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
  @spec dump(PlanarMap.t()) :: map_dump()
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
  defp op([map, "faces"], _line), do: {:faces, map}

  defp op(["fill" | spec], line) do
    case spec |> Enum.join(" ") |> String.split(";") do
      [region, t1, t2] -> {:fill, region_points(region, line), point(t1, line), point(t2, line)}
      _other -> bad_line("script", line)
    end
  end

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

  defp op(["figure", "map", expr | rest], line), do: {:figure, :map, figure_expr!([expr | rest], line)}

  defp op(["figure", "unit", expr | rest], line), do: {:figure, :unit, figure_expr!([expr | rest], line)}

  defp op(_tokens, line), do: bad_line("script", line)

  # `figure_expr!/2` parses one expression and rejects leftover tokens.
  defp figure_expr!([expr | rest], line) do
    case figure_expr([expr | rest], line) do
      {expression, []} -> expression
      {_expression, _rest} -> bad_line("script", line)
    end
  end

  # Postfix, so `scale <expr> <s>` is unambiguous without parentheses.
  defp figure_expr(["star", n, d, s | rest], line) do
    {{:star, integer(n, line), number(d, line), integer(s, line)}, rest}
  end

  defp figure_expr(["rosette", n, q, s | rest], line) do
    {{:rosette, integer(n, line), number(q, line), integer(s, line)}, rest}
  end

  defp figure_expr(["scale" | rest], line) do
    {child, rest} = figure_expr(rest, line)

    case rest do
      [factor | rest] -> {{:scale, child, number(factor, line)}, rest}
      [] -> bad_line("script", line)
    end
  end

  defp figure_expr(["connect" | rest], line) do
    {child, rest} = figure_expr(rest, line)
    {{:connect, child}, rest}
  end

  defp figure_expr(_tokens, line), do: bad_line("script", line)

  defp transform(["m", a, b, c, d, e, f], line) do
    [a, b, c, d, e, f]
    |> Enum.map(&number(&1, line))
    |> then(fn [a, b, c, d, e, f] -> Transform.new(a, b, c, d, e, f) end)
  end

  defp transform(["rot", r], line), do: r |> number(line) |> Transform.rotate()
  defp transform(["tr", x, y], line), do: Transform.translate(number(x, line), number(y, line))
  defp transform(["sc", r], line), do: r |> number(line) |> Transform.scale()
  defp transform(_tokens, line), do: bad_line("script", line)

  defp region_points(text, line) do
    case numbers(text, line) do
      [a, b, c, d, e, f, g, h] ->
        [
          Point.new(a, b),
          Point.new(c, d),
          Point.new(e, f),
          Point.new(g, h)
        ]

      _other ->
        bad_line("script", line)
    end
  end

  defp point(text, line) do
    case numbers(text, line) do
      [x, y] -> Point.new(x, y)
      _other -> bad_line("script", line)
    end
  end

  defp numbers(text, line), do: text |> String.split() |> Enum.map(&number(&1, line))

  # -- dump parsing -----------------------------------------------------------

  @doc "Parses a dump, in Java's float spelling, into a `t:dump/0`."
  @spec parse_dump(String.t()) :: dump()
  def parse_dump(text) do
    lines =
      text
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case lines do
      ["faces ok" | rest] -> %{faces: {:ok, parse_faces(rest)}}
      ["faces error " <> word] -> %{faces: {:error, face_error(word)}}
      ["fill ok" | rest] -> %{cells: {:ok, Enum.map(rest, &cell/1)}}
      ["fill error " <> word] -> %{cells: {:error, fill_error(word)}}
      ["figure ok" | rest] -> %{figure: {:ok, parse_map_dump(rest)}}
      ["figure unit ok" | rest] -> %{figure: {:ok, parse_map_dump(rest)}}
      ["figure error null"] -> %{figure: {:error, :null}}
      _other -> parse_map_dump(lines)
    end
  end

  defp parse_map_dump(lines) do
    items = Enum.map(lines, &dump_item/1)

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

  defp parse_faces(lines) do
    Enum.reduce(lines, %{black: [], white: []}, fn line, acc -> add_face(acc, line) end)
  end

  defp add_face(acc, line) do
    case String.split(line) do
      ["black" | coords] -> %{acc | black: acc.black ++ [face(coords, line)]}
      ["white" | coords] -> %{acc | white: acc.white ++ [face(coords, line)]}
      _other -> bad_line("face", line)
    end
  end

  defp face(coords, line) do
    values = Enum.map(coords, &number(&1, line))
    values |> Enum.chunk_every(2) |> build_face(values, line)
  end

  # An empty face, or one with an odd coordinate count, is malformed.
  defp build_face(pairs, values, _line) when length(pairs) * 2 == length(values),
    do: Enum.map(pairs, fn [x, y] -> {x, y} end)

  defp build_face(_pairs, _values, line), do: bad_line("face coordinates in", line)

  defp cell(line) do
    case String.split(line) do
      ["cell", t1, t2] -> {integer(t1, line), integer(t2, line)}
      _other -> bad_line("cell in", line)
    end
  end

  defp face_error("filling"), do: :filling
  defp face_error("empty"), do: :empty
  defp face_error(other), do: bad_line("faces error word", inspect(other))

  defp fill_error("too_many"), do: :too_many
  defp fill_error(other), do: bad_line("fill error word", inspect(other))

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
  def compare(%{faces: expected}, %{faces: actual}), do: expected |> faces_errors(actual) |> result()

  def compare(%{cells: expected}, %{cells: actual}), do: expected |> cells_errors(actual) |> result()

  def compare(%{figure: expected}, %{figure: actual}), do: expected |> figure_errors(actual) |> result()

  def compare(%{faces: _expected}, actual), do: {:error, ["dump shape: expected faces, got #{inspect(Map.keys(actual))}"]}

  def compare(%{cells: _expected}, actual), do: {:error, ["dump shape: expected cells, got #{inspect(Map.keys(actual))}"]}

  def compare(%{figure: _expected}, actual),
    do: {:error, ["dump shape: expected figure, got #{inspect(Map.keys(actual))}"]}

  def compare(expected, actual), do: expected |> map_errors(actual) |> result()

  defp map_errors(expected, actual) do
    vertex_errors(expected.vertices, actual.vertices) ++
      exact_errors("edges", expected.edges, actual.edges) ++
      exact_errors("rings", expected.rings, actual.rings) ++
      verify_errors(expected.verify, actual.verify)
  end

  defp figure_errors({:error, :null}, {:error, :null}), do: []
  defp figure_errors({:ok, expected}, {:ok, actual}), do: map_errors(expected, actual)

  defp figure_errors(expected, actual), do: ["figure: expected #{inspect(expected)}, got #{inspect(actual)}"]

  defp faces_errors({:error, reason}, {:error, reason}), do: []

  defp faces_errors({:ok, expected}, {:ok, actual}) do
    face_list_errors("black", expected.black, actual.black) ++
      face_list_errors("white", expected.white, actual.white)
  end

  defp faces_errors(expected, actual), do: ["faces: expected #{inspect(expected)}, got #{inspect(actual)}"]

  defp face_list_errors(label, expected, actual) when length(expected) != length(actual),
    do: ["#{label} face count: expected #{length(expected)}, got #{length(actual)}"]

  defp face_list_errors(label, expected, actual) do
    expected
    |> Enum.zip(actual)
    |> Enum.with_index()
    |> Enum.flat_map(fn {{e, a}, i} -> face_errors(label, i, e, a) end)
  end

  defp face_errors(label, index, expected, actual) when length(expected) != length(actual),
    do: ["#{label} face #{index} corner count: expected #{length(expected)}, got #{length(actual)}"]

  defp face_errors(label, index, expected, actual) do
    expected
    |> Enum.zip(actual)
    |> Enum.with_index()
    |> Enum.flat_map(fn {{e, a}, c} -> corner_errors(label, index, c, e, a) end)
  end

  defp corner_errors(_label, _face, _corner, {ex, ey}, {ax, ay})
       when abs(ex - ax) < @tolerance and abs(ey - ay) < @tolerance, do: []

  defp corner_errors(label, face, corner, expected, actual),
    do: ["#{label} face #{face} corner #{corner}: expected #{inspect(expected)}, got #{inspect(actual)}"]

  defp cells_errors({:error, reason}, {:error, reason}), do: []
  defp cells_errors({:ok, expected}, {:ok, actual}), do: exact_errors("cells", expected, actual)

  defp cells_errors(expected, actual), do: ["cells: expected #{inspect(expected)}, got #{inspect(actual)}"]

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

  defp integer(token, line) do
    case Integer.parse(token) do
      {value, ""} -> value
      _other -> bad_line("integer in", line)
    end
  end

  defp index(token, line), do: token |> Integer.parse() |> index_result(line)

  defp index_result({value, ""}, _line) when value >= 0, do: value
  defp index_result(_other, line), do: bad_line("index in", line)

  defp bad_line(what, line), do: raise(ArgumentError, "malformed #{what} line: #{line}")
end

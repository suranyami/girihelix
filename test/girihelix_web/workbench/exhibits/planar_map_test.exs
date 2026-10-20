defmodule GirihelixWeb.Workbench.Exhibits.PlanarMapTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Viewport
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibits.PlanarMap, as: Exhibit
  alias GirihelixWeb.Workbench.Param

  test "the default weld scenario shows both maps and its crossing count" do
    values = Param.values(Exhibit.params(), :default)
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:ok, _} = Map.fetch(List.last(frames).state, :receiver)

    assert {:both, ops, rows} = Exhibit.draw(hd(frames), values)
    assert ops != []
    assert {"receiver vertices", "4"} in rows
  end

  test "the replicate scenario reaches six spokes" do
    values = %{Param.values(Exhibit.params(), :default) | scenario: :replicate_ladder}
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, _ops, rows} = Exhibit.draw(List.last(frames), values)
    assert {"receiver edges", "12"} in rows
  end

  test "identifies itself, declares a scenario and pins its viewport" do
    assert Exhibit.slug() == "planar-map"
    assert Exhibit.category() == :geometry
    assert Exhibit.title() != ""
    assert Exhibit.summary() != ""

    assert [scenario] = Exhibit.params()
    assert {scenario.name, scenario.type, scenario.default} == {:scenario, :enum, :weld_squares}
    assert scenario.options == [:weld_squares, :replicate_ladder]

    assert Exhibit.viewport(Param.values(Exhibit.params(), :default)) ==
             Viewport.fit({-2.0, -2.0, 2.0, 2.0}, padding: 0.0)
  end

  test "the weld scenario is two unit squares offset by half a side" do
    {receiver, other} = Exhibit.scenario(:weld_squares)

    assert PlanarMap.num_vertices(receiver) == 4
    assert PlanarMap.num_edges(receiver) == 4
    assert PlanarMap.num_vertices(other) == 4
    assert PlanarMap.num_edges(other) == 4

    assert positions(receiver) ==
             MapSet.new([
               Point.new(0.0, 0.0),
               Point.new(1.0, 0.0),
               Point.new(1.0, 1.0),
               Point.new(0.0, 1.0)
             ])

    assert positions(other) ==
             MapSet.new([
               Point.new(0.5, 0.5),
               Point.new(1.5, 0.5),
               Point.new(1.5, 1.5),
               Point.new(0.5, 1.5)
             ])
  end

  test "the replicate scenario is an empty receiver and a three-vertex spoke" do
    {receiver, unit} = Exhibit.scenario(:replicate_ladder)

    assert PlanarMap.num_vertices(receiver) == 0
    assert PlanarMap.num_edges(receiver) == 0
    assert PlanarMap.num_vertices(unit) == 3
    assert PlanarMap.num_edges(unit) == 2

    assert positions(unit) ==
             MapSet.new([Point.new(0.0, 0.0), Point.new(1.0, 0.0), Point.new(1.5, 0.3)])
  end

  test "the weld scenario starts from both maps and runs the weld steps" do
    values = Param.values(Exhibit.params(), :default)
    {receiver, other} = Exhibit.scenario(:weld_squares)

    assert Exhibit.initial(values) == PlanarMap.weld_start(receiver, other)

    assert Enum.map(Exhibit.steps(values), & &1.id) ==
             [:find_crossings, :force_vertices, :unify_vertices, :copy_edges]
  end

  test "the replicate scenario starts from an empty receiver and copies six times" do
    values = %{Param.values(Exhibit.params(), :default) | scenario: :replicate_ladder}
    {receiver, _unit} = Exhibit.scenario(:replicate_ladder)

    assert Exhibit.initial(values) == PlanarMap.replicate_start(receiver)

    assert Enum.map(Exhibit.steps(values), & &1.id) ==
             [:copy, :copy, :copy, :copy, :copy, :copy, :sort_edges]
  end

  test "weld frame zero draws both squares and no crossings yet" do
    values = Param.values(Exhibit.params(), :default)
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))

    assert {:both, ops, rows} = Exhibit.draw(hd(frames), values)

    assert Enum.count(ops, &match?({:line, _from, _to, []}, &1)) == 4
    assert Enum.count(ops, &match?({:point, _at, _radius, []}, &1)) == 4
    assert Enum.count(ops, &match?({:guide, _from, _to, []}, &1)) == 4
    assert Enum.all?(ops, &(elem(&1, 0) in [:line, :point, :guide]))

    assert rows == [
             {"receiver vertices", "4"},
             {"receiver edges", "4"},
             {"crossings", "0"},
             {"verify", "ok"}
           ]
  end

  test "the welded frame draws the crossings and reports the final counts" do
    values = Param.values(Exhibit.params(), :default)
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))

    assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

    assert Enum.count(ops, &match?({:point, _at, _radius, []}, &1)) == 12
    assert Enum.any?(ops, &match?({:point, {1.0, 0.5}, _radius, []}, &1))
    assert Enum.any?(ops, &match?({:point, {0.5, 1.0}, _radius, []}, &1))

    assert rows == [
             {"receiver vertices", "10"},
             {"receiver edges", "12"},
             {"crossings", "2"},
             {"verify", "ok"}
           ]
  end

  test "replicate frame zero draws the unit that is about to be copied" do
    values = %{Param.values(Exhibit.params(), :default) | scenario: :replicate_ladder}
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))

    assert {:both, ops, rows} = Exhibit.draw(hd(frames), values)

    assert ops == [
             {:guide, {0.0, 0.0}, {1.0, 0.0}, []},
             {:guide, {1.0, 0.0}, {1.5, 0.3}, []}
           ]

    assert rows == [
             {"receiver vertices", "0"},
             {"receiver edges", "0"},
             {"crossings", "0"},
             {"verify", "ok"}
           ]
  end

  test "the finished replicate draws twelve edges and thirteen vertices" do
    values = %{Param.values(Exhibit.params(), :default) | scenario: :replicate_ladder}
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))

    assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

    assert Enum.count(ops, &match?({:line, _from, _to, []}, &1)) == 12
    assert Enum.count(ops, &match?({:point, _at, _radius, []}, &1)) == 13
    assert Enum.count(ops, &match?({:guide, _from, _to, []}, &1)) == 2

    assert rows == [
             {"receiver vertices", "13"},
             {"receiver edges", "12"},
             {"crossings", "0"},
             {"verify", "ok"}
           ]
  end

  test "reproduces the scenario with a fully qualified pasteable snippet" do
    values = Param.values(Exhibit.params(), :default)

    assert Exhibit.reproduce(values) ==
             "GirihelixWeb.Workbench.Exhibits.PlanarMap.scenario(:weld_squares)"

    assert Exhibit.reproduce(%{values | scenario: :replicate_ladder}) ==
             "GirihelixWeb.Workbench.Exhibits.PlanarMap.scenario(:replicate_ladder)"
  end

  defp positions(map) do
    map
    |> PlanarMap.vertices()
    |> MapSet.new(&PlanarMap.position!(map, &1))
  end
end

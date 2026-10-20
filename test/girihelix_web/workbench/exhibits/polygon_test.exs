defmodule GirihelixWeb.Workbench.Exhibits.PolygonTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Polygon
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibits.Polygon, as: Exhibit
  alias GirihelixWeb.Workbench.Param

  test "the default unit square reports its measures" do
    values = Param.values(Exhibit.params(), :default)
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

    assert Enum.any?(ops, fn
             {:polygon, points, :fill, _opts} ->
               points == [{0.0, 0.0}, {1.0, 0.0}, {1.0, 1.0}, {0.0, 1.0}]

             _op ->
               false
           end)

    assert {"vertices", "4"} in rows
    assert {"area", "1.0"} in rows
    assert {"arc length", "4.0"} in rows
    assert {"contains probe", "true"} in rows
  end

  test "identifies itself and declares a shape and a probe" do
    assert Exhibit.slug() == "polygon"
    assert Exhibit.category() == :geometry
    assert Exhibit.title() != ""
    assert Exhibit.summary() != ""

    assert [shape, probe_x, probe_y] = Exhibit.params()

    assert {shape.name, shape.type, shape.default} == {:shape, :enum, :square}
    assert shape.options == [:square, :triangle, :star]

    for {param, default} <- [{probe_x, 0.5}, {probe_y, 0.5}] do
      assert {param.name, param.type, param.default} == {param.name, :float, default}
      assert param.range == -2..2
      assert param.step == 0.1
    end
  end

  test "starts from the parameters and the build step builds the polygon and probe" do
    values = Param.values(Exhibit.params(), :default)

    assert Exhibit.initial(values) == values
    assert [%Steps.Step{id: :build} = step] = Exhibit.steps(values)

    assert %{polygon: polygon, probe: probe} = step.run.(values)

    assert Polygon.points(polygon) == [
             Point.new(0.0, 0.0),
             Point.new(1.0, 0.0),
             Point.new(1.0, 1.0),
             Point.new(0.0, 1.0)
           ]

    assert probe == Point.new(0.5, 0.5)
  end

  test "draws the filled polygon, its vertices and a larger probe marker" do
    values = Param.values(Exhibit.params(), :default)
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

    assert [
             {:polygon, points, :fill, opts},
             {:point, a, vertex_radius, []},
             {:point, b, vertex_radius, []},
             {:point, c, vertex_radius, []},
             {:point, d, vertex_radius, []},
             {:point, probe, probe_radius, []}
           ] = ops

    assert opts == [fill: "currentColor", opacity: 0.15]
    assert points == [{0.0, 0.0}, {1.0, 0.0}, {1.0, 1.0}, {0.0, 1.0}]
    assert [a, b, c, d] == points
    assert probe == {0.5, 0.5}
    assert probe_radius > vertex_radius

    assert rows == [
             {"vertices", "4"},
             {"area", "1.0"},
             {"arc length", "4.0"},
             {"contains probe", "true"}
           ]
  end

  test "frame zero draws the same polygon before the build step runs" do
    values = Param.values(Exhibit.params(), :default)
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))

    assert Exhibit.draw(hd(frames), values) == Exhibit.draw(List.last(frames), values)
  end

  test "the triangle reports three vertices, half the area and its closed path" do
    values = Param.decode(Exhibit.params(), %{"shape" => "triangle"})
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

    assert {:polygon, points, :fill, _opts} = hd(ops)
    assert points == [{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}]

    assert {"vertices", "3"} in rows
    assert {"area", "0.5"} in rows

    {"arc length", arc_length} = List.keyfind(rows, "arc length", 0)
    assert_in_delta String.to_float(arc_length), 2.0 + :math.sqrt(2.0), 1.0e-12
  end

  test "the star is ten vertices alternating outer and inner about (0.5, 0.5)" do
    values = Param.decode(Exhibit.params(), %{"shape" => "star"})
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

    assert {:polygon, points, :fill, _opts} = hd(ops)
    assert length(points) == 10
    assert hd(points) == {1.0, 0.5}

    radii = Enum.map(points, fn {x, y} -> :math.sqrt((x - 0.5) ** 2 + (y - 0.5) ** 2) end)

    for radius <- Enum.take_every(radii, 2), do: assert_in_delta(radius, 0.5, 1.0e-9)

    for radius <- radii |> Enum.drop(1) |> Enum.take_every(2),
        do: assert_in_delta(radius, 0.2, 1.0e-9)

    assert {"vertices", "10"} in rows

    {"area", area} = List.keyfind(rows, "area", 0)
    assert_in_delta String.to_float(area), 0.5 * :math.sin(:math.pi() / 5), 1.0e-12
  end

  test "a probe outside the square reports false and marks the probe's position" do
    values = Param.decode(Exhibit.params(), %{"probe_x" => "2.0", "probe_y" => "2.0"})
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

    assert {"contains probe", "false"} in rows
    assert {:point, probe, probe_radius, []} = List.last(ops)
    assert probe == {2.0, 2.0}
    assert probe_radius > 0
  end

  test "reproduces the polygon with a fully qualified pasteable snippet" do
    values = Param.values(Exhibit.params(), :default)

    assert Exhibit.reproduce(values) ==
             "Girihelix.Engine.Geometry.Polygon.new!([" <>
               "Girihelix.Engine.Geometry.Point.new(0.0, 0.0), " <>
               "Girihelix.Engine.Geometry.Point.new(1.0, 0.0), " <>
               "Girihelix.Engine.Geometry.Point.new(1.0, 1.0), " <>
               "Girihelix.Engine.Geometry.Point.new(0.0, 1.0)])"
  end
end

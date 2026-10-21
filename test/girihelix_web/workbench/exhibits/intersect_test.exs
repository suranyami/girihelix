defmodule GirihelixWeb.Workbench.Exhibits.IntersectTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Segment
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibits.Intersect, as: Exhibit
  alias GirihelixWeb.Workbench.Param

  test "at the defaults the segments cross at (1.0, 0.0)" do
    values = Param.values(Exhibit.params(), :default)
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

    assert Enum.any?(ops, fn
             {:point, at, _radius, _opts} -> at == {1.0, 0.0}
             _op -> false
           end)

    assert {"params", "{0.25, 0.5}"} in rows
    assert {"intersection", "1.0, 0.0"} in rows
    assert {"true intersection", "1.0, 0.0"} in rows
  end

  test "coincident endpoints are a failure state, not a crash" do
    values = Map.merge(Param.values(Exhibit.params(), :default), %{x2: 0.0, y2: 0.0})

    assert {:error, %Steps.Failure{step: %Steps.Step{id: :build}}} =
             Steps.run(Exhibit.steps(values), Exhibit.initial(values))
  end

  test "identifies itself and declares eight coordinates" do
    assert Exhibit.slug() == "intersect"
    assert Exhibit.category() == :geometry
    assert Exhibit.title() != ""
    assert Exhibit.summary() != ""

    params = Exhibit.params()

    assert Enum.map(params, & &1.name) == [:x1, :y1, :x2, :y2, :x3, :y3, :x4, :y4]

    assert Enum.map(params, & &1.default) == [0.0, 0.0, 4.0, 0.0, 1.0, -2.0, 1.0, 2.0]

    for param <- params do
      assert param.type == :float
      assert param.range == -5..5
      assert param.step == 0.1
    end
  end

  test "starts from the parameters and the build step returns both segments" do
    values = Param.values(Exhibit.params(), :default)

    assert Exhibit.initial(values) == values
    assert [%Steps.Step{id: :build} = step] = Exhibit.steps(values)

    assert %{
             first: first,
             second: second,
             params: {0.25, 0.5},
             intersection: intersection,
             true_intersection: true_intersection
           } = step.run.(values)

    assert {Segment.from(first), Segment.to(first)} ==
             {Point.new(0.0, 0.0), Point.new(4.0, 0.0)}

    assert {Segment.from(second), Segment.to(second)} ==
             {Point.new(1.0, -2.0), Point.new(1.0, 2.0)}

    assert %Point{x: x, y: y} = intersection
    assert {x, y} == {1.0, 0.0}
    assert %Point{x: true_x, y: true_y} = true_intersection
    assert {true_x, true_y} == {1.0, 0.0}
  end

  test "draws both segments, their endpoints and a larger crossing marker" do
    values = Param.values(Exhibit.params(), :default)
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

    assert [
             {:line, first_from, first_to, []},
             {:line, second_from, second_to, []},
             {:point, a, endpoint_radius, []},
             {:point, b, endpoint_radius, []},
             {:point, c, endpoint_radius, []},
             {:point, d, endpoint_radius, []},
             {:point, crossing, crossing_radius, []}
           ] = ops

    assert first_from == {0.0, 0.0}
    assert first_to == {4.0, 0.0}
    assert second_from == {1.0, -2.0}
    assert second_to == {1.0, 2.0}
    assert [a, b, c, d] == [{0.0, 0.0}, {4.0, 0.0}, {1.0, -2.0}, {1.0, 2.0}]
    assert crossing == {1.0, 0.0}
    assert crossing_radius > endpoint_radius

    assert rows == [
             {"params", "{0.25, 0.5}"},
             {"intersection", "1.0, 0.0"},
             {"true intersection", "1.0, 0.0"}
           ]
  end

  test "reports none when the lines cross outside a segment" do
    values = Param.values(Exhibit.params(), :default)
    values = Map.merge(values, %{y3: 1.0, y4: 2.0})

    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

    refute Enum.any?(ops, fn
             {:point, at, _radius, _opts} -> at == {1.0, 0.0}
             _op -> false
           end)

    assert rows == [
             {"params", "none"},
             {"intersection", "none"},
             {"true intersection", "none"}
           ]
  end

  test "frame zero draws the inputs before anything is built" do
    values = Param.values(Exhibit.params(), :default)
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, ops, rows} = Exhibit.draw(hd(frames), values)

    assert length(ops) == 6

    assert rows == [
             {"params", "none"},
             {"intersection", "none"},
             {"true intersection", "none"}
           ]
  end

  test "a failed build still leaves frame zero drawable" do
    values = Map.merge(Param.values(Exhibit.params(), :default), %{x2: 0.0, y2: 0.0})

    assert {:error, %Steps.Failure{frames: [frame]}} =
             Steps.run(Exhibit.steps(values), Exhibit.initial(values))

    assert {:both, ops, rows} = Exhibit.draw(frame, values)
    assert length(ops) == 6
    assert {"intersection", "none"} in rows
  end

  test "reproduces the crossing with a fully qualified pasteable snippet" do
    values = Param.values(Exhibit.params(), :default)

    assert Exhibit.reproduce(values) ==
             "{:ok, first} = Girihelix.Engine.Geometry.Segment.new(" <>
               "Girihelix.Engine.Geometry.Point.new(0.0, 0.0), " <>
               "Girihelix.Engine.Geometry.Point.new(4.0, 0.0))\n" <>
               "{:ok, second} = Girihelix.Engine.Geometry.Segment.new(" <>
               "Girihelix.Engine.Geometry.Point.new(1.0, -2.0), " <>
               "Girihelix.Engine.Geometry.Point.new(1.0, 2.0))\n" <>
               "Girihelix.Engine.Geometry.Intersect.get_intersection(first, second)"
  end
end

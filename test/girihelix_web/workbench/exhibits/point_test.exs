defmodule GirihelixWeb.Workbench.Exhibits.PointTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibits.Point, as: Exhibit
  alias GirihelixWeb.Workbench.Param

  test "at the defaults it draws the point and reports its measures" do
    values = Param.values(Exhibit.params(), :default)
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

    assert Enum.any?(ops, fn
             {:point, at, _radius, _opts} -> at == {3.0, 4.0}
             _op -> false
           end)

    assert Enum.any?(ops, fn
             {:line, from, to, _opts} -> from == {0.0, 0.0} and to == {3.0, 4.0}
             _op -> false
           end)

    assert {"mag", "5.0"} in rows
    assert {"mag2", "25.0"} in rows
    assert Exhibit.reproduce(values) == "Point.new(3.0, 4.0)"
  end

  test "identifies itself and declares two float coordinates" do
    assert Exhibit.slug() == "point"
    assert Exhibit.category() == :geometry
    assert Exhibit.title() != ""
    assert Exhibit.summary() != ""

    assert [x, y] = Exhibit.params()

    assert x.name == :x and x.type == :float
    assert x.default == 3.0 and x.range == -5..5 and x.step == 0.1
    assert y.name == :y and y.type == :float
    assert y.default == 4.0 and y.range == -5..5 and y.step == 0.1
  end

  test "starts from the parameters and runs one identity build step" do
    values = Param.values(Exhibit.params(), :default)

    assert Exhibit.initial(values) == values
    assert [%Steps.Step{id: :build} = step] = Exhibit.steps(values)
    assert step.run.(values) == values
  end

  test "draws the origin, the vector and the point, with every measure" do
    values = Param.values(Exhibit.params(), :default)
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, ops, rows} = Exhibit.draw(hd(frames), values)

    assert [
             {:point, origin, origin_radius, _origin_opts},
             {:line, from, to, _line_opts},
             {:point, tip, tip_radius, _tip_opts}
           ] = ops

    assert origin == {0.0, 0.0}
    assert from == {0.0, 0.0}
    assert to == {3.0, 4.0}
    assert tip == {3.0, 4.0}
    assert tip_radius > origin_radius

    assert rows == [
             {"x", "3.0"},
             {"y", "4.0"},
             {"mag", "5.0"},
             {"mag2", "25.0"},
             {"angle", "0.9272952180016122"},
             {"perp", "-4.0, 3.0"}
           ]
  end

  test "measures the point the parameters name, not the defaults" do
    values = Param.decode(Exhibit.params(), %{"x" => "1.0", "y" => "0.0"})
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, _ops, rows} = Exhibit.draw(List.last(frames), values)

    assert {"x", "1.0"} in rows
    assert {"angle", "0.0"} in rows
    assert {"perp", "-0.0, 1.0"} in rows
    assert Exhibit.reproduce(values) == "Point.new(1.0, 0.0)"
  end
end

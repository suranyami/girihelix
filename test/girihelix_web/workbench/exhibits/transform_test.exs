defmodule GirihelixWeb.Workbench.Exhibits.TransformTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibits.Transform, as: Exhibit
  alias GirihelixWeb.Workbench.Param

  # Float literals are legal in an equality check but warn in a pattern
  # (`0.0` matches only `+0.0`), so each op is compared value by value.
  test "at the defaults it translates the unit square" do
    values = Param.values(Exhibit.params(), :default)
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

    assert Enum.any?(ops, fn
             {:polygon, points, :stroke, _opts} ->
               points == [{1.0, 0.0}, {2.0, 0.0}, {2.0, 1.0}, {1.0, 1.0}]

             _op ->
               false
           end)

    assert {"determinant", "1.0"} in rows
    assert {"flips", "false"} in rows
  end

  test "identifies itself and declares six scalars and a shape" do
    assert Exhibit.slug() == "transform"
    assert Exhibit.category() == :geometry
    assert Exhibit.title() != ""
    assert Exhibit.summary() != ""

    assert [a, b, c, d, e, f, shape] = Exhibit.params()

    assert {a.name, a.type, a.default} == {:a, :float, 1.0}
    assert {b.name, b.type, b.default} == {:b, :float, 0.0}
    assert {c.name, c.type, c.default} == {:c, :float, 1.0}
    assert {d.name, d.type, d.default} == {:d, :float, 0.0}
    assert {e.name, e.type, e.default} == {:e, :float, 1.0}
    assert {f.name, f.type, f.default} == {:f, :float, 0.0}

    for scalar <- [a, b, c, d, e, f] do
      assert scalar.range == -2..2
      assert scalar.step == 0.1
    end

    assert {shape.name, shape.type, shape.default} == {:shape, :enum, :square}
    assert shape.options == [:square, :triangle]
  end

  test "starts from the parameters and runs one identity build step" do
    values = Param.values(Exhibit.params(), :default)

    assert Exhibit.initial(values) == values
    assert [%Steps.Step{id: :build} = step] = Exhibit.steps(values)
    assert step.run.(values) == values
  end

  test "draws the source as guides, the transformed square and its vertices" do
    values = Param.values(Exhibit.params(), :default)
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, ops, rows} = Exhibit.draw(hd(frames), values)

    assert [{:point, _, radius, []} | _] = Enum.drop(ops, 5)

    assert ops == [
             {:guide, {0.0, 0.0}, {1.0, 0.0}, []},
             {:guide, {1.0, 0.0}, {1.0, 1.0}, []},
             {:guide, {1.0, 1.0}, {0.0, 1.0}, []},
             {:guide, {0.0, 1.0}, {0.0, 0.0}, []},
             {:polygon, [{1.0, 0.0}, {2.0, 0.0}, {2.0, 1.0}, {1.0, 1.0}], :stroke, []},
             {:point, {1.0, 0.0}, radius, []},
             {:point, {2.0, 0.0}, radius, []},
             {:point, {2.0, 1.0}, radius, []},
             {:point, {1.0, 1.0}, radius, []}
           ]

    assert is_number(radius)

    assert rows == [
             {"a", "1.0"},
             {"b", "0.0"},
             {"c", "1.0"},
             {"d", "0.0"},
             {"e", "1.0"},
             {"f", "0.0"},
             {"determinant", "1.0"},
             {"flips", "false"}
           ]
  end

  test "draws the triangle when the shape parameter asks for it" do
    values = Param.decode(Exhibit.params(), %{"shape" => "triangle"})
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, ops, _rows} = Exhibit.draw(List.last(frames), values)

    guides = for {:guide, from, to, []} <- ops, do: {from, to}

    assert guides == [
             {{0.0, 0.0}, {1.0, 0.0}},
             {{1.0, 0.0}, {0.0, 1.0}},
             {{0.0, 1.0}, {0.0, 0.0}}
           ]

    assert Enum.any?(ops, fn
             {:polygon, points, :stroke, []} -> points == [{1.0, 0.0}, {2.0, 0.0}, {1.0, 1.0}]
             _op -> false
           end)
  end

  test "reports the determinant and orientation the parameters produce" do
    values = Param.decode(Exhibit.params(), %{"a" => "-1.0"})
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, _ops, rows} = Exhibit.draw(List.last(frames), values)

    assert {"a", "-1.0"} in rows
    assert {"determinant", "-1.0"} in rows
    assert {"flips", "true"} in rows
  end

  test "reproduces the transform with a fully qualified pasteable call" do
    defaults = Param.values(Exhibit.params(), :default)

    assert Exhibit.reproduce(defaults) ==
             "Girihelix.Engine.Geometry.Transform.new(1.0, 0.0, 1.0, 0.0, 1.0, 0.0)"

    identity = Param.decode(Exhibit.params(), %{"c" => "0.0"})

    assert Exhibit.reproduce(identity) ==
             "Girihelix.Engine.Geometry.Transform.new(1.0, 0.0, 0.0, 0.0, 1.0, 0.0)"
  end
end

defmodule GirihelixWeb.Workbench.Exhibits.FillRegionTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.FillRegion
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibits.FillRegion, as: Exhibit
  alias GirihelixWeb.Workbench.Param

  test "the default unit basis fills twenty cells" do
    values = Param.values(Exhibit.params(), :default)
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

    cells =
      Enum.filter(
        ops,
        &match?(
          {:polygon, _, :fill, [fill: "currentColor", stroke: "currentColor", width: 0.75, opacity: 0.3]},
          &1
        )
      )

    assert length(cells) == 20
    assert {"cells", "20"} in rows
    assert Enum.any?(ops, &match?({:label, _, "region", _}, &1))
    assert Enum.any?(ops, &match?({:label, _, "T1", _}, &1))
    assert Enum.any?(ops, &match?({:label, _, "T2", _}, &1))
    assert Enum.any?(ops, &match?({:label, _, "row 0: x 0.0 .. 4.0", _}, &1))
  end

  test "an intermediate frame draws only the region and its rows" do
    values = Param.values(Exhibit.params(), :default)
    {:ok, frames} = Steps.run(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, ops, rows} = Exhibit.draw(Enum.at(frames, 1), values)
    assert Enum.any?(ops, &match?({:polygon, _, :stroke, _}, &1))
    assert {"cells", "0"} in rows
  end

  test "identifies itself and declares its size and basis parameters" do
    assert Exhibit.slug() == "fill-region"
    assert Exhibit.category() == :geometry
    assert Exhibit.title() != ""
    assert Exhibit.summary() != ""

    assert [width, height, t1x, t1y, t2x, t2y] = Exhibit.params()

    assert {width.name, width.type, width.default} == {:width, :float, 4.0}
    assert {height.name, height.type, height.default} == {:height, :float, 3.0}

    for param <- [width, height] do
      assert param.range == 1..10
      assert param.step == 0.5
    end

    for {param, default} <- [{t1x, 1.0}, {t1y, 0.0}, {t2x, 0.0}, {t2y, 1.0}] do
      assert {param.name, param.type, param.default} == {param.name, :float, default}
      assert param.range == -2..2
      assert param.step == 0.1
    end
  end

  test "starts from FillRegion.start/3 and runs the three fill steps" do
    values = Param.values(Exhibit.params(), :default)

    assert Exhibit.initial(values) ==
             FillRegion.start(
               [
                 Point.new(0.0, 0.0),
                 Point.new(4.0, 0.0),
                 Point.new(4.0, 3.0),
                 Point.new(0.0, 3.0)
               ],
               Point.new(1.0, 0.0),
               Point.new(0.0, 1.0)
             )

    assert Enum.map(Exhibit.steps(values), & &1.id) == [:change_basis, :find_rows, :scan_rows]
  end

  test "frame zero draws the region but no rows and no cells" do
    values = Param.values(Exhibit.params(), :default)
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, ops, rows} = Exhibit.draw(hd(frames), values)

    assert {:polygon, region, :stroke, _} = hd(ops)
    assert region == [{0.0, 0.0}, {4.0, 0.0}, {4.0, 3.0}, {0.0, 3.0}]
    assert Enum.count(ops, &match?({:guide, _, _, _}, &1)) == 2

    assert rows == [
             {"rows", "0"},
             {"cells", "0"},
             {"failure", "none"},
             {"shading", "unit cells"},
             {"bars", "each row's outermost x extent"},
             {"arrows", "T1 and T2"}
           ]
  end

  test "the find-rows frame has its row range set but no rows yet" do
    values = Param.values(Exhibit.params(), :default)
    {:ok, frames} = Steps.run(Exhibit.steps(values), Exhibit.initial(values))
    frame = Enum.at(frames, 2)
    assert frame.step.id == :find_rows
    assert {:both, ops, rows} = Exhibit.draw(frame, values)

    assert Enum.count(ops, &match?({:guide, _, _, _}, &1)) == 2

    assert rows == [
             {"rows", "0"},
             {"cells", "0"},
             {"failure", "none"},
             {"shading", "unit cells"},
             {"bars", "each row's outermost x extent"},
             {"arrows", "T1 and T2"}
           ]
  end

  test "the final frame draws the translation guides, a guide per row and every cell" do
    values = Param.values(Exhibit.params(), :default)
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

    assert {:guide, {0.0, 0.0}, {1.0, 0.0}, [width: 2.0]} in ops
    assert {:guide, {0.0, 0.0}, {0.0, 1.0}, [width: 2.0]} in ops

    row_guides = Enum.filter(ops, &row_guide?/1)

    assert row_guides == [
             {:guide, {0.0, 0.0}, {4.0, 0.0}, [width: 2.0]},
             {:guide, {0.0, 1.0}, {4.0, 1.0}, [width: 2.0]},
             {:guide, {0.0, 2.0}, {4.0, 2.0}, [width: 2.0]},
             {:guide, {0.0, 3.0}, {4.0, 3.0}, [width: 2.0]}
           ]

    assert {:polygon, [{0.0, 0.0}, {1.0, 0.0}, {1.0, 1.0}, {0.0, 1.0}], :fill,
            [fill: "currentColor", stroke: "currentColor", width: 0.75, opacity: 0.3]} in ops

    assert rows == [
             {"rows", "4"},
             {"cells", "20"},
             {"failure", "none"},
             {"shading", "unit cells"},
             {"bars", "each row's outermost x extent"},
             {"arrows", "T1 and T2"}
           ]
  end

  test "row guides are mapped through a sheared basis" do
    values = %{Param.values(Exhibit.params(), :default) | t2y: 2.0}
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

    assert {:guide, {0.0, 0.0}, {4.0, 0.0}, [width: 2.0]} in ops
    assert {:guide, {0.0, 2.0}, {4.0, 2.0}, [width: 2.0]} in ops

    assert rows == [
             {"rows", "2"},
             {"cells", "10"},
             {"failure", "none"},
             {"shading", "unit cells"},
             {"bars", "each row's outermost x extent"},
             {"arrows", "T1 and T2"}
           ]
  end

  test "a region spanning too many lattice rows reports the failure" do
    values = %{
      Param.values(Exhibit.params(), :default)
      | width: 10.0,
        height: 10.0,
        t1x: 2.0,
        t1y: 1.9,
        t2x: 0.1,
        t2y: 0.1
    }

    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

    refute Enum.any?(
             ops,
             &match?(
               {:polygon, _, :fill, [fill: "currentColor", stroke: "currentColor", width: 0.75, opacity: 0.3]},
               &1
             )
           )

    assert rows == [
             {"rows", "0"},
             {"cells", "0"},
             {"failure", "too_many_units"},
             {"shading", "unit cells"},
             {"bars", "each row's outermost x extent"},
             {"arrows", "T1 and T2"}
           ]
  end

  test "a degenerate basis reports the failure and draws no cells" do
    values = %{Param.values(Exhibit.params(), :default) | t1x: 0.0, t1y: 0.0}
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

    refute Enum.any?(
             ops,
             &match?(
               {:polygon, _, :fill, [fill: "currentColor", stroke: "currentColor", width: 0.75, opacity: 0.3]},
               &1
             )
           )

    assert rows == [
             {"rows", "0"},
             {"cells", "0"},
             {"failure", "degenerate_basis"},
             {"shading", "unit cells"},
             {"bars", "each row's outermost x extent"},
             {"arrows", "T1 and T2"}
           ]
  end

  test "reproduces the fill with a fully qualified pasteable snippet" do
    values = Param.values(Exhibit.params(), :default)

    assert Exhibit.reproduce(values) ==
             "Girihelix.Engine.FillRegion.fill([" <>
               "Girihelix.Engine.Geometry.Point.new(0.0, 0.0), " <>
               "Girihelix.Engine.Geometry.Point.new(4.0, 0.0), " <>
               "Girihelix.Engine.Geometry.Point.new(4.0, 3.0), " <>
               "Girihelix.Engine.Geometry.Point.new(0.0, 3.0)], " <>
               "Girihelix.Engine.Geometry.Point.new(1.0, 0.0), " <>
               "Girihelix.Engine.Geometry.Point.new(0.0, 1.0))"

    shifted = %{values | width: 2.0, height: 1.5, t1x: 0.5, t1y: 1.0, t2x: -0.5, t2y: 1.0}

    assert Exhibit.reproduce(shifted) ==
             "Girihelix.Engine.FillRegion.fill([" <>
               "Girihelix.Engine.Geometry.Point.new(0.0, 0.0), " <>
               "Girihelix.Engine.Geometry.Point.new(2.0, 0.0), " <>
               "Girihelix.Engine.Geometry.Point.new(2.0, 1.5), " <>
               "Girihelix.Engine.Geometry.Point.new(0.0, 1.5)], " <>
               "Girihelix.Engine.Geometry.Point.new(0.5, 1.0), " <>
               "Girihelix.Engine.Geometry.Point.new(-0.5, 1.0))"
  end

  defp row_guide?({:guide, {from, _from_y}, {to, _to_y}, [width: 2.0]}), do: from == 0.0 and to == 4.0

  defp row_guide?(_op), do: false
end

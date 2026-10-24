defmodule GirihelixWeb.Workbench.Exhibits.FacesTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Faces
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibits.Faces, as: Exhibit
  alias GirihelixWeb.Workbench.Param

  test "the default scenario colours two faces" do
    values = Param.values(Exhibit.params(), :default)
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

    assert Enum.any?(
             ops,
             &match?({:polygon, _, :fill, [fill: "currentColor", opacity: 0.4]}, &1)
           )

    assert Enum.any?(
             ops,
             &match?(
               {:polygon, _, :stroke, [stroke: "currentColor", width: 1.5, dash: "4 3"]},
               &1
             )
           )

    assert {"black", "1"} in rows
    assert {"white", "1"} in rows
  end

  test "the square with a diagonal reports the filling conflict in the panel" do
    values = %{Param.values(Exhibit.params(), :default) | scenario: :square_diagonal}
    {:ok, frames} = Steps.run(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, _ops, rows} = Exhibit.draw(List.last(frames), values)
    assert {"failure", "filling_conflict"} in rows
  end

  test "identifies itself and declares the six scenarios" do
    assert Exhibit.slug() == "faces"
    assert Exhibit.category() == :geometry
    assert Exhibit.title() != ""
    assert Exhibit.summary() != ""

    assert [scenario] = Exhibit.params()
    assert {scenario.name, scenario.type, scenario.default} == {:scenario, :enum, :split_parallel}

    assert scenario.options ==
             [:split_parallel, :dangling, :figure_eight, :two_corner, :square_diagonal, :grid]
  end

  test "every scenario builds its map" do
    assert size(:split_parallel) == {3, 3}
    assert size(:dangling) == {4, 4}
    assert size(:figure_eight) == {7, 8}
    assert size(:two_corner) == {2, 2}
    assert size(:square_diagonal) == {4, 5}
    assert size(:grid) == {16, 24}
  end

  test "the scenarios reach the Plan 1c golden outcomes" do
    assert colours(:split_parallel) == {1, 1}
    assert colours(:dangling) == {1, 0}
    assert colours(:figure_eight) == {2, 0}
    assert colours(:two_corner) == {2, 1}

    assert Faces.extract_faces(Exhibit.scenario(:square_diagonal)) ==
             {:error, :filling_conflict}

    assert Faces.extract_faces(Exhibit.scenario(:grid)) == {:error, :filling_conflict}
  end

  test "starts from Faces.start/1 and runs the three face steps" do
    values = Param.values(Exhibit.params(), :default)

    assert Exhibit.initial(values) == Faces.start(Exhibit.scenario(:split_parallel))
    assert Enum.map(Exhibit.steps(values), & &1.id) == [:discover, :colour, :collect]
  end

  test "frame zero draws the map before any face is discovered" do
    values = Param.values(Exhibit.params(), :default)
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, ops, rows} = Exhibit.draw(hd(frames), values)

    assert Enum.count(ops, &match?({:line, _, _, []}, &1)) == 3
    refute Enum.any?(ops, &match?({:point, _, _, []}, &1))

    assert rows == [
             {"discovered", "0"},
             {"kept", "0"},
             {"black", "0"},
             {"white", "0"},
             {"failure", "none"}
           ]
  end

  test "the final frame fills each kept face and marks every discovered corner" do
    values = Param.values(Exhibit.params(), :default)
    frames = Steps.run!(Exhibit.steps(values), Exhibit.initial(values))
    assert {:both, ops, rows} = Exhibit.draw(List.last(frames), values)

    assert Enum.count(ops, &match?({:polygon, _, :fill, _}, &1)) == 1
    assert Enum.count(ops, &match?({:polygon, _, :stroke, _}, &1)) == 1
    assert Enum.count(ops, &match?({:point, _, _, []}, &1)) == 6

    assert rows == [
             {"discovered", "2"},
             {"kept", "2"},
             {"black", "1"},
             {"white", "1"},
             {"failure", "none"}
           ]
  end

  test "reproduces the scenario with a fully qualified pasteable snippet" do
    values = Param.values(Exhibit.params(), :default)

    assert Exhibit.reproduce(values) ==
             "Girihelix.Engine.Faces.extract_faces(GirihelixWeb.Workbench.Exhibits.Faces.scenario(:split_parallel))"

    assert Exhibit.reproduce(%{values | scenario: :grid}) ==
             "Girihelix.Engine.Faces.extract_faces(GirihelixWeb.Workbench.Exhibits.Faces.scenario(:grid))"
  end

  defp size(name) do
    map = Exhibit.scenario(name)
    {PlanarMap.num_vertices(map), PlanarMap.num_edges(map)}
  end

  defp colours(name) do
    {:ok, colouring} = Faces.extract_faces(Exhibit.scenario(name))
    {length(colouring.black), length(colouring.white)}
  end
end

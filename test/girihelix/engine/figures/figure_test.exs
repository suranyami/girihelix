defmodule Girihelix.Engine.Figures.FigureTest do
  @moduledoc """
  The figure dispatcher, exercised by the four-fold square fixture.
  """

  use ExUnit.Case, async: true

  alias Girihelix.Engine.FigureFixtures.Square
  alias Girihelix.Engine.Figures.Figure
  alias Girihelix.Engine.PlanarMap

  test "unit/1 and map/1 replicate the fixture four times without doubling the vertices" do
    figure = %Square{}

    unit = Figure.unit(figure)
    assert PlanarMap.num_vertices(unit) == 4
    assert PlanarMap.num_edges(unit) == 4

    map = Figure.map(figure)

    # Four rotations of the diamond land on the same four vertices, so the
    # ladder does not double them: the copies coalesce.
    assert PlanarMap.num_vertices(map) == 4

    # `replicate!/3` coalesces vertices but never edges. This fixture's unit is
    # closed, so each of the four transforms contributes its four edges and the
    # result is sixteen parallel edges, which `verify/1` reports. That is the
    # engine's documented behaviour, not a fault in the fixture.
    assert PlanarMap.num_edges(map) == 16
    assert {:error, problems} = PlanarMap.verify(map)
    assert Enum.all?(problems, &match?({:parallel_edge, _edge}, &1))
  end

  test "radial?/1 distinguishes the radial figures" do
    assert Figure.radial?(%Square{})
  end
end

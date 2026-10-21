defmodule Girihelix.Engine.Figures.FigureTest do
  @moduledoc """
  The figure dispatcher, exercised by the four-fold square fixture.
  """

  use ExUnit.Case, async: true

  alias Girihelix.Engine.FigureFixtures.Square
  alias Girihelix.Engine.Figures.Figure
  alias Girihelix.Engine.PlanarMap

  test "unit/1 and map/1 replicate the fixture four times without doubling" do
    figure = %Square{}

    unit = Figure.unit(figure)
    assert PlanarMap.num_vertices(unit) == 2
    assert PlanarMap.num_edges(unit) == 1

    map = Figure.map(figure)

    # Four quarter turns of the wedge produce the diamond's four sides, so the
    # copies meet at shared vertices and add no parallel edges.
    assert PlanarMap.verify(map) == :ok
    assert PlanarMap.num_vertices(map) == 4
    assert PlanarMap.num_edges(map) == 4
  end

  test "radial?/1 distinguishes the radial figures" do
    assert Figure.radial?(%Square{})
  end
end

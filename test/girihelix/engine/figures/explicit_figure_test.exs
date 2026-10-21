defmodule Girihelix.Engine.Figures.ExplicitFigureTest do
  @moduledoc """
  The explicit figure: a stored map returned unchanged, and not radial.
  """

  use ExUnit.Case, async: true

  alias Girihelix.Engine.Figures.ExplicitFigure
  alias Girihelix.Engine.Figures.Figure
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap

  test "new/1 accepts a map and returns the same map from build_unit/1" do
    {map, _vertex} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(1.0, 2.0))

    assert {:ok, figure} = ExplicitFigure.new(map)
    assert figure.map == map
    assert ExplicitFigure.build_unit(figure) == map
    assert Figure.unit(figure) == map
    assert Figure.map(figure) == map
  end

  test "new/1 refuses a non-map and new!/1 raises" do
    assert ExplicitFigure.new(:nope) == {:error, :not_a_map}
    assert_raise ArgumentError, ~r/not_a_map/, fn -> ExplicitFigure.new!(:nope) end
  end

  test "an explicit figure is not radial" do
    assert Figure.radial?(ExplicitFigure.new!(PlanarMap.new())) == false
  end
end

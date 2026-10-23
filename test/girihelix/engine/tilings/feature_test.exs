defmodule Girihelix.Engine.Tilings.FeatureTest do
  @moduledoc """
  The tiling tile value: the regular polygon generator, tolerant equality, and
  catalogue id assignment. Also the placed tile, whose equality is structural.
  """

  use ExUnit.Case, async: true

  alias Girihelix.Engine.Figures.RadialFigure
  alias Girihelix.Engine.Geometry.Loose
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.Engine.Tilings.Feature
  alias Girihelix.Engine.Tilings.PlacedFeature

  test "a regular feature generates Taprats' polygon" do
    n = 6
    feature = Feature.new(regular: n, points: [])
    r = 1.0 / :math.cos(:math.pi() / n)

    expected =
      Enum.map(0..(n - 1), fn i ->
        Point.scale(RadialFigure.arc((2 * i + 1) / (2 * n)), r)
      end)

    assert length(Feature.points(feature)) == n

    for {actual, want} <- Enum.zip(Feature.points(feature), expected) do
      assert Loose.equals(actual, want)
    end
  end

  test "equal?/2 is tolerant on points and includes the regular flag" do
    a = Feature.new(regular: 4, points: [])
    b = Feature.new(regular: 4, points: [])
    c = Feature.new(regular: nil, points: Feature.points(a))

    off =
      Feature.new(
        regular: nil,
        points: Enum.map(Feature.points(a), &Point.add(&1, Point.new(1.0e-8, 0.0)))
      )

    assert Feature.equal?(a, b)
    refute Feature.equal?(a, c)
    assert Feature.equal?(c, off)
  end

  test "assign_ids/1 shares one id across tolerant duplicates" do
    a = Feature.new(regular: 4, points: [])
    b = Feature.new(regular: 4, points: [])
    c = Feature.new(regular: 3, points: [])

    assert [%{id: 0}, %{id: 0}, %{id: 1}] = Feature.assign_ids([a, b, c])
  end

  test "a placed feature compares its transform exactly" do
    t = Transform.translate(1.0, 2.0)
    assert PlacedFeature.new(0, t) == PlacedFeature.new(0, t)
    refute PlacedFeature.new(0, t) == PlacedFeature.new(1, t)
  end
end

defmodule Girihelix.Engine.Figures.ConnectFigureTest do
  @moduledoc """
  The connecting wrapper: the derived scale, the fold that moves the apex back
  to `(1, 0)`, and the agreement between the stepped and plain builders.
  """

  use ExUnit.Case, async: true

  alias Girihelix.Engine.FigureFixtures.Counting
  alias Girihelix.Engine.Figures.ConnectFigure
  alias Girihelix.Engine.Figures.ExplicitFigure
  alias Girihelix.Engine.Figures.Figure
  alias Girihelix.Engine.Figures.Rosette
  alias Girihelix.Engine.Figures.ScaleFigure
  alias Girihelix.Engine.Figures.Star
  alias Girihelix.Engine.Geometry.Loose
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Steps

  test "new/1 derives and stores the scale, and refuses a non-radial child" do
    rosette = Rosette.new!(8, 0.0, 3)
    assert {:ok, connect} = ConnectFigure.new(rosette)
    assert connect.s == ScaleFigure.normalise_s(ConnectFigure.compute_scale(rosette))
    # The oracle's ConnectFigure for this rosette stores 1/sqrt(2), not > 1:
    # the crossing lands on the inradius of the unit n-gon.
    assert_in_delta connect.s, 0.7071067811865475, 1.0e-12

    map = PlanarMap.new() |> PlanarMap.insert_vertex(Point.new(0.0, 0.0)) |> elem(0)
    assert ConnectFigure.new(ExplicitFigure.new!(map)) == {:error, :not_radial}
  end

  test "child_changed/1 re-derives the scale" do
    connect = ConnectFigure.new!(Rosette.new!(8, 0.0, 3))
    changed = ConnectFigure.child_changed(%{connect | child: Rosette.new!(8, -0.3, 3)})
    assert changed.s == ScaleFigure.normalise_s(ConnectFigure.compute_scale(changed.child))
  end

  test "a connected rosette verifies and normalises to x <= 1" do
    connect = ConnectFigure.new!(Rosette.new!(8, 0.0, 3))
    map = ConnectFigure.build_unit(connect)

    assert PlanarMap.verify(map) == :ok
    max_x = map |> PlanarMap.vertices() |> Enum.map(&PlanarMap.position!(map, &1).x) |> Enum.max()
    assert_in_delta max_x, 1.0, 1.0e-9
  end

  # The three `1.0` fallbacks are geometrically identical, so each is pinned by
  # the state that reaches it rather than by the returned number alone.
  test "compute_scale/1 falls back to 1.0 when the child has no tip at (1, 0)" do
    child = ScaleFigure.new!(Rosette.new!(8, 0.0, 3), 0.5)
    unit = Figure.unit(child)

    refute tip(unit)
    assert ConnectFigure.compute_scale(child) == 1.0
  end

  test "compute_scale/1 falls back to 1.0 when the tip has no lower neighbour" do
    child = Star.new!(8, 3.0, 0)
    unit = Figure.unit(child)

    assert PlanarMap.num_edges(unit) == 0
    assert tip(unit)
    refute lower_neighbour(unit, tip(unit))
    assert ConnectFigure.compute_scale(child) == 1.0
  end

  test "compute_scale/1 falls back to 1.0 when the rotated ray misses the fixed ray" do
    # Star(8, 3.0, 2) reaches the crossing test: its tip has a lower neighbour,
    # but the rotated mirror is parallel to the fixed ray, so the intersection
    # is nil. This is the third `1.0` path.
    child = Star.new!(8, 3.0, 2)
    unit = Figure.unit(child)

    assert tip(unit)
    assert lower_neighbour(unit, tip(unit))
    assert ConnectFigure.compute_scale(child) == 1.0
  end

  test "the fold leaves an axis seam from its two tolerances" do
    connect = ConnectFigure.new!(Rosette.new!(8, 0.0, 3))

    frames =
      connect.child
      |> ConnectFigure.steps(connect.s)
      |> Steps.run!(ConnectFigure.start(connect.child, connect.s))

    clipped = frame(frames, :scale_clip).state.map
    folded = frame(frames, :fold).state.map

    # The band |y| <= 1e-7 keeps its originals as well as their rotated copies:
    # the apex survives the deletion pass and a second axis vertex is added.
    [apex] = axis(clipped)
    assert apex in axis(folded)
    assert length(axis(folded)) == 2
  end

  test "the fold keeps the apex on the axis" do
    connect = ConnectFigure.new!(Rosette.new!(8, 0.0, 3))
    map = ConnectFigure.build_unit(connect)

    apex =
      Enum.find(PlanarMap.vertices(map), fn v ->
        PlanarMap.position!(map, v).x > 0.999
      end)

    assert apex
    assert_in_delta PlanarMap.position!(map, apex).y, 0.0, 1.0e-7
  end

  test "the stepped builder and the plain builder agree" do
    connect = ConnectFigure.new!(Rosette.new!(8, 0.0, 3))

    stepped =
      connect.child
      |> ConnectFigure.steps(connect.s)
      |> Steps.run!(ConnectFigure.start(connect.child, connect.s))
      |> Steps.final()
      |> ConnectFigure.result()

    assert stepped == ConnectFigure.build_unit(connect)
  end

  test "new/1 caches the child unit and build_unit/1 does not rebuild the child" do
    connect = ConnectFigure.new!(%Counting{pid: self()})

    assert_received :child_built
    refute_received :child_built

    ConnectFigure.build_unit(connect)
    refute_received :child_built
  end

  test "child_changed/1 replaces the cached unit" do
    first = Rosette.new!(8, 0.0, 3)
    second = Rosette.new!(8, -0.3, 3)
    connect = ConnectFigure.new!(first)
    changed = ConnectFigure.child_changed(%{connect | child: second})

    assert changed.unit == Figure.unit(second)
    assert changed.s == ScaleFigure.normalise_s(ConnectFigure.compute_scale(second))
    refute changed.unit == connect.unit
  end

  test "the cached unit produces the same unit as the plain builder" do
    connect = ConnectFigure.new!(Rosette.new!(8, 0.0, 3))

    assert ConnectFigure.build_unit(connect) ==
             ConnectFigure.build_unit(connect.child, connect.s)
  end

  defp frame(frames, id) do
    Enum.find(frames, fn frame -> frame.step && frame.step.id == id end)
  end

  defp tip(map) do
    Enum.find(PlanarMap.vertices(map), fn vertex ->
      Loose.equals(PlanarMap.position!(map, vertex), Point.new(1.0, 0.0))
    end)
  end

  defp lower_neighbour(map, tip) do
    map
    |> PlanarMap.ring!(tip)
    |> Enum.map(&far_vertex(map, &1, tip))
    |> Enum.find(fn vertex -> PlanarMap.position!(map, vertex).y < 0.0 end)
  end

  defp far_vertex(map, edge, vertex) do
    case PlanarMap.endpoints!(map, edge) do
      {^vertex, other} -> other
      {other, _second} -> other
    end
  end

  defp axis(map) do
    map
    |> PlanarMap.vertices()
    |> Enum.map(&PlanarMap.position!(map, &1))
    |> Enum.filter(fn point -> abs(point.y) <= 1.0e-7 end)
  end
end

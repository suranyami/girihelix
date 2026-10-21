defmodule Girihelix.Engine.Figures.ScaleFigureTest do
  @moduledoc """
  The nested scaling wrapper: the constructor and its clamp, the passthrough at
  `s = 1`, and the clipped scaled unit.
  """

  use ExUnit.Case, async: true

  alias Girihelix.Engine.Figures.ExplicitFigure
  alias Girihelix.Engine.Figures.Rosette
  alias Girihelix.Engine.Figures.ScaleFigure
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Steps

  test "s within 1e-7 of one is stored as exactly 1.0" do
    assert ScaleFigure.normalise_s(1.00000005) == 1.0
    assert ScaleFigure.normalise_s(1.001) == 1.001
    assert {:ok, %ScaleFigure{s: 1.0}} = ScaleFigure.new(Rosette.new!(8, 0.0, 3), 0.99999999)
  end

  test "an explicit child is not radial" do
    map = PlanarMap.new() |> PlanarMap.insert_vertex(Point.new(0.0, 0.0)) |> elem(0)

    assert ScaleFigure.new(ExplicitFigure.new!(map), 1.5) == {:error, :not_radial}
  end

  test "with_s/2 normalises and with_child/2 rechecks radiality" do
    figure = ScaleFigure.new!(Rosette.new!(8, 0.0, 3), 1.5)
    explicit = ExplicitFigure.new!(PlanarMap.new())

    assert ScaleFigure.with_s(figure, 0.99999999).s == 1.0
    assert ScaleFigure.with_s(figure, 1.001).s == 1.001

    assert {:ok, %ScaleFigure{child: %Rosette{}}} =
             ScaleFigure.with_child(figure, Rosette.new!(6, 0.0, 2))

    assert ScaleFigure.with_child(figure, explicit) == {:error, :not_radial}
    assert ScaleFigure.n(figure) == 8

    assert_raise ArgumentError, ~r/not_radial/, fn -> ScaleFigure.new!(explicit, 1.5) end
  end

  test "s = 1 passes the child's unit through unchanged" do
    child = Rosette.new!(8, 0.0, 3)

    assert ScaleFigure.build_unit(child, 1.0) == Rosette.build_unit(child)

    stepped =
      child
      |> ScaleFigure.steps(1.0)
      |> Steps.run!(ScaleFigure.start(child, 1.0))
      |> Steps.final()

    assert stepped.passthrough
    assert ScaleFigure.result(stepped) == Rosette.build_unit(child)
  end

  # The source clips only when the tip starts inside the n-gon. At s = 1.5 the
  # ray points outward and falls back to the tip, leaving max x = 1.5, as the
  # Java fixture `figure-scale-rosette` shows; s = 0.5 is the clipping case.
  test "a scaled rosette stays inside the unit n-gon and verifies" do
    child = Rosette.new!(8, 0.0, 3)
    map = ScaleFigure.build_unit(child, 0.5)

    assert PlanarMap.verify(map) == :ok
    max_x = map |> PlanarMap.vertices() |> Enum.map(&PlanarMap.position!(map, &1).x) |> Enum.max()
    assert max_x <= 1.0 + 1.0e-9
  end

  test "an outward ray falls back to the tip above unit scale" do
    child = Rosette.new!(8, 0.0, 3)
    map = ScaleFigure.build_unit(child, 1.5)

    assert PlanarMap.verify(map) == :ok
    max_x = map |> PlanarMap.vertices() |> Enum.map(&PlanarMap.position!(map, &1).x) |> Enum.max()
    assert_in_delta max_x, 1.5, 1.0e-9
  end

  # The s = 1.5 test above pins the max-x result; this one names the cause: the
  # ray hits no n-gon edge, so the endpoint stays on the tip and the endpoint
  # insertion coalesces onto the chain head instead of adding a closing seam.
  test "the s = 1.5 endpoint coalesces onto the chain head" do
    child = Rosette.new!(8, 0.0, 3)

    frames =
      child
      |> ScaleFigure.steps(1.5)
      |> Steps.run!(ScaleFigure.start(child, 1.5))

    clip = frame(frames, :clip)
    extended = frame(frames, :extend)
    endpoint = frame(frames, :endpoint)

    assert clip.state.endpoint == clip.state.tip_pos
    assert endpoint.state.last_top == extended.state.last_top

    assert PlanarMap.num_vertices(endpoint.state.map) ==
             PlanarMap.num_vertices(extended.state.map)

    assert PlanarMap.num_edges(endpoint.state.map) == PlanarMap.num_edges(extended.state.map)
  end

  test "the stepped builder and the plain builder agree" do
    child = Rosette.new!(8, 0.0, 3)

    plain = ScaleFigure.build_unit(child, 1.5)

    stepped =
      child
      |> ScaleFigure.steps(1.5)
      |> Steps.run!(ScaleFigure.start(child, 1.5))
      |> Steps.final()
      |> ScaleFigure.result()

    assert stepped == plain
  end

  defp frame(frames, id) do
    Enum.find(frames, fn frame -> frame.step && frame.step.id == id end)
  end
end

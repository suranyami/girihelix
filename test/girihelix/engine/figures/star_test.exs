defmodule Girihelix.Engine.Figures.StarTest do
  @moduledoc """
  The `[n/d]s` star: its clamps and snap, and the unit's vertex and edge counts
  for the open chain, the rotated-apex closure and the fractional `cent`
  closure.
  """

  use ExUnit.Case, async: true

  alias Girihelix.Engine.Figures.Star
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Steps

  test "new/3 stores the clamped d and s beside the raw d" do
    assert {:ok, star} = Star.new(8, 99.0, 9)
    assert star.d == 99.0
    assert star.clamp_d == 3.99
    assert star.s == 3
    assert {:ok, %Star{d: 3.0, clamp_d: 3.0, s: 2}} = Star.new(8, 3.0, 2)
    assert {:ok, %Star{clamp_d: 1.0}} = Star.new(8, 0.5, 2)
  end

  test "invalid order and negative steps are refused" do
    assert Star.new(2, 3.0, 2) == {:error, :invalid_order}
    assert Star.new(8, 3.0, -1) == {:error, :invalid_step_count}
    assert_raise ArgumentError, ~r/invalid_order/, fn -> Star.new!(2, 3.0, 2) end
  end

  test "clamp_d and clamp_s are the source's expressions" do
    assert Star.clamp_d(8, 99.0) == 3.99
    assert Star.clamp_d(8, 0.5) == 1.0
    assert Star.clamp_s(9, 3) == 3
    assert Star.clamp_s(2, 3) == 2
  end

  test "the default unit is an open five-vertex chain" do
    map = Star.build_unit(Star.new!(8, 3.0, 2))
    assert PlanarMap.verify(map) == :ok
    assert PlanarMap.num_vertices(map) == 5
    assert PlanarMap.num_edges(map) == 4
  end

  test "s = 3 closes the unit at the rotated apex" do
    map = Star.build_unit(Star.new!(8, 3.0, 3))
    assert PlanarMap.verify(map) == :ok
    assert PlanarMap.num_vertices(map) == 6
    assert PlanarMap.num_edges(map) == 5
  end

  test "a fractional d inserts the cent vertex and two closure edges" do
    # outer_s = min(s, di - 1) = 1, so the chain holds one crossing: the tip,
    # its mirror pair, and then the closure's apex and cent vertices.
    map = Star.build_unit(Star.new!(8, 2.5, 2))
    assert PlanarMap.verify(map) == :ok
    assert PlanarMap.num_vertices(map) == 5
    assert PlanarMap.num_edges(map) == 4
  end

  test "the near-integral snap disables the closure" do
    # d rounds up to 3 after outer_s and clamp_s have taken the pre-increment
    # di = 2, so clamp_s (2) never equals the snapped di (3) and the unit is
    # the one-crossing chain alone. Without the snap the fractional closure
    # would add the apex and cent vertices.
    map = Star.build_unit(Star.new!(8, 2.99999999, 2))
    assert PlanarMap.verify(map) == :ok
    assert PlanarMap.num_vertices(map) == 3
    assert PlanarMap.num_edges(map) == 2
  end

  test "the stepped builder and the plain builder agree" do
    plain = Star.build_unit(Star.new!(8, 3.0, 2))

    frames = Steps.run!(Star.steps(8, 3.0, 2), Star.start(8, 3.0, 2))
    stepped = frames |> Steps.final() |> Star.result()

    assert stepped == plain
  end

  test "a failed crossing raises rather than substituting a point (n = 8, d = 7.02, s = 3)" do
    # Found by the golden scenario figure-star-crash; the source dereferences a
    # null here. The reason names the failure.
    assert_raise ArgumentError, ~r/degenerate_crossing/, fn ->
      Star.build_unit(Star.new!(8, 7.02, 3))
    end
  end
end

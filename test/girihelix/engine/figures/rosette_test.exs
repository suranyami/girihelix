defmodule Girihelix.Engine.Figures.RosetteTest do
  @moduledoc """
  The Lee rosette: the constructor's clamps, the stepped and plain builders, the
  FIXME's skipped crossing, and the unit's symmetry.
  """

  use ExUnit.Case, async: true

  alias Girihelix.Engine.Figures.Rosette
  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Steps

  test "new/3 clamps q and s and stores the clamped values" do
    assert {:ok, rosette} = Rosette.new(8, 2.0, 9)
    assert rosette.q == 0.99
    assert rosette.s == 3
    assert {:ok, %Rosette{q: -0.99, s: 3}} = Rosette.new(8, -2.0, 3)
    assert Rosette.clamp_s(12, 9) == 5
    assert Rosette.clamp_s(5, 9) == 2
  end

  test "with_s/2 clamps like the constructor" do
    rosette = Rosette.new!(8, 0.0, 1)
    assert Rosette.with_s(rosette, 99).s == 3
    assert Rosette.with_q(rosette, -9.0).q == -0.99
  end

  test "invalid order and negative steps are refused" do
    assert Rosette.new(2, 0.0, 3) == {:error, :invalid_order}
    assert Rosette.new(8, 0.0, -1) == {:error, :invalid_step_count}
    assert_raise ArgumentError, ~r/invalid_order/, fn -> Rosette.new!(2, 0.0, 3) end
  end

  test "the default unit verifies and its stepped and plain builds agree" do
    plain = Rosette.build_unit(Rosette.new!(8, 0.0, 3))
    assert PlanarMap.verify(plain) == :ok

    stepped =
      8
      |> Rosette.steps(0.0, 3)
      |> Steps.run!(Rosette.start(8, 0.0, 3))
      |> Steps.final()
      |> Rosette.result()

    assert stepped == plain
  end

  test "the documented FIXME case skips a step and still builds" do
    map = Rosette.build_unit(Rosette.new!(12, -0.8, 4))
    assert PlanarMap.verify(map) == :ok

    state =
      12
      |> Rosette.steps(-0.8, 4)
      |> Steps.run!(Rosette.start(12, -0.8, 4))
      |> Steps.final()

    assert state.skipped > 0
  end

  test "the unit is symmetric about the x axis" do
    map = Rosette.build_unit(Rosette.new!(8, 0.0, 3))
    ys = Enum.map(PlanarMap.vertices(map), &PlanarMap.position!(map, &1).y)

    assert Enum.sort(ys) == Enum.sort(Enum.map(ys, &(-&1)))
  end
end

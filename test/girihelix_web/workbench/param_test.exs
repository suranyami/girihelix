defmodule GirihelixWeb.Workbench.ParamTest do
  use ExUnit.Case, async: true

  alias GirihelixWeb.Workbench.Param

  @params [
    %Param{name: :n, type: :integer, range: 3..24, default: 8, doc: "order"},
    # Elixir 1.20 ranges are integer-only; `step` carries the float precision.
    %Param{name: :d, type: :float, range: 1..10, step: 0.1, default: 3.0, doc: "skip"},
    %Param{name: :on, type: :boolean, default: true, doc: "toggle"},
    %Param{
      name: :shape,
      type: :enum,
      options: [:square, :triangle],
      default: :square,
      doc: "shape"
    }
  ]

  test "decode/2 falls back to defaults" do
    assert Param.decode(@params, %{}) == %{n: 8, d: 3.0, on: true, shape: :square}
  end

  test "decode/2 clamps numbers and rejects garbage" do
    assert Param.decode(@params, %{"n" => "99", "d" => "-4.0"})[:n] == 24
    assert Param.decode(@params, %{"n" => "99", "d" => "-4.0"})[:d] == 1.0
    assert Param.decode(@params, %{"n" => "x", "d" => "x"})[:n] == 8
    assert Param.decode(@params, %{"n" => "x", "d" => "x"})[:d] == 3.0
  end

  test "decode/2 reads booleans and enums" do
    assert Param.decode(@params, %{"on" => "false"})[:on] == false
    assert Param.decode(@params, %{"on" => "nonsense"})[:on] == true
    assert Param.decode(@params, %{"shape" => "triangle"})[:shape] == :triangle
    assert Param.decode(@params, %{"shape" => "hexagon"})[:shape] == :square
  end

  test "encode/2 round-trips through decode/2" do
    values = %{n: 12, d: 4.5, on: false, shape: :triangle}
    encoded = Param.encode(@params, values)

    assert encoded == %{"n" => "12", "d" => "4.5", "on" => "false", "shape" => "triangle"}
    assert Param.decode(@params, encoded) == values
  end

  test "values/2 gives the defaults and both extremes" do
    assert Param.values(@params, :default) == %{n: 8, d: 3.0, on: true, shape: :square}
    assert Param.values(@params, :first) == %{n: 3, d: 1.0, on: false, shape: :square}
    assert Param.values(@params, :last) == %{n: 24, d: 10.0, on: true, shape: :triangle}
  end

  test "decode/2 ignores unknown keys and non-string values" do
    # A repeated query parameter arrives as a list, and an unrelated key is not a
    # parameter at all. Neither may crash or leak into the result.
    assert Param.decode(@params, %{"n" => ["1", "2"], "frame" => "3"}) == %{
             n: 8,
             d: 3.0,
             on: true,
             shape: :square
           }
  end

  test "decode/2 rejects a partly numeric string" do
    assert Param.decode(@params, %{"n" => "12px"})[:n] == 8
    assert Param.decode(@params, %{"d" => "4.5x"})[:d] == 3.0
  end

  test "decode/2 leaves an unclamped numeric parameter alone" do
    params = [%Param{name: :size, type: :integer, default: 5}]

    assert Param.decode(params, %{"size" => "-99"}) == %{size: -99}
  end

  test "encode/2 falls back to the default for a missing key" do
    assert Param.encode(@params, %{n: 12}) == %{
             "n" => "12",
             "d" => "3.0",
             "on" => "true",
             "shape" => "square"
           }
  end
end

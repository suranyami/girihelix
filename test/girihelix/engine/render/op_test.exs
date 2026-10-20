defmodule Girihelix.Engine.Render.OpTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Render.Op

  test "known?/1 accepts the five ops and rejects anything else" do
    assert Op.known?({:line, {0.0, 0.0}, {1.0, 1.0}, []})
    assert Op.known?({:polygon, [{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}], :fill, []})
    assert Op.known?({:point, {2.0, 3.0}, 0.5, []})
    assert Op.known?({:label, {2.0, 3.0}, "hi", []})
    assert Op.known?({:guide, {0.0, 0.0}, {1.0, 1.0}, []})
    refute Op.known?({:arc, {0.0, 0.0}, {1.0, 1.0}, []})
    refute Op.known?(:nope)
  end

  test "points/1 returns every positional point" do
    assert Op.points({:line, {0.0, 0.0}, {1.0, 1.0}, []}) == [{0.0, 0.0}, {1.0, 1.0}]
    assert Op.points({:guide, {0.0, 0.0}, {1.0, 1.0}, []}) == [{0.0, 0.0}, {1.0, 1.0}]

    assert Op.points({:polygon, [{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}], :stroke, []}) ==
             [{0.0, 0.0}, {1.0, 0.0}, {0.0, 1.0}]

    assert Op.points({:point, {2.0, 3.0}, 0.5, []}) == [{2.0, 3.0}]
    assert Op.points({:label, {2.0, 3.0}, "hi", []}) == [{2.0, 3.0}]
  end

  test "points/1 raises for an unknown op" do
    assert_raise ArgumentError, "unknown draw op", fn ->
      Op.points({:arc, {0.0, 0.0}, {1.0, 1.0}, []})
    end
  end
end

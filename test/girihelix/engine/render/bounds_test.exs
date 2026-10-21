defmodule Girihelix.Engine.Render.BoundsTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Render.Bounds

  test "of_ops/1 spans every positional point and is nil without one" do
    assert Bounds.of_ops([]) == nil
    assert Bounds.of_ops([{:label, {1.0, 1.0}, "x", []}]) == {1.0, 1.0, 1.0, 1.0}

    assert Bounds.of_ops([{:line, {0.0, 0.0}, {4.0, 3.0}, []}]) ==
             {0.0, 0.0, 4.0, 3.0}

    assert Bounds.of_ops([
             {:line, {0.0, 0.0}, {4.0, 0.0}, []},
             {:point, {-1.0, 2.0}, 0.5, []}
           ]) == {-1.0, 0.0, 4.0, 2.0}
  end

  test "pad/2 grows every side" do
    assert Bounds.pad({0.0, 0.0, 4.0, 3.0}, 1.0) == {-1.0, -1.0, 5.0, 4.0}
  end
end

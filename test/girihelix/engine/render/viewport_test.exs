defmodule Girihelix.Engine.Render.ViewportTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Render.Viewport

  test "fit/2 frames bounds with padding and aspect" do
    # padding 0, square aspect: the bounds are the view. The derived scale makes
    # the viewBox 1000 units wide, so 1 unit of stroke is not a fifth of the map.
    assert Viewport.fit({0.0, 0.0, 10.0, 10.0}, padding: 0.0, aspect: 1.0) ==
             %Viewport{left: 0.0, top: 10.0, width: 10.0, scale: 100.0}

    # padding 0.1 of the larger extent: 12 x 12, still a 1000-wide viewBox.
    assert Viewport.fit({0.0, 0.0, 10.0, 10.0}, aspect: 1.0) ==
             %Viewport{left: -1.0, top: 11.0, width: 12.0, scale: 1000.0 / 12.0}

    # A wide aspect widens the view and re-centres the content in x.
    assert Viewport.fit({0.0, 0.0, 10.0, 10.0}, padding: 0.0, aspect: 0.5) ==
             %Viewport{left: -5.0, top: 10.0, width: 20.0, scale: 50.0}
  end

  test "the fitted viewBox is a nominal 1000 units wide" do
    viewport = Viewport.fit({0.0, 0.0, 10.0, 10.0}, padding: 0.0, aspect: 1.0)
    assert Viewport.view_box(viewport, 1.0) == {0.0, 0.0, 1000.0, 1000.0}

    viewport = Viewport.fit({0.0, 0.0, 10.0, 10.0}, aspect: 0.75)
    assert Viewport.view_box(viewport, 0.75) == {0.0, 0.0, 1000.0, 750.0}
  end

  test "fit/2 handles nil and degenerate bounds" do
    assert Viewport.fit(nil) == %Viewport{left: -1.0, top: 1.0, width: 2.0, scale: 500.0}

    # A single point gets a 2 x 2 box centred on it.
    assert Viewport.fit({1.0, 2.0, 1.0, 2.0}, padding: 0.0, aspect: 1.0) ==
             %Viewport{left: 0.0, top: 3.0, width: 2.0, scale: 500.0}
  end

  test "project/2 flips y and view_box/2 carries the aspect" do
    vp = %Viewport{left: 0.0, top: 10.0, width: 10.0, scale: 2.0}

    assert Viewport.project(vp, {0.0, 0.0}) == {0.0, 20.0}
    assert Viewport.project(vp, {10.0, 10.0}) == {20.0, 0.0}
    assert Viewport.view_box(vp, 0.75) == {0.0, 0.0, 20.0, 15.0}
  end
end

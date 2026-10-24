defmodule GirihelixWeb.Workbench.RunTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Run

  test "compact/1 keeps the draw's state and drops the construction's" do
    step = %Steps.Step{
      id: :weld,
      label: "weld the feature maps",
      doc: "Welds the feature maps.",
      run: &Function.identity/1,
      source: {__ENV__.file, __ENV__.line}
    }

    state = %{
      tiling: :tiling,
      translations: [:t1],
      map: :map,
      failure: nil,
      bindings: [:b],
      feature_maps: %{1 => 2},
      binder: :binder,
      region: :region
    }

    assert [compact] = Run.compact([%Steps.Frame{index: 3, step: step, state: state}])

    # Everything a draw, a row or the viewport reads survives; the construction's
    # intermediates do not, because no cached frame is ever rebuilt.
    assert compact.state == %{tiling: :tiling, translations: [:t1], map: :map, failure: nil}
    assert compact.index == 3
    assert compact.step == step
  end
end

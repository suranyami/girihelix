defmodule GirihelixWeb.Workbench.Components.ControlsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias GirihelixWeb.Workbench.Components.Controls
  alias GirihelixWeb.Workbench.Param

  test "controls render a range per number and a select per enum" do
    params = [
      %Param{name: :n, type: :integer, range: 3..24, step: 1, default: 8, doc: "order"},
      %Param{
        name: :shape,
        type: :enum,
        options: [:square, :triangle],
        default: :square,
        doc: "shape"
      }
    ]

    html = render_component(&Controls.controls/1, params: params, values: %{n: 8, shape: :square})

    assert html =~ ~s(type="range")
    assert html =~ ~s(name="n")
    assert html =~ ~s(min="3")
    assert html =~ ~s(phx-change="params")
    assert html =~ ~s(name="shape")
  end

  test "controls render a float range with its step and value" do
    params = [
      %Param{name: :d, type: :float, range: 1..10, step: 0.1, default: 3.0, doc: "depth"}
    ]

    html = render_component(&Controls.controls/1, params: params, values: %{d: 7.5})

    assert html =~ ~s(name="d")
    assert html =~ ~s(min="1")
    assert html =~ ~s(max="10")
    assert html =~ ~s(step="0.1")
    assert html =~ ~s(value="7.5")
    assert html =~ ">7.5</span>"
  end

  test "controls render a boolean select and fall back to the declared default" do
    params = [
      %Param{name: :closed, type: :boolean, default: true, doc: "closed"}
    ]

    html = render_component(&Controls.controls/1, params: params, values: %{})

    assert html =~ ~s(name="closed")
    assert html =~ ~s(<option selected value="true">)
  end
end

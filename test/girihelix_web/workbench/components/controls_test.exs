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

  test "controls render a checked boolean checkbox from the declared default" do
    params = [
      %Param{name: :closed, type: :boolean, default: true, doc: "closed"}
    ]

    html = render_component(&Controls.controls/1, params: params, values: %{})

    assert html =~ ~s(name="closed")
    assert html =~ ~s(type="checkbox")
    assert html =~ ~s(type="hidden" name="closed" value="false")
    assert html =~ ~s(checked)
  end

  test "the palette control renders one swatch row per combination and checks the selected one" do
    param = %Param{
      name: :palette,
      type: :palette,
      options: [:"1", :"253"],
      default: :"253",
      doc: "Wada combination"
    }

    html = render_component(&Controls.controls/1, params: [param], values: %{palette: :"253"})
    fragment = LazyHTML.from_fragment(html)

    assert Enum.count(LazyHTML.query(fragment, ~s(input[type="radio"]))) == 2

    assert LazyHTML.attribute(LazyHTML.query(fragment, ~s(input[type="radio"][checked])), "value") ==
             ["253"]

    assert html =~ "background-color: #de4500"
    assert html =~ "background-color: #340059"

    legend = LazyHTML.text(LazyHTML.query(fragment, "legend"))
    assert legend =~ "palette"
    assert legend =~ "Wada combination"
    # The legend names the fieldset itself, so it carries no dangling `for`.
    assert Enum.empty?(LazyHTML.query(fragment, ~s(label[for="palette"])))
  end

  test "an unknown palette option renders a row with no swatches" do
    param = %Param{name: :palette, type: :palette, options: [:"9999"], default: :"9999"}

    html = render_component(&Controls.controls/1, params: [param], values: %{palette: :"9999"})
    fragment = LazyHTML.from_fragment(html)

    assert LazyHTML.attribute(LazyHTML.query(fragment, ~s(input[type="radio"][checked])), "value") ==
             ["9999"]

    assert Enum.empty?(LazyHTML.query(fragment, "[style]"))
    refute html =~ "background-color"
  end

  test "a boolean renders a checkbox that sends false when cleared" do
    param = %Param{name: :tiles, type: :boolean, default: false, doc: "overlay"}
    html = render_component(&Controls.controls/1, params: [param], values: %{tiles: false})

    assert html =~ ~s(type="checkbox")
    assert html =~ ~s(type="hidden" name="tiles" value="false")
    assert html =~ ~r/type="hidden" name="tiles" value="false".*type="checkbox"/s
    refute html =~ ~s(checked)
  end
end

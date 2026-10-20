defmodule GirihelixWeb.Workbench.Components.TransportTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Components.Transport

  test "transport shows the controls and the current step" do
    step = %Steps.Step{
      id: :build,
      label: "build",
      doc: "Build it.",
      run: & &1,
      source: {"lib/x.ex", 1}
    }

    html = render_component(&Transport.transport/1, index: 1, count: 3, step: step, failure: nil)
    assert html =~ ~s(phx-value-to="next")
    assert html =~ "build"
    assert html =~ "Build it."
    assert html =~ ~s(max="2")
  end

  test "transport offers every transport control" do
    html = render_component(&Transport.transport/1, index: 1, count: 3, step: nil, failure: nil)

    for to <- ~w(first prev next last) do
      assert html =~ ~s(phx-click="go")
      assert html =~ ~s(phx-value-to="#{to}")
    end

    assert html =~ ~s(type="range")
    assert html =~ ~s(name="frame")
    assert html =~ ~s(phx-change="go")
    assert html =~ ~s(min="0")
    assert html =~ ~s(value="1")
  end

  test "frame zero is the parameters frame, with no step prose" do
    html = render_component(&Transport.transport/1, index: 0, count: 3, step: nil, failure: nil)

    assert html =~ "Parameters"
    refute html =~ "Build it."
    assert html =~ ~s(value="0")
  end

  test "a failure banner names the failing step and its exception message" do
    step = %Steps.Step{
      id: :build,
      label: "build",
      doc: "Build it.",
      run: & &1,
      source: {"lib/x.ex", 1}
    }

    failure = %Steps.Failure{
      frames: [],
      index: 1,
      step: step,
      exception: %RuntimeError{message: "boom"},
      stacktrace: []
    }

    html =
      render_component(&Transport.transport/1, index: 1, count: 3, step: step, failure: failure)

    assert html =~ "Step failed:"
    assert html =~ "build"
    assert html =~ "boom"
  end
end

defmodule GirihelixWeb.Workbench.Exhibits.LooseTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Exhibits.Loose

  # The task brief lists the last row's value as "false", but `near/3` compares
  # its tolerance against a **squared** distance: two points 1.0e-6 apart have a
  # squared distance of 1.0e-12, which is below 1.0e-10. The row therefore
  # computes to "true" — the fact the row exists to illustrate.
  @rows [
    {"tol/0", "1.0e-7"},
    {"tol2/0", "1.0e-10"},
    {"equals(1.0, 1.0 + 1.0e-8)", "true"},
    {"near(1.0e-8, 1.0e-7)", "true"},
    {"near two points 1.0e-6 apart, tolerance 1.0e-10", "true"}
  ]

  test "identifies itself and takes no parameters" do
    assert Loose.slug() == "loose"
    assert Loose.category() == :geometry
    assert Loose.params() == []

    assert Loose.title() != ""
    assert Loose.summary() != ""
    assert Loose.reproduce(%{}) != ""
  end

  test "starts empty and runs one identity build step" do
    assert Loose.initial(%{}) == %{}
    assert [%Steps.Step{id: :build} = step] = Loose.steps(%{})
    assert step.run.(:anything) == :anything
  end

  test "draws the tolerance table from every frame" do
    frames = Steps.run!(Loose.steps(%{}), Loose.initial(%{}))

    assert Enum.map(frames, &Loose.draw(&1, %{})) ==
             [{:panel, @rows}, {:panel, @rows}]
  end
end

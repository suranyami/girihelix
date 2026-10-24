defmodule Girihelix.Engine.StepsTest do
  use ExUnit.Case, async: true

  import Girihelix.Engine.Steps

  alias Girihelix.Engine.Steps
  alias Girihelix.Engine.Steps.Failure

  @this_file __ENV__.file

  defp steps do
    [
      step(:double, "double", "multiply the counter by two", fn s ->
        Map.update!(s, :n, &(&1 * 2))
      end),
      step(:add_one, "add one", "add one to the counter", fn s ->
        Map.update!(s, :n, &(&1 + 1))
      end)
    ]
  end

  defp boom do
    step(:boom, "boom", "always raises", fn _ -> raise "nope" end)
  end

  test "run/3 returns one frame per step, plus frame zero" do
    assert {:ok, frames} = Steps.run(steps(), %{n: 1})
    assert length(frames) == 3
    assert Enum.map(frames, & &1.index) == [0, 1, 2]
  end

  test "frame zero carries the initial state and no step" do
    assert {:ok, [first | _]} = Steps.run(steps(), %{n: 1})
    assert first.step == nil
    assert first.state == %{n: 1}
  end

  test "final/1 is the state after the last step" do
    assert {:ok, frames} = Steps.run(steps(), %{n: 1})
    assert Steps.final(frames) == %{n: 3}
  end

  test "at/2 indexes a frame and returns nil past the end" do
    assert {:ok, frames} = Steps.run(steps(), %{n: 1})
    assert Steps.at(frames, 1).step.id == :double
    assert Steps.at(frames, 2).state == %{n: 3}
    assert Steps.at(frames, 99) == nil
  end

  test "a raising step returns a Failure naming the step, keeping prior frames" do
    assert {:error, %Failure{} = failure} =
             Steps.run(steps() ++ [boom()], %{n: 1})

    assert failure.step.id == :boom
    assert failure.index == 3
    assert length(failure.frames) == 3
    assert Exception.message(failure.exception) == "nope"
    assert is_list(failure.stacktrace)
  end

  test "run!/3 re-raises the original exception unchanged" do
    assert_raise RuntimeError, "nope", fn -> Steps.run!([boom()], %{n: 1}) end
  end

  test "step/4 records the file and line of its call site" do
    assert {:ok, [_, frame | _]} = Steps.run(steps(), %{n: 1})
    assert {file, line} = frame.step.source
    assert file == @this_file
    assert is_integer(line) and line > 0
  end

  test "on_step sees every built frame except frame zero" do
    parent = self()

    steps = [
      Steps.step(:one, "one", "first", fn state -> state + 1 end),
      Steps.step(:two, "two", "second", fn state -> state * 2 end)
    ]

    notify = fn frame -> send(parent, {:step, frame.index, frame.step.id, frame.state}) end
    assert {:ok, frames} = Steps.run(steps, 1, on_step: notify)
    assert length(frames) == 3
    assert_received {:step, 1, :one, 2}
    assert_received {:step, 2, :two, 4}
    refute_received {:step, 0, _, _}
  end

  test "on_step is not called for a step that raised" do
    parent = self()
    notify = fn frame -> send(parent, {:step, frame.index}) end

    assert {:error, %Failure{}} = Steps.run(steps() ++ [boom()], %{n: 1}, on_step: notify)
    assert_received {:step, 1}
    assert_received {:step, 2}
    refute_received {:step, 3}
  end

  test "max_frames caps the frames returned, including frame zero" do
    ticks = List.duplicate(step(:tick, "tick", "no-op", &Function.identity/1), 10)
    assert {:ok, frames} = Steps.run(ticks, %{n: 1}, max_frames: 4)
    assert length(frames) == 4
    assert Steps.final(frames) == %{n: 1}
  end
end

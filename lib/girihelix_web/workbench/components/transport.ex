defmodule GirihelixWeb.Workbench.Components.Transport do
  @moduledoc """
  Moves through a run's frames and states the step that built the current one.

  The controls are live, not links: every button sends `phx-click="go"` with a
  `phx-value-to` of `first`, `prev`, `next` or `last`, and the range input sends
  `phx-change="go"` under the name `frame`. The LiveView owns the meaning of
  those values; this component owns only their markup.

  Frame zero is the parameters themselves, so `step` is `nil` there and the
  component says "Parameters" instead of prose. When a step raised, `failure`
  carries the failing step and its exception, and the banner names both — the
  frame still on screen is the last one that built.
  """

  use GirihelixWeb, :html

  alias Girihelix.Engine.Steps

  attr :index, :integer, required: true, doc: "The current frame index."
  attr :count, :integer, required: true, doc: "The number of frames, frame zero included."

  attr :step, :any,
    default: nil,
    doc: "The step that built the current frame, or `nil` at frame zero."

  attr :failure, :any,
    default: nil,
    doc: "The `%Steps.Failure{}` when a step raised, or `nil`."

  def transport(assigns) do
    ~H"""
    <div class="flex flex-col gap-4">
      <p :if={@failure} role="alert" class="alert alert-error">
        Step failed: {@failure.step.label} — {Exception.message(@failure.exception)}
      </p>

      <div class="flex flex-wrap items-center gap-2">
        <button type="button" class="btn btn-sm" phx-click="go" phx-value-to="first">First</button>
        <button type="button" class="btn btn-sm" phx-click="go" phx-value-to="prev">Prev</button>
        <input
          type="range"
          name="frame"
          phx-change="go"
          min="0"
          max={@count - 1}
          value={@index}
          class="range range-sm"
          aria-label="Frame"
        />
        <button type="button" class="btn btn-sm" phx-click="go" phx-value-to="next">Next</button>
        <button type="button" class="btn btn-sm" phx-click="go" phx-value-to="last">Last</button>
      </div>

      <div class="min-h-16">
        <.step_summary step={@step} />
      </div>
    </div>
    """
  end

  attr :step, :any, required: true

  defp step_summary(%{step: nil} = assigns) do
    ~H"""
    <p class="text-sm opacity-70">Parameters</p>
    """
  end

  defp step_summary(%{step: %Steps.Step{}} = assigns) do
    ~H"""
    <p class="text-sm">
      <span class="font-semibold">{@step.label}</span>
      <span class="opacity-70">{@step.doc}</span>
    </p>
    """
  end
end

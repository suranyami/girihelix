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

  While a run is still building there is no frame to move through, so the
  component takes its loading form: the failure banner, if any, and a
  `#run-progress` status naming the step in flight and its `index/total`. That
  form reserves at least the finished form's height (its buttons and step
  summary), so a header carrying the transport does not grow when the run lands.
  The frame controls return as soon as the run completes.
  """

  use GirihelixWeb, :html

  alias Girihelix.Engine.Steps

  attr :index, :any, required: true, doc: "The current frame index, or `nil` while loading."

  attr :count, :any,
    required: true,
    doc: "The number of frames, frame zero included, or `nil` while loading."

  attr :step, :any,
    default: nil,
    doc: "The step that built the current frame, or `nil` at frame zero."

  attr :failure, :any,
    default: nil,
    doc: "The `%Steps.Failure{}` when a step raised, or `nil`."

  attr :loading, :boolean,
    default: false,
    doc: "Whether the run is still building, which replaces the controls with progress."

  attr :progress, :any,
    default: nil,
    doc: "The step in flight as `{index, total, label}`, or `nil` before the first step."

  @spec transport(map()) :: Phoenix.LiveView.Rendered.t()
  def transport(%{index: nil} = assigns) do
    ~H"""
    <div class="flex min-h-28 flex-col gap-4">
      <p :if={@failure} role="alert" class="alert alert-error">
        Step failed: {@failure.step.label} — {Exception.message(@failure.exception)}
      </p>

      <div :if={@loading} id="run-progress" role="status" class="flex items-center gap-3 text-sm">
        <span class="loading loading-spinner loading-sm"></span>
        <span>{progress_text(@progress)}</span>
      </div>
    </div>
    """
  end

  def transport(assigns) do
    ~H"""
    <div class="flex flex-col gap-4">
      <p :if={@failure} role="alert" class="alert alert-error">
        Step failed: {@failure.step.label} — {Exception.message(@failure.exception)}
      </p>

      <div class="flex flex-wrap items-center gap-2">
        <button type="button" class="btn btn-sm" phx-click="go" phx-value-to="first">First</button>
        <button type="button" class="btn btn-sm" phx-click="go" phx-value-to="prev">Prev</button>
        <form id="frame-form" phx-change="go">
          <input
            type="range"
            name="frame"
            min="0"
            max={@count - 1}
            value={@index}
            class="range range-sm"
            aria-label="Frame"
          />
        </form>
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

  # Before the first step there is no label yet, so the status still says what
  # the page is doing rather than rendering an empty line.
  defp progress_text(nil), do: "Preparing the run…"
  defp progress_text({index, total, label}), do: "#{label} — #{index}/#{total}"
end

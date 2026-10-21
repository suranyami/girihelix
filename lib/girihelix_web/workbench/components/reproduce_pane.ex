defmodule GirihelixWeb.Workbench.Components.ReproducePane do
  @moduledoc """
  Shows the call that yields the current frame, with the frame's index.

  The snippet is the exhibit's `reproduce/1` result for this frame's
  parameters: a fully qualified call a reader can paste into `iex -S mix`. The
  frame index is shown beside it, because the same parameters can yield a later
  frame and the reader needs to know which one the snippet names.

  The copy button carries the snippet in `data-copy` and dispatches `phx:copy`
  with `JS.dispatch/1`. A window listener in `app.js` reads `data-copy` from the
  event's target and writes it to the clipboard, which keeps the snippet out of
  an attribute-only mechanism such as a hidden input and works for every pane
  that wants the same button.
  """

  use GirihelixWeb, :html

  attr :snippet, :string, required: true, doc: "The call that yields this frame."
  attr :index, :integer, required: true, doc: "The current frame index."

  @spec reproduce_pane(map()) :: Phoenix.LiveView.Rendered.t()
  def reproduce_pane(assigns) do
    ~H"""
    <section class="flex flex-col gap-3">
      <div class="flex items-center justify-between gap-2">
        <p class="text-sm font-semibold">frame {@index}</p>
        <button
          type="button"
          class="btn btn-sm"
          data-copy={@snippet}
          phx-click={JS.dispatch("phx:copy")}
        >
          Copy
        </button>
      </div>
      <pre id="reproduce" class="overflow-x-auto rounded-box bg-base-200 p-3 text-xs"><code>{@snippet}</code></pre>
    </section>
    """
  end
end

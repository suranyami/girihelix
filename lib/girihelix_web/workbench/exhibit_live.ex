defmodule GirihelixWeb.Workbench.ExhibitLive do
  @moduledoc """
  One exhibit: a header row carrying the transport, the picture, the controls and
  the panel, and the source and reproduction behind one collapsed disclosure.

  **The URL is the state.** The slug chooses the exhibit, the declared
  parameters travel in their own query keys, and `frame` names the index into
  the run's frames. `handle_params/3` derives every assign from those strings,
  so a reload, a shared link and a `push_patch` all go through the same path and
  cannot disagree with each other.

  Omitting `frame` means the last frame, which is what makes a parameter change
  — patched without a `frame` key — land on the finished picture. The transport
  includes `frame`, so moving through a run is itself linkable.

  **A failure is a frame too.** A run that raises still has the frames that
  built; the last one is drawn and the failure goes to the transport's banner.
  The source pane then points at the step that failed rather than at frame
  zero's parameters, because that is the line a reader wants to see.

  The viewport comes from the exhibit when it pins one, and otherwise fits the
  current drawing's bounds. A pinned viewport is asked for the run's frames, so
  it can be anchored on the finished map rather than on the frame being drawn. A
  panel has no ops, so it fits the empty view; the canvas ignores a panel's
  viewport.

  **A run is a task; a frame is not.** Building a run can take minutes for a
  heavy tiling, so `handle_params/3` starts it with `start_async/3` and renders
  the finished page's skeleton — the same header, grid and controls — with the
  previous picture still on screen or an empty framed canvas when there is none.
  The task reports
  each step to this process as `{:run_progress, index, total, label}`. Moving
  through the frames of the run it already holds never starts a task: the URL's
  parameters name the run, the assigned `:run_key` says whether they still do,
  and `Run.view/4` redraws a frame from the frames in hand.

  A superseded run is cancelled rather than left to finish unseen, and an
  unexpected task exit clears the loading state with a generic failure.
  """

  use GirihelixWeb, :live_view

  import GirihelixWeb.Workbench.Components.Canvas, only: [canvas: 1, panel: 1]
  import GirihelixWeb.Workbench.Components.Controls, only: [controls: 1]
  import GirihelixWeb.Workbench.Components.ReproducePane, only: [reproduce_pane: 1]
  import GirihelixWeb.Workbench.Components.SourcePane, only: [source_pane: 1]
  import GirihelixWeb.Workbench.Components.Transport, only: [transport: 1]

  alias GirihelixWeb.Workbench.NotFound
  alias GirihelixWeb.Workbench.Param
  alias GirihelixWeb.Workbench.Registry
  alias GirihelixWeb.Workbench.Run
  alias Phoenix.LiveView.Socket

  @impl true
  @spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
  def mount(_params, _session, socket) do
    # The run's fields are assigned here so the loading render is total before
    # the first task exists. `handle_params/3` then preserves the previous
    # drawing while a new run builds.
    {:ok,
     assign(socket,
       frames: nil,
       failure: nil,
       index: nil,
       count: nil,
       step: nil,
       drawing: nil,
       viewport: nil,
       source: {:error, :no_step},
       snippet: nil,
       cells: nil,
       loading: false,
       progress: nil,
       run_key: nil,
       requested_frame: nil
     )}
  end

  @impl true
  @spec handle_params(map(), String.t(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_params(%{"slug" => slug} = params, _uri, socket) do
    exhibit = fetch!(slug)
    param_defs = exhibit.params()
    values = Param.decode(param_defs, params)
    run_key = {slug, values}
    previous_key = socket.assigns.run_key
    requested = params["frame"]

    socket =
      assign(socket,
        exhibit: exhibit,
        values: values,
        param_defs: param_defs,
        run_key: run_key,
        requested_frame: requested,
        page_title: exhibit.title(),
        groups: Registry.grouped()
      )

    {:noreply, continue(socket, previous_key, run_key, requested)}
  end

  @impl true
  @spec handle_async(:run, {:ok, map()} | {:exit, term()}, Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_async(:run, {:ok, result}, socket) do
    {:noreply, socket |> assign(result) |> assign(loading: false, progress: nil)}
  end

  def handle_async(:run, {:exit, reason}, socket) do
    # The previous picture belongs to a run this task was replacing, so it must
    # not stand beside a failure that has no frames; clear everything the page
    # would otherwise attribute to the failed run.
    {:noreply,
     assign(socket,
       loading: false,
       progress: nil,
       failure: Run.generic_failure(reason),
       frames: nil,
       index: nil,
       count: nil,
       step: nil,
       drawing: nil,
       viewport: nil,
       source: {:error, :no_step}
     )}
  end

  @impl true
  @spec handle_info({:run_progress, non_neg_integer(), non_neg_integer(), String.t()}, Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_info({:run_progress, index, total, label}, %{assigns: %{loading: true}} = socket) do
    {:noreply, assign(socket, progress: {index, total, label})}
  end

  # A message from a superseded run can still be in the mailbox after its task
  # is cancelled; it must not overwrite the run that replaced it.
  def handle_info({:run_progress, _index, _total, _label}, socket), do: {:noreply, socket}

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) ::
          {:noreply, Socket.t()}
  # A transport event can race a parameter patch that has just cleared the run;
  # there is no run to move through until the new one completes.
  def handle_event("go", %{"to" => _to}, %{assigns: %{count: count}} = socket) when not is_integer(count) do
    {:noreply, socket}
  end

  def handle_event("go", %{"to" => to}, socket) do
    {:noreply, patch_frame(socket, target(to, socket.assigns.index, socket.assigns.count))}
  end

  def handle_event("go", %{"frame" => raw}, socket) do
    case parse_frame(raw) do
      {:ok, index} -> {:noreply, patch_frame(socket, index)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("params", params, socket) do
    values = Param.decode(socket.assigns.param_defs, params)
    # No `frame` key: the patch lands on the last frame, as a fresh run should.
    query = Param.encode(socket.assigns.param_defs, values)

    {:noreply, push_patch(socket, to: ~p"/workbench/#{socket.assigns.exhibit.slug()}?#{query}")}
  end

  # A run in flight has no frame index yet, but the page it renders has the same
  # header, grid and controls as a finished one. The canvas slot keeps the
  # previous picture when there is one and an empty framed canvas otherwise. When
  # the previous drawing filled the right column, that panel is already there with
  # `n/a` values and the previous run's labels; otherwise a placeholder box of the
  # panel's height stands in. Either way, nothing below the header moves when the
  # run lands.
  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(%{index: nil} = assigns) do
    assigns =
      assign(assigns,
        plot: assigns.drawing || {:canvas, []},
        panel_rows: placeholder_rows(assigns.drawing),
        transcript_index: 0,
        transcript_snippet: assigns.snippet || "Preparing the run…"
      )

    page(assigns)
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        plot: assigns.drawing,
        panel_rows: drawing_panel_rows(assigns.drawing),
        transcript_index: assigns.index,
        transcript_snippet: assigns.snippet
      )

    page(assigns)
  end

  # Both render heads reach the same block structure: one header row carrying
  # the transport, the picture in the flexible column, the controls and then the
  # panel in the right column, and the code behind one collapsed disclosure.
  defp page(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      wide
      nav_groups={@groups}
      nav_active={@exhibit.category()}
      nav_slug={@exhibit.slug()}
    >
      <div class="flex flex-col gap-2">
        <header class="flex flex-col gap-2 lg:flex-row lg:items-start lg:justify-between">
          <div class="flex min-w-0 flex-col gap-1">
            <h1 class="text-xl font-semibold">{@exhibit.title()}</h1>
            <p class="text-sm italic opacity-70">{@exhibit.byline()}</p>
            <p class="text-sm opacity-70">{@exhibit.summary()}</p>
          </div>

          <section id="transport" class="min-w-0 shrink-0">
            <.transport
              index={@index}
              count={@count}
              step={@step}
              failure={@failure}
              loading={@loading}
              progress={@progress}
            />
          </section>
        </header>

        <div class="flex flex-col gap-2 lg:flex-row xl:items-start">
          <section id="picture" class="min-w-0 flex-1">
            <.canvas drawing={@plot} viewport={@viewport} />
          </section>

          <aside class="flex w-80 shrink-0 flex-col gap-2">
            <.controls params={@param_defs} values={@values} />
            <.panel :if={@panel_rows != []} rows={@panel_rows} />
            <div
              :if={@loading and @panel_rows == []}
              id="panel-placeholder"
              aria-hidden="true"
              class="min-h-64 rounded-box border border-base-300"
            >
            </div>
          </aside>
        </div>

        <details class="border-t border-base-300 pt-2">
          <summary class="cursor-pointer text-sm font-semibold">
            Show source and reproduce
          </summary>
          <div class="mt-2 flex flex-col gap-2 lg:flex-row xl:items-start">
            <div class="min-w-0 flex-1"><.source_pane source={@source} /></div>
            <div class="w-80 shrink-0">
              <.reproduce_pane snippet={@transcript_snippet} index={@transcript_index} />
            </div>
          </div>
        </details>
      </div>
    </Layouts.app>
    """
  end

  # The right column's panel belongs to a `:both` drawing; a `:panel` drawing's
  # table is the picture itself and stays in the main column.
  defp drawing_panel_rows({:both, _ops, rows}), do: rows
  defp drawing_panel_rows(_drawing), do: []

  # While a run builds, the previous frame's labels are the skeleton for the
  # rows it will replace, so the right column does not change height.
  defp placeholder_rows({:both, _ops, rows}) do
    Enum.map(rows, fn {label, _value} -> {label, "n/a"} end)
  end

  defp placeholder_rows(_drawing), do: []

  defp fetch!(slug) do
    case Registry.get(slug) do
      {:ok, exhibit} -> exhibit
      {:error, :unknown_exhibit} -> raise NotFound
    end
  end

  defp parse_frame(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {index, ""} -> {:ok, index}
      _partial -> :error
    end
  end

  defp parse_frame(_raw), do: :error

  defp clamp(index, count), do: index |> max(0) |> min(count - 1)

  # The same parameters name the run already in hand: redraw one of its frames
  # and start nothing.
  defp continue(%{assigns: %{frames: frames}} = socket, key, key, requested) when is_list(frames) do
    reuse(socket, requested)
  end

  # New parameters: supersede any run in flight and build this one in a task.
  defp continue(socket, _previous_key, _run_key, requested), do: start_run(socket, requested)

  defp reuse(socket, requested) do
    values = Map.put(socket.assigns.values, :cells, socket.assigns.cells)
    index = Run.index(requested, length(socket.assigns.frames))

    socket
    |> assign(
      Run.view(socket.assigns.frames, socket.assigns.failure, index, %{
        exhibit: socket.assigns.exhibit,
        values: values
      })
    )
    |> assign(loading: false, progress: nil, requested_frame: requested)
  end

  defp start_run(socket, requested) do
    exhibit = socket.assigns.exhibit
    values = socket.assigns.values
    parent = self()

    socket
    |> assign(
      loading: true,
      progress: nil,
      index: nil,
      # A run in flight has no frames yet. Clearing these is what stops a
      # same-key patch during the run from reusing the previous run's frames,
      # which no longer belong to the assigned `run_key`.
      frames: nil,
      count: nil,
      requested_frame: requested
    )
    |> cancel_async(:run)
    |> start_async(:run, fn -> run_task(exhibit, values, requested, parent) end)
  end

  # The task body. The step count is the same for the probe and the run that
  # follows it, so one total serves every `:run_progress` message.
  defp run_task(exhibit, values, requested, parent) do
    total = length(exhibit.steps(values))
    on_step = fn frame -> send(parent, {:run_progress, frame.index, total, frame.step.label}) end

    Run.build(exhibit, values, requested, on_step)
  end

  defp target(_to, nil, _count), do: 0
  defp target("first", _index, _count), do: 0
  defp target("prev", index, _count), do: index - 1
  defp target("next", index, _count), do: index + 1
  defp target("last", _index, count), do: count - 1
  defp target(_unknown, index, _count), do: index

  # A frame control before the first run has finished has no run to move
  # through; it is a no-op rather than a crash.
  defp patch_frame(%{assigns: %{count: count}} = socket, _index) when not is_integer(count), do: socket

  defp patch_frame(%{assigns: %{count: count}} = socket, _index) when count == 0, do: socket

  defp patch_frame(socket, index) do
    # A string handed to `~p`'s query slot is itself URL-encoded, so the map is
    # passed whole and the sigil performs the `URI.encode_query/1` step.
    query =
      socket.assigns.param_defs
      |> Param.encode(socket.assigns.values)
      |> Map.put("frame", index |> clamp(socket.assigns.count) |> Integer.to_string())

    push_patch(socket, to: ~p"/workbench/#{socket.assigns.exhibit.slug()}?#{query}")
  end
end

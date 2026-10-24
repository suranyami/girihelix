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

  **One construction, shared.** A run keyed by an exhibit's `construct_key/1`
  goes through `ConstructCache`, so the construction is built once — across
  style, palette and `tiles` changes and across users — and later requests read
  it from memory or disk. An exhibit without a construct key is never cached.

  **The paint phase.** A `Filled` draw needs the map's face colouring, and
  extracting it is expensive even when the construction is free. The colouring
  is therefore cached in the entry and injected into the draw's params as
  `:cached_faces`; when the entry holds none, the LiveView computes it in a
  second task and paints when it lands, so `handle_params/3` never blocks on it.
  """

  use GirihelixWeb, :live_view

  import GirihelixWeb.Workbench.Components.Canvas, only: [canvas: 1, panel: 1]
  import GirihelixWeb.Workbench.Components.Controls, only: [controls: 1]
  import GirihelixWeb.Workbench.Components.ReproducePane, only: [reproduce_pane: 1]
  import GirihelixWeb.Workbench.Components.SourcePane, only: [source_pane: 1]
  import GirihelixWeb.Workbench.Components.Transport, only: [transport: 1]

  alias Girihelix.Engine.Faces
  alias GirihelixWeb.Workbench.ConstructCache
  alias GirihelixWeb.Workbench.Exhibit
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
       cached_faces: nil,
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
    # A cacheable exhibit's identity is its construct key, so a parameter that
    # only changes the drawing keeps this key and redraws the frames in hand.
    run_key = {slug, Exhibit.construct_key(exhibit, values) || values}
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
  def handle_async(:run, {:ok, %{frames: frames, failure: failure, cells: cells} = construct}, socket) do
    requested = socket.assigns.requested_frame

    socket =
      assign(socket,
        cached_faces: faces_of(construct),
        frames: frames,
        failure: failure,
        cells: cells
      )

    {:noreply, show_frames(socket, frames, failure, cells, requested)}
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
       cached_faces: nil,
       index: nil,
       count: nil,
       step: nil,
       drawing: nil,
       viewport: nil,
       source: {:error, :no_step}
     )}
  end

  @impl true
  @spec handle_async(:faces, {:ok, term()} | {:exit, term()}, Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_async(:faces, {:ok, {run_key, faces}}, %{assigns: %{run_key: run_key}} = socket) do
    :ok = ConstructCache.update_faces(ConstructCache, run_key, faces)

    {:noreply, socket |> assign(cached_faces: faces) |> redraw_cached()}
  end

  # A result from a superseded phase carries another run's key, and must neither
  # be assigned to this page nor written to the cache under the current key. An
  # exit cannot be attributed at all, so it is treated the same way; the task
  # folds its own failures into the result tuple, so only a kill reaches here.
  def handle_async(:faces, _superseded_or_unattributed, socket), do: {:noreply, socket}

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
            <.canvas drawing={@plot} viewport={@viewport} canvas_key={@exhibit.slug()} />
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

  # Another exhibit: the picture in hand belongs to the old one, so it must not
  # sit under the new title while this run builds.
  defp continue(socket, {previous_slug, _}, {slug, _}, requested) when previous_slug != slug do
    start_run(socket, requested, :new_exhibit)
  end

  # New parameters for the same exhibit: keep the previous picture on screen as
  # the skeleton, as before.
  defp continue(socket, _previous_key, _run_key, requested), do: start_run(socket, requested, :same_exhibit)

  # A `Filled` draw still needs the cached face colouring, which `show_frames/5`
  # computes off the render path when it is missing.
  defp reuse(socket, requested) do
    show_frames(
      socket,
      socket.assigns.frames,
      socket.assigns.failure,
      socket.assigns.cells,
      requested
    )
  end

  # The face colouring is part of a `Filled` draw, and extracting it can take
  # seconds on a heavy map. When the cache holds none, a second task computes it
  # and paints only when it lands, so no render blocks on the extraction.
  defp show_frames(socket, frames, failure, cells, requested) do
    show_frames(needs_faces?(socket, frames), socket, frames, failure, cells, requested)
  end

  defp show_frames(true, socket, frames, failure, cells, requested) do
    start_faces(socket, frames, failure, cells, requested)
  end

  defp show_frames(false, socket, frames, failure, cells, requested) do
    draw_frames(socket, frames, failure, cells, requested)
  end

  defp needs_faces?(socket, frames) do
    faces_phase?(
      Exhibit.construct_key(socket.assigns.exhibit, socket.assigns.values),
      socket.assigns.cached_faces,
      Map.get(socket.assigns.values, :style),
      frames
    )
  end

  # An exhibit without a construct key is never cached, so it has no entry to
  # store a colouring in; its `Filled` draw extracts as it always did.
  defp faces_phase?(nil, _faces, _style, _frames), do: false
  defp faces_phase?(_key, nil, :filled, frames), do: is_map(faces_map(frames))
  defp faces_phase?(_key, _faces, _style, _frames), do: false

  defp faces_map([]), do: nil

  defp faces_map(frames) do
    case List.last(frames) do
      %{state: %{map: map}} -> map
      _frame -> nil
    end
  end

  defp start_faces(socket, frames, failure, cells, requested) do
    map = faces_map(frames)
    # The result is tagged with its key, so a phase superseded by a construct
    # key change can never be written under the new key.
    run_key = socket.assigns.run_key

    socket
    |> assign(
      frames: frames,
      failure: failure,
      cells: cells,
      requested_frame: requested,
      loading: true,
      progress: {1, 1, "painting from the cached map"},
      index: nil,
      count: nil
    )
    |> start_async(:faces, fn -> {run_key, extract_faces(map)} end)
  end

  # `Faces.extract_faces/1` reports its own failures as tuples; a raise is folded
  # into one here, because an exit cannot carry the key the result belongs to.
  defp extract_faces(map) do
    Faces.extract_faces(map)
  rescue
    _exception -> {:error, :faces_unavailable}
  end

  defp draw_frames(socket, frames, failure, cells, requested) do
    values =
      socket.assigns.values
      |> Map.put(:cells, cells)
      |> Map.put(:cached_faces, socket.assigns.cached_faces)

    index = Run.index(requested, length(frames))

    socket
    |> assign(Run.view(frames, failure, index, %{exhibit: socket.assigns.exhibit, values: values}))
    |> assign(cells: cells, loading: false, progress: nil)
  end

  defp redraw_cached(%{assigns: %{frames: frames}} = socket) when is_list(frames) do
    show_frames(
      socket,
      frames,
      socket.assigns.failure,
      socket.assigns.cells,
      socket.assigns.requested_frame
    )
  end

  # A run in flight has no frames to redraw onto; the run's own result will.
  defp redraw_cached(socket), do: socket

  defp faces_of(%{faces: faces}), do: faces
  defp faces_of(_uncached_construct), do: nil

  # A run started for another exhibit clears the previous picture; a parameter
  # change on the same exhibit keeps it as the loading skeleton.
  defp start_run(socket, requested, mode) do
    exhibit = socket.assigns.exhibit
    values = socket.assigns.values
    run_key = socket.assigns.run_key
    parent = self()

    socket
    |> clear_picture(mode)
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
    |> cancel_async(:faces)
    |> start_async(:run, fn -> run_task(exhibit, values, run_key, parent) end)
  end

  defp clear_picture(socket, :new_exhibit), do: assign(socket, drawing: nil, viewport: nil)
  defp clear_picture(socket, :same_exhibit), do: socket

  # The task body. The step count is the same for the probe and the run that
  # follows it, so one total serves every `:run_progress` message. A cacheable
  # exhibit builds through the shared cache, so a second caller — including
  # another user's LiveView — waits for the one build and receives its entry.
  defp run_task(exhibit, values, run_key, parent) do
    total = length(exhibit.steps(values))
    on_step = fn frame -> send(parent, {:run_progress, frame.index, total, frame.step.label}) end

    case Exhibit.construct_key(exhibit, values) do
      nil ->
        Run.construct(exhibit, values, on_step)

      _key ->
        ConstructCache.fetch(ConstructCache, run_key, fn ->
          construct = Run.construct(exhibit, values, on_step)
          ConstructCache.entry(run_key, construct.frames, construct.failure, construct.cells)
        end)
    end
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

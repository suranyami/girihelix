defmodule GirihelixWeb.Workbench.ExhibitLive do
  @moduledoc """
  One exhibit, with its picture, controls, source and reproduction side by side.

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
  current drawing's bounds. A panel has no ops, so it fits the empty view; the
  canvas ignores a panel's viewport.
  """

  use GirihelixWeb, :live_view

  import GirihelixWeb.Workbench.Components.Canvas, only: [canvas: 1]
  import GirihelixWeb.Workbench.Components.Controls, only: [controls: 1]
  import GirihelixWeb.Workbench.Components.ReproducePane, only: [reproduce_pane: 1]
  import GirihelixWeb.Workbench.Components.SourcePane, only: [source_pane: 1]
  import GirihelixWeb.Workbench.Components.Transport, only: [transport: 1]

  alias Girihelix.Engine.Render.Bounds
  alias Girihelix.Engine.Render.Viewport
  alias Girihelix.Engine.Steps
  alias Girihelix.Engine.Steps.Failure
  alias Girihelix.Engine.Steps.Frame
  alias GirihelixWeb.Workbench.NotFound
  alias GirihelixWeb.Workbench.Param
  alias GirihelixWeb.Workbench.Registry
  alias GirihelixWeb.Workbench.Source
  alias Phoenix.LiveView.Socket

  # The same cap the workbench's runs use everywhere; a run longer than this is
  # a bug in the exhibit, not a page worth rendering.
  @max_frames 200

  @impl true
  @spec mount(map(), map(), Socket.t()) :: {:ok, Socket.t()}
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  @spec handle_params(map(), String.t(), Socket.t()) ::
          {:noreply, Socket.t()}
  def handle_params(%{"slug" => slug} = params, _uri, socket) do
    exhibit = fetch!(slug)
    param_defs = exhibit.params()
    values = Param.decode(param_defs, params)
    {frames, failure} = run(exhibit, values)
    count = length(frames)
    index = index(params["frame"], count)
    frame = frame_at(frames, index)
    drawing = draw(exhibit, frame, values)

    socket =
      assign(socket,
        exhibit: exhibit,
        values: values,
        param_defs: param_defs,
        index: index,
        count: count,
        step: frame_step(frame),
        failure: failure,
        drawing: drawing,
        viewport: viewport(exhibit, values, drawing),
        source: source(frame, failure),
        snippet: exhibit.reproduce(values),
        page_title: exhibit.title()
      )

    {:noreply, socket}
  end

  @impl true
  @spec handle_event(String.t(), map(), Socket.t()) ::
          {:noreply, Socket.t()}
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

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(%{index: nil} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} wide>
      <div class="flex flex-col gap-4">
        <.exhibit_header exhibit={@exhibit} />

        <p :if={@failure} role="alert" class="alert alert-error">
          Step failed: {@failure.step.label} — {Exception.message(@failure.exception)}
        </p>

        <div class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_22rem] lg:items-start">
          <div class="min-w-0"><.source_pane source={@source} /></div>
          <aside class="min-w-0">
            <.controls params={@param_defs} values={@values} />
          </aside>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} wide>
      <div class="flex flex-col gap-4">
        <.exhibit_header exhibit={@exhibit} />

        <p :if={@failure} role="alert" class="alert alert-error">
          Step failed: {@failure.step.label} — {Exception.message(@failure.exception)}
        </p>

        <section id="transport" class="min-w-0">
          <.transport index={@index} count={@count} step={@step} failure={@failure} />
        </section>

        <div class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_22rem] lg:items-start">
          <section id="picture" class="min-w-0">
            <.canvas drawing={@drawing} viewport={@viewport} />
          </section>

          <aside class="min-w-0">
            <.controls params={@param_defs} values={@values} />
          </aside>
        </div>

        <div class="grid gap-4 lg:grid-cols-[minmax(0,1fr)_22rem] lg:items-start">
          <div class="min-w-0"><.source_pane source={@source} /></div>
          <div class="min-w-0"><.reproduce_pane snippet={@snippet} index={@index} /></div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :exhibit, :atom, required: true

  defp exhibit_header(assigns) do
    ~H"""
    <header class="flex flex-col gap-1">
      <.link navigate={~p"/workbench"} class="text-sm opacity-70 hover:underline">
        &larr; Workbench
      </.link>
      <h1 class="text-2xl font-semibold">{@exhibit.title()}</h1>
      <p class="text-sm opacity-70">{@exhibit.summary()}</p>
    </header>
    """
  end

  defp fetch!(slug) do
    case Registry.get(slug) do
      {:ok, exhibit} -> exhibit
      {:error, :unknown_exhibit} -> raise NotFound
    end
  end

  defp run(exhibit, values) do
    case Steps.run(exhibit.steps(values), exhibit.initial(values), max_frames: @max_frames) do
      {:ok, frames} -> {frames, nil}
      {:error, %Failure{frames: frames} = failure} -> {frames, failure}
    end
  end

  defp index(_requested, 0), do: nil

  defp index(requested, count) do
    requested |> requested_index(count) |> clamp(count)
  end

  defp requested_index(requested, count) do
    case parse_frame(requested) do
      {:ok, index} -> index
      :error -> count - 1
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

  defp frame_at(_frames, nil), do: nil
  defp frame_at(frames, index), do: Enum.at(frames, index)

  defp frame_step(nil), do: nil
  defp frame_step(%Frame{step: step}), do: step

  defp draw(_exhibit, nil, _values), do: nil
  defp draw(exhibit, frame, values), do: exhibit.draw(frame, values)

  defp viewport(exhibit, values, drawing) do
    case pinned_viewport(exhibit, values) do
      %Viewport{} = viewport -> viewport
      :fit -> fitted(drawing)
    end
  end

  defp pinned_viewport(exhibit, values) do
    pinned_viewport(exhibit, values, exports_viewport?(exhibit))
  end

  # `function_exported?/3` reports false for a module that has not been loaded,
  # which would silently downgrade a pinned viewport to a fitted one. Loading
  # first makes the answer depend on the module, not on what happened to be
  # loaded already.
  defp exports_viewport?(exhibit) do
    Code.ensure_loaded?(exhibit) and function_exported?(exhibit, :viewport, 1)
  end

  defp pinned_viewport(exhibit, values, true), do: declared_viewport(exhibit.viewport(values))
  defp pinned_viewport(_exhibit, _values, false), do: :fit

  defp declared_viewport(%Viewport{} = viewport), do: viewport
  defp declared_viewport(_other), do: :fit

  # A panel drawing carries no ops, so it fits the empty view. The canvas
  # ignores that viewport; it is here because every drawing needs one.
  defp fitted({:canvas, ops}), do: Viewport.fit(Bounds.of_ops(ops))
  defp fitted({:both, ops, _rows}), do: Viewport.fit(Bounds.of_ops(ops))
  defp fitted(_drawing), do: Viewport.fit(nil)

  # Frame zero has no step of its own, so a failed run points the source pane
  # at the step that raised instead of at the parameters.
  defp source(%Frame{step: %Steps.Step{} = step}, _failure), do: Source.resolve(step)
  defp source(_frame, failure), do: Source.resolve(failure_step(failure))

  defp failure_step(%Failure{step: step}), do: step
  defp failure_step(nil), do: nil

  defp target(_to, nil, _count), do: 0
  defp target("first", _index, _count), do: 0
  defp target("prev", index, _count), do: index - 1
  defp target("next", index, _count), do: index + 1
  defp target("last", _index, count), do: count - 1
  defp target(_unknown, index, _count), do: index

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

defmodule GirihelixWeb.Workbench.Run do
  @moduledoc """
  Builds one exhibit's run and derives the page's view of one built frame.

  **A frame is the page's unit, not the run's.** The transport moves through
  the frames of a run that has already been built, so navigating a frame must
  never re-run the exhibit. `view/4` derives the same fields for one frame of
  an existing run; the LiveView calls it when the URL's parameters still name
  the run it holds, and starts a task only when they do not.

  **The patch span adapts to the tiling.** A run is first probed at one cell.
  The probe's final map is measured: above `@vertex_budget` the probe *is* the
  run and its frames are kept, so a heavy tiling pays for one small run rather
  than a large one. Otherwise the probe is discarded and the exhibit runs again
  at two cells, which is the shipped patch span. A probe that raised proves
  nothing about the span, so the run is repeated at two cells and the failure
  is reported from there.

  **A failure is a frame too.** A step that raises still has the frames that
  built; the run reports the last of them together with the `Steps.Failure`, so
  the page can draw what exists and point the source pane at the step that
  failed. An unexpected task exit is the one failure with no frames at all;
  `generic_failure/1` gives the page something to show for it.
  """

  alias Girihelix.Engine.PlanarMap
  alias Girihelix.Engine.Render.Bounds
  alias Girihelix.Engine.Render.Viewport
  alias Girihelix.Engine.Steps
  alias Girihelix.Engine.Steps.Failure
  alias Girihelix.Engine.Steps.Frame
  alias GirihelixWeb.Workbench.Source

  # The same cap the workbench's runs use everywhere; a run longer than this is
  # a bug in the exhibit, not a page worth rendering.
  @max_frames 200

  # A one-cell welded map above this many vertices is a heavy tiling. Calibrated
  # against the shipped catalogue with the rosette binder: 8.5's three-by-three
  # `patch_region/2` map has 1,392 vertices and must stay at two cells; 7.6
  # (4,321) and 6.5 flower (6,164) are above it and drop to one, as do 3-8-4-6
  # and Girih Star (full one-cell runs take about 90 s and 12 s). The plan's
  # figures (432 for 8.5, 1,257 for 7.6) are Task 4's
  # `Construct.default_region/1` baselines — a single unit cell — not
  # `patch_region(tiling, 1)`, which is a three-by-three patch. A 1,200 budget
  # would leave 8.5 at one cell, contrary to the mandated behaviour.
  @vertex_budget 2_000

  @typedoc """
  The context `view/4` needs: the exhibit that draws and the run's values.

  The values carry the chosen `:cells` span, so the drawn viewport matches the
  patch the frames were built over.
  """
  @type context :: %{exhibit: module(), values: map()}

  @doc """
  Runs `exhibit` over `values`, returning every field the page assigns.

  `requested_frame` is the URL's `frame` string, or `nil` for the last frame.
  `on_step` is forwarded to `Steps.run/3` for every run the probe performs.

  The returned map carries `:frames`, `:failure`, `:index`, `:count`,
  `:drawing`, `:viewport`, `:source`, `:snippet`, `:step` and the chosen span
  as `:cells`.
  """
  @spec build(module(), map(), nil | String.t(), nil | (Frame.t() -> any())) :: map()
  def build(exhibit, values, requested_frame, on_step \\ nil) do
    {frames, failure, run_values, cells} = adaptive(exhibit, values, on_step)

    exhibit
    |> page(frames, failure, requested_frame, run_values)
    |> Map.put(:cells, cells)
  end

  @doc """
  Derives the page's fields for `index` of an already-built run.

  This is the navigation path: the frames, failure and the exhibit's drawing
  and viewport are all that a frame change needs.
  """
  @spec view([Frame.t()], Failure.t() | nil, nil | non_neg_integer(), context()) :: map()
  def view(frames, failure, index, %{exhibit: exhibit, values: values}) do
    frame = frame_at(frames, index)
    drawing = draw(exhibit, frame, values)

    %{
      frames: frames,
      failure: failure,
      index: index,
      count: length(frames),
      step: frame_step(frame),
      drawing: drawing,
      viewport: viewport(exhibit, values, frames, drawing),
      source: source(frame, failure),
      snippet: exhibit.reproduce(values)
    }
  end

  @doc """
  The frame index the URL asks for, clamped into the run.

  `nil` (no `frame` key) and an unparseable value both mean the last frame.
  An empty run has no frame to select, so the index is `nil`.
  """
  @spec index(nil | String.t(), non_neg_integer()) :: nil | non_neg_integer()
  def index(_requested, 0), do: nil
  def index(requested, count), do: requested |> requested_index(count) |> clamp(count)

  @doc """
  A failure for an unexpected task exit, which has no frames and no step.

  It is a real `%Steps.Failure{}` so the transport and source panes treat it
  exactly like a step failure, with a generic message instead of an exception.
  """
  @spec generic_failure(term()) :: Failure.t()
  def generic_failure(reason) do
    %Failure{
      frames: [],
      index: 0,
      step: %Steps.Step{
        id: :run,
        label: "run",
        doc: "The exhibit's run",
        run: &Function.identity/1,
        source: {__ENV__.file, __ENV__.line}
      },
      exception: %RuntimeError{message: "The run failed to complete: #{inspect(reason)}"},
      stacktrace: []
    }
  end

  defp page(exhibit, frames, failure, requested_frame, values) do
    index = index(requested_frame, length(frames))
    view(frames, failure, index, %{exhibit: exhibit, values: values})
  end

  # -- adaptive span ----------------------------------------------------------

  defp adaptive(exhibit, values, on_step) do
    probe_values = Map.put(values, :cells, 1)
    {frames, failure} = run(exhibit, probe_values, on_step)
    choose(frames, failure, exhibit, values, on_step)
  end

  # A probe that raised cannot tell a heavy tiling from a light one, so the
  # run is repeated at the default span and its failure is the reported one.
  defp choose(_frames, %Failure{}, exhibit, values, on_step), do: wide(exhibit, values, on_step)

  defp choose(frames, nil, exhibit, values, on_step), do: choose_span(heavy?(frames), frames, exhibit, values, on_step)

  defp choose_span(true, frames, _exhibit, values, _on_step), do: {frames, nil, Map.put(values, :cells, 1), 1}

  defp choose_span(false, _frames, exhibit, values, on_step), do: wide(exhibit, values, on_step)

  defp wide(exhibit, values, on_step) do
    run_values = Map.put(values, :cells, 2)
    {frames, failure} = run(exhibit, run_values, on_step)
    {frames, failure, run_values, 2}
  end

  defp run(exhibit, values, on_step) do
    case Steps.run(exhibit.steps(values), exhibit.initial(values),
           max_frames: @max_frames,
           on_step: on_step
         ) do
      {:ok, frames} -> {frames, nil}
      {:error, %Failure{frames: frames} = failure} -> {frames, failure}
    end
  end

  # The state exposes its welded map only for a map-building exhibit; every
  # other exhibit reports zero and therefore takes the default span.
  defp heavy?([]), do: false

  defp heavy?(frames), do: frames |> List.last() |> Map.fetch!(:state) |> vertices() > @vertex_budget

  defp vertices(%{map: %PlanarMap{} = map}), do: PlanarMap.num_vertices(map)
  defp vertices(_state), do: 0

  # -- the frame's page fields ------------------------------------------------

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

  defp viewport(exhibit, values, frames, drawing) do
    case pinned_viewport(exhibit, values, frames) do
      %Viewport{} = viewport -> viewport
      :fit -> fitted(drawing)
    end
  end

  defp pinned_viewport(exhibit, values, frames) do
    pinned_viewport(exhibit, values, frames, exports_viewport?(exhibit))
  end

  # `function_exported?/3` reports false for a module that has not been loaded,
  # which would silently downgrade a pinned viewport to a fitted one. Loading
  # first makes the answer depend on the module, not on what happened to be
  # loaded already.
  defp exports_viewport?(exhibit) do
    Code.ensure_loaded?(exhibit) and function_exported?(exhibit, :viewport, 2)
  end

  defp pinned_viewport(exhibit, values, frames, true), do: declared_viewport(exhibit.viewport(values, frames))

  defp pinned_viewport(_exhibit, _values, _frames, false), do: :fit

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
end

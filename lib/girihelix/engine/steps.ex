defmodule Girihelix.Engine.Steps do
  @moduledoc """
  Runs a labelled sequence of pure steps over a state, retaining every frame.

  Every engine algorithm that has internal stages is authored as such a sequence,
  which gives it two entry points over one implementation: a `steps/…` function
  returning the sequence, and a plain function that runs it and takes the last
  state. The workbench renders the frames; nothing else needs them.

  Value types and single-operation primitives are deliberately exempt — `Loose`,
  `Point`, `Transform`, `Intersect` and `Polygon` expose no `steps/…`. A sequence
  wrapping them would be a list of one-line delegations to functions that already
  *are* the whole implementation, and `final(steps) == plain` would be a
  tautology. The first real subjects are `Map.merge_map`, `Faces.extract_faces`
  and `FillRegion.fill`, then the figure builders.
  """

  defmodule Step do
    @moduledoc "One clause of an algorithm: a pure function from state to state."
    @enforce_keys [:id, :label, :doc, :run, :source]
    defstruct [:id, :label, :doc, :run, :source]

    @type t :: %__MODULE__{
            id: atom(),
            label: String.t(),
            doc: String.t(),
            run: (term() -> term()),
            source: {String.t(), non_neg_integer()}
          }
  end

  defmodule Frame do
    @moduledoc "The state after one step, or the initial state when `step` is nil."
    @enforce_keys [:index, :step, :state]
    defstruct [:index, :step, :state]

    @type t :: %__MODULE__{index: non_neg_integer(), step: Step.t() | nil, state: term()}
  end

  defmodule Failure do
    @moduledoc "A step that raised, with every frame that did build."
    @enforce_keys [:frames, :index, :step, :exception, :stacktrace]
    defstruct [:frames, :index, :step, :exception, :stacktrace]

    @type t :: %__MODULE__{
            frames: [Frame.t()],
            index: non_neg_integer(),
            step: Step.t(),
            exception: Exception.t(),
            stacktrace: list()
          }
  end

  @doc """
  Builds a step, recording the file and line of the call site.

  The captured location is what lets the workbench highlight the code that
  produced a frame, without searching for the module on disk.
  """
  defmacro step(id, label, doc, run) do
    quote do
      %Girihelix.Engine.Steps.Step{
        id: unquote(id),
        label: unquote(label),
        doc: unquote(doc),
        run: unquote(run),
        source: {unquote(__CALLER__.file), unquote(__CALLER__.line)}
      }
    end
  end

  @doc """
  Runs `steps` from `initial`, returning every frame.

  Frame zero is `initial` itself, with a nil step. Options:

    * `:max_frames` — cap on the frames returned, frame zero included. Defaults
      to `:infinity`.
  """
  @spec run([Step.t()], term(), keyword()) :: {:ok, [Frame.t()]} | {:error, Failure.t()}
  def run(steps, initial, opts \\ []) do
    max = Keyword.get(opts, :max_frames, :infinity)
    zero = %Frame{index: 0, step: nil, state: initial}
    advance(steps, zero, [zero], max)
  end

  @doc "Runs `steps` and returns the frames, re-raising the original exception."
  @spec run!([Step.t()], term(), keyword()) :: [Frame.t()]
  def run!(steps, initial, opts \\ []) do
    case run(steps, initial, opts) do
      {:ok, frames} ->
        frames

      {:error, %Failure{exception: exception, stacktrace: stacktrace}} ->
        reraise(exception, stacktrace)
    end
  end

  @doc "The state a plain caller wants: the last frame's state."
  @spec final([Frame.t()]) :: term()
  def final(frames), do: List.last(frames).state

  @doc "The frame at `index`, or nil when out of range."
  @spec at([Frame.t()], non_neg_integer()) :: Frame.t() | nil
  def at(frames, index), do: Enum.at(frames, index)

  defp advance([], _previous, acc, _max), do: {:ok, Enum.reverse(acc)}

  # At capacity: stop, keeping the frames built so far. `:infinity` is not an
  # integer, so it falls through to the clause that runs the next step.
  defp advance([_step | _rest], %Frame{index: index}, acc, max) when is_integer(max) and index + 1 >= max,
    do: {:ok, Enum.reverse(acc)}

  defp advance([step | rest], %Frame{index: index} = previous, acc, max),
    do: run_one(step, rest, previous, acc, max, index + 1)

  defp run_one(step, rest, previous, acc, max, index) do
    state = step.run.(previous.state)
    frame = %Frame{index: index, step: step, state: state}
    advance(rest, frame, [frame | acc], max)
  rescue
    exception ->
      {:error,
       %Failure{
         frames: Enum.reverse(acc),
         index: index,
         step: step,
         exception: exception,
         stacktrace: __STACKTRACE__
       }}
  end
end

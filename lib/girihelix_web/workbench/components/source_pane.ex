defmodule GirihelixWeb.Workbench.Components.SourcePane do
  @moduledoc """
  Shows the file and lines that built the current frame.

  A frame carries the file, line and prose captured by `step/3`, so the pane
  renders the step's lines exactly as they are on disk. The resolver finds the
  call's range and the context window around it; this pane renders that window.
  Lines inside `first..last` are highlighted; the header names the file and the
  first line, so a reader can find the same call in an editor.

  The lines outside `context_first..context_last` are never rendered: the
  resolver hands over the whole file, and this pane selects the window.

  Frame zero has no step, so there is nothing to point at and the pane says so.
  A file that cannot be read is an ordinary state too — the exhibit still works
  without its source.
  """

  use GirihelixWeb, :html

  @highlight_class "bg-warning/30"

  attr :source, :any,
    required: true,
    doc: "The resolver's `{:ok, source}` or `{:error, :no_step | :unavailable}`."

  @spec source_pane(map()) :: Phoenix.LiveView.Rendered.t()
  def source_pane(%{source: {:ok, source}} = assigns) do
    assigns =
      assign(assigns,
        path: source.path,
        first: source.first,
        last: source.last,
        lines: context_lines(source)
      )

    ~H"""
    <section id="source" class="flex flex-col gap-2">
      <p class="font-mono text-sm font-semibold">{@path}:{@first}</p>
      <div class="overflow-x-auto rounded-box bg-base-200 p-3 font-mono text-xs leading-5">
        <div :for={{number, text} <- @lines} class={line_class(number, @first, @last)}>
          <span class="mr-3 inline-block w-8 select-none text-right opacity-50">{number}</span>
          <span class="whitespace-pre">{text}</span>
        </div>
      </div>
    </section>
    """
  end

  def source_pane(%{source: {:error, :no_step}} = assigns) do
    ~H"""
    <p id="source" class="text-sm opacity-70">Parameters, before any step.</p>
    """
  end

  def source_pane(%{source: {:error, :unavailable}} = assigns) do
    ~H"""
    <p id="source" class="text-sm opacity-70">Source unavailable.</p>
    """
  end

  defp context_lines(%{lines: lines, context_first: first, context_last: last}) do
    for {number, _text} = line <- lines, number >= first and number <= last, do: line
  end

  defp line_class(number, first, last) when number >= first and number <= last, do: @highlight_class

  defp line_class(_number, _first, _last), do: nil
end

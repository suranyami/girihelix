defmodule GirihelixWeb.Workbench.Source do
  @moduledoc """
  Resolves a step's captured call site into the lines of the file that built it.

  A step records the file and line of the `step/4` call that built it. The
  source pane renders that call, so this module turns the capture into the whole
  file as `{number, text}` plus two ranges: the call itself (`first..last`) and
  the window around it (`context_first..context_last`). The pane selects the
  window; keeping the whole file here means a reader can scroll without a second
  read.

  ## The call range

  The captured line is where the call opens. A call written on one line closes
  there; a call written over several lines closes where its parenthesis balance
  returns to zero. The scan counts `(` and `)` only, ignoring `#` comments and
  `"` strings with backslash escapes, and stops after 50 lines so a malformed
  source cannot be walked to the end of the file. If the balance never returns,
  the range is the captured line alone.

  ## What is readable

  Only paths under `lib/` are accepted. A captured path is absolute when the
  code was compiled with `mix`, so it is made relative to the working directory
  first. The guard also means the workbench serves girihelix's own source only:
  a path outside `lib/` is not readable, whatever produced the capture.
  """

  alias Girihelix.Engine.Steps

  @typedoc """
  A readable file with the step's call range and a two-line window around it.

  `lines` is the whole file, so a caller can render a different window without
  reading disk again.
  """
  @type source :: %{
          path: String.t(),
          first: pos_integer(),
          last: pos_integer(),
          context_first: pos_integer(),
          context_last: pos_integer(),
          lines: [{pos_integer(), String.t()}]
        }

  # The longest call the balancer will walk before giving up and reporting the
  # captured line alone.
  @scan_lines 50

  @doc """
  Resolves `step`'s captured `{file, line}` into the file's contents.

  Returns `{:error, :no_step}` for frame zero, and `{:error, :unavailable}` for
  a path outside `lib/` or a file that cannot be read.
  """
  @spec resolve(Steps.Step.t() | nil) :: {:ok, source()} | {:error, :no_step | :unavailable}
  def resolve(nil), do: {:error, :no_step}

  def resolve(%Steps.Step{source: {captured, first}}) do
    path = Path.relative_to_cwd(captured)

    with :ok <- within_lib(path),
         {:ok, contents} <- read(path) do
      {:ok, source(path, first, file_lines(contents))}
    end
  end

  defp within_lib("lib/" <> _rest), do: :ok
  defp within_lib(_path), do: {:error, :unavailable}

  defp read(path) do
    case File.read(path) do
      {:ok, contents} -> {:ok, contents}
      {:error, _reason} -> {:error, :unavailable}
    end
  end

  defp source(path, first, lines) do
    last = call_last(lines, first)

    %{
      path: path,
      first: first,
      last: last,
      context_first: max(1, first - 2),
      context_last: min(length(lines), last + 2),
      lines: lines
    }
  end

  # A file's lines, 1-based, without the empty element a final newline leaves
  # behind. A blank line at the end of the file is kept: only the break itself
  # is dropped.
  defp file_lines(contents) do
    contents
    |> String.split("\n")
    |> drop_final_break()
    |> Enum.with_index(1)
    |> Enum.map(fn {text, number} -> {number, text} end)
  end

  defp drop_final_break(lines), do: lines |> Enum.reverse() |> drop_break() |> Enum.reverse()

  defp drop_break(["" | rest]), do: rest
  defp drop_break(lines), do: lines

  defp call_last(lines, first) do
    lines
    |> Enum.drop(first - 1)
    |> Enum.take(@scan_lines)
    |> scan_lines(0, :code)
    |> found_or(first)
  end

  defp found_or(nil, first), do: first
  defp found_or(number, _first), do: number

  defp scan_lines([], _balance, _mode), do: nil

  defp scan_lines([{number, text} | rest], balance, mode) do
    {balance, mode} = scan_text(text, balance, mode)
    closed(rest, balance, mode, number)
  end

  defp closed(_rest, 0, _mode, number), do: number
  defp closed(rest, balance, mode, _number), do: scan_lines(rest, balance, mode)

  # A comment ends with its line; a string may continue onto the next one.
  defp scan_text(text, balance, mode) do
    text
    |> String.to_charlist()
    |> Enum.reduce({balance, mode}, &scan_char/2)
    |> close_comment()
  end

  defp close_comment({balance, :comment}), do: {balance, :code}
  defp close_comment(acc), do: acc

  defp scan_char(?\\, {balance, :string}), do: {balance, :escaped}
  defp scan_char(_char, {balance, :escaped}), do: {balance, :string}
  defp scan_char(?", {balance, :string}), do: {balance, :code}
  defp scan_char(_char, {_balance, :string} = acc), do: acc
  defp scan_char(?", {balance, :code}), do: {balance, :string}
  defp scan_char(?#, {balance, :code}), do: {balance, :comment}
  defp scan_char(_char, {_balance, :comment} = acc), do: acc
  defp scan_char(?(, {balance, :code}), do: {balance + 1, :code}
  defp scan_char(?), {balance, :code}), do: {balance - 1, :code}
  defp scan_char(_char, acc), do: acc
end

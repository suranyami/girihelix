defmodule Girihelix.Credo.Checks.ModuleLength do
  @moduledoc """
  Flags source files longer than the documented maximum — the workspace coding
  style's "files are focused (<800 lines)" rule, borrowed from `work/core` where
  the same check guards against "god modules".

  A long file is a proxy for a module doing too much. The fix is usually to
  extract cohesive pieces into their own module, not to raise the limit.
  """

  use Credo.Check,
    id: "GIRI001",
    category: :design,
    base_priority: :high,
    param_defaults: [max_lines: 800],
    explanations: [
      check: """
      Files should stay under 800 lines. Beyond that, a module is usually doing
      too much and should be split by extracting cohesive pieces (a sub-context,
      a dedicated module, a shared helper) rather than left to keep growing.
      """,
      params: [
        max_lines: "The maximum number of lines a source file may have."
      ]
    ]

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params) do
    max_lines = Params.get(params, :max_lines, __MODULE__)
    issue_meta = IssueMeta.for(source_file, params)
    line_count = source_file |> Credo.Code.to_lines() |> Enum.count()

    if line_count > max_lines do
      [issue_for(issue_meta, line_count, max_lines)]
    else
      []
    end
  end

  defp issue_for(issue_meta, line_count, max_lines) do
    format_issue(
      issue_meta,
      message:
        "Module is #{line_count} lines long (max #{max_lines}) — consider extracting a sub-context, a dedicated module, or a shared helper.",
      trigger: Issue.no_trigger(),
      line_no: 1
    )
  end
end

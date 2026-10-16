defmodule Girihelix.Engine.ArchitectureTest do
  @moduledoc """
  Guards the rule that keeps the engine portable and testable: it may not
  reference Ash, Phoenix or the web layer.
  """

  use ExUnit.Case, async: true

  @engine_root "lib/girihelix/engine"

  @patterns [
    {"Ash", ~r/\bAsh\./},
    {"Phoenix", ~r/\bPhoenix\./},
    {"GirihelixWeb", ~r/\bGirihelixWeb\b/}
  ]

  test "every engine source file is free of Ash, Phoenix and web references" do
    offenders =
      @engine_root
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.flat_map(fn path ->
        path
        |> File.read!()
        |> violations()
        |> Enum.map(&"#{path} references #{&1}")
      end)

    assert offenders == [],
           """
           The engine must stay pure. These files break the boundary:

           #{Enum.join(offenders, "\n")}

           Ash resources may hold engine values; the engine may never hold Ash.
           The same goes for Phoenix and the web layer.
           """
  end

  test "the detector finds a violation, so the guard cannot pass vacuously" do
    assert violations("defmodule X do\n  alias Ash.Foo\nend") == ["Ash"]
    assert violations("Phoenix.LiveView.socket()") == ["Phoenix"]
    assert violations("alias GirihelixWeb.Endpoint") == ["GirihelixWeb"]
    assert violations("defmodule Clean do\nend") == []
  end

  defp violations(source) do
    for {name, pattern} <- @patterns, Regex.match?(pattern, source), do: name
  end
end

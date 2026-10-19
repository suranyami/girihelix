defmodule Girihelix.Engine.ArchitectureTest do
  @moduledoc """
  Guards the rule that keeps the engine portable and testable: it may not
  reference Ash, Ecto, Phoenix or the web layer.
  """

  use ExUnit.Case, async: true

  @engine_root "lib/girihelix/engine"

  @patterns [
    {"Ash", ~r/\bAsh\./},
    {"Ecto", ~r/\bEcto\./},
    {"Phoenix", ~r/\bPhoenix\./},
    {"GirihelixWeb", ~r/\bGirihelixWeb\b/}
  ]

  test "every engine source file is free of Ash, Ecto, Phoenix and web references" do
    offenders =
      Enum.flat_map(engine_files(), fn path ->
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
           The same goes for Ecto, Phoenix and the web layer.
           """
  end

  test "the detector finds a violation, so the guard cannot pass vacuously" do
    assert violations("defmodule X do\n  alias Ash.Foo\nend") == ["Ash"]
    assert violations("Ecto.UUID.generate()") == ["Ecto"]
    assert violations("Phoenix.LiveView.socket()") == ["Phoenix"]
    assert violations("alias GirihelixWeb.Endpoint") == ["GirihelixWeb"]
    assert violations("defmodule Clean do\nend") == []
  end

  test "the guard scans the engine, so it cannot pass by matching nothing" do
    assert length(engine_files()) >= 7
    assert "lib/girihelix/engine/geometry/segment.ex" in engine_files()
  end

  defp engine_files do
    @engine_root
    |> Path.join("**/*.ex")
    |> Path.wildcard()
  end

  defp violations(source) do
    for {name, pattern} <- @patterns, Regex.match?(pattern, source), do: name
  end
end

defmodule Girihelix.Engine.FacesGoldenTest do
  @moduledoc """
  Golden tests for face discovery and colouring against the local-only Taprats
  reference harness. Opted in by the `:taprats` tag, which
  `test/test_helper.exs` excludes when `reference/oracle/fixtures` is absent.
  """
  use ExUnit.Case, async: true

  @moduletag :taprats

  @scenarios ~w(faces-square-diagonal faces-grid-3x3 faces-hub-hexagon
    faces-replicate-ladder faces-dangling faces-figure-eight faces-conflict
    faces-two-corner faces-no-faces faces-split-parallel)

  for name <- @scenarios do
    test "matches Taprats: #{name}" do
      {ops, expected} = Girihelix.TapratsHarness.load(unquote(name))

      assert Girihelix.TapratsHarness.compare(expected, Girihelix.TapratsHarness.run_script(ops)) ==
               :ok
    end
  end
end

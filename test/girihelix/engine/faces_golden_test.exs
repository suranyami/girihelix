defmodule Girihelix.Engine.FacesGoldenTest do
  @moduledoc """
  Golden tests for face discovery and colouring against the local-only Taprats
  reference harness. Opted in by the `:taprats` tag, which
  `test/test_helper.exs` excludes when `reference/oracle/fixtures` is absent.
  """
  use ExUnit.Case, async: true

  @moduletag :taprats

  @scenarios ~w()

  for name <- @scenarios do
    test "matches Taprats: #{name}" do
      {ops, expected} = Girihelix.TapratsHarness.load(unquote(name))

      assert Girihelix.TapratsHarness.compare(expected, Girihelix.TapratsHarness.run_script(ops)) ==
               :ok
    end
  end
end

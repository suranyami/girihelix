defmodule Girihelix.Engine.TilingsGoldenTest do
  @moduledoc """
  Golden tests for the constructed tilings against the local-only Taprats
  reference harness. Opted in by the `:taprats` tag, which `test/test_helper.exs`
  excludes when `reference/oracle/fixtures` is absent.

  The comparison is canonical — sorted rounded positions, edge position pairs
  and ring cycles — because Java's hash iteration order is unspecified. Each
  scenario binds `Rosette(n, 0.0, 3)` to every regular feature and constructs
  over `Construct.default_region/1`, on both sides.
  """
  use ExUnit.Case, async: true

  @moduletag :taprats

  @scenarios ~w(construct-4.5 construct-6.5 construct-mixed)

  for name <- @scenarios do
    test "matches Taprats: #{name}" do
      {ops, expected} = Girihelix.TapratsHarness.load(unquote(name))

      assert Girihelix.TapratsHarness.compare(expected, Girihelix.TapratsHarness.run_script(ops)) ==
               :ok
    end
  end
end

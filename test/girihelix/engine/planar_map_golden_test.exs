defmodule Girihelix.Engine.PlanarMapGoldenTest do
  @moduledoc """
  Golden tests against the local-only Taprats reference harness. Opted in by
  the `:taprats` tag, which `test/test_helper.exs` excludes when
  `reference/oracle/fixtures` is absent.
  """
  use ExUnit.Case, async: true

  @moduletag :taprats

  @scenarios ~w(basic-edge coincident-vertices hub-ring duplicate-angle self-edge
    split-on-edge split-two-edges split-repeat split-at-endpoint split-keeps-ring
    split-parallel-edges remove-hub remove-moves-head remove-last transform-rotate
    transform-then-insert transform-empty scale-translate scale-negative sort-probe
    replicate-ladder replicate-coalesce replicate-no-split replicate-empty-unit
    replicate-no-transforms sort-probe-replicate remove-self-edge)

  for name <- @scenarios do
    test "matches Taprats: #{name}" do
      {ops, expected} = Girihelix.TapratsHarness.load(unquote(name))

      assert Girihelix.TapratsHarness.compare(expected, Girihelix.TapratsHarness.run_script(ops)) ==
               :ok
    end
  end
end

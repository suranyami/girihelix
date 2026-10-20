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
    replicate-no-transforms sort-probe-replicate remove-self-edge weld-squares
    weld-shared-edge weld-cluster weld-collinear weld-self weld-empty-receiver
    weld-empty-other sortfuzz-12-1 sortfuzz-12-2 sortfuzz-12-3 sortfuzz-20-1
    sortfuzz-20-2 sortfuzz-20-3 sortfuzz-40-1 sortfuzz-40-2 sortfuzz-40-3 sortfuzz-70-1
    sortfuzz-70-2 sortfuzz-70-3)

  for name <- @scenarios do
    test "matches Taprats: #{name}" do
      {ops, expected} = Girihelix.TapratsHarness.load(unquote(name))

      assert Girihelix.TapratsHarness.compare(expected, Girihelix.TapratsHarness.run_script(ops)) ==
               :ok
    end
  end
end

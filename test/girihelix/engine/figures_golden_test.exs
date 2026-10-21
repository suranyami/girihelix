defmodule Girihelix.Engine.FiguresGoldenTest do
  @moduledoc """
  Golden tests for the figure builders against the local-only Taprats reference
  harness. Opted in by the `:taprats` tag, which `test/test_helper.exs` excludes
  when `reference/oracle/fixtures` is absent.
  """
  use ExUnit.Case, async: true

  @moduletag :taprats

  @scenarios ~w(figure-star-default figure-star-unit figure-star-fractional
    figure-star-closure figure-star-clamped figure-star-crash
    figure-rosette-default figure-rosette-negative-q figure-rosette-clamped
    figure-rosette-fixme figure-scale-passthrough figure-scale-rosette
    figure-scale-clipped)

  for name <- @scenarios do
    test "matches Taprats: #{name}" do
      {ops, expected} = Girihelix.TapratsHarness.load(unquote(name))

      assert Girihelix.TapratsHarness.compare(expected, Girihelix.TapratsHarness.run_script(ops)) ==
               :ok
    end
  end
end

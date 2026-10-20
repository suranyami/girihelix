defmodule GirihelixWeb.Workbench.RegistryTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Steps
  alias GirihelixWeb.Workbench.Param
  alias GirihelixWeb.Workbench.Registry

  test "the registry has unique slugs and one non-empty group" do
    slugs = Enum.map(Registry.exhibits(), & &1.slug())
    assert slugs == Enum.uniq(slugs)
    assert Enum.map(Registry.grouped(), &elem(&1, 0)) == [:geometry]
    assert {:ok, GirihelixWeb.Workbench.Exhibits.Loose} = Registry.get("loose")
    assert Registry.get("nope") == {:error, :unknown_exhibit}
  end

  test "every exhibit declares a default for every parameter" do
    for exhibit <- Registry.exhibits(), param <- exhibit.params() do
      # A helper rather than `refute is_nil(...)`: Styler would rewrite that to
      # a truthiness check, and `false` is a legitimate boolean default.
      refute missing_default?(param)
    end
  end

  test "every exhibit draws at its defaults and extremes" do
    for exhibit <- Registry.exhibits(),
        values <- variants(exhibit) do
      run = Steps.run(exhibit.steps(values), exhibit.initial(values), max_frames: 200)

      case run do
        {:ok, frames} ->
          assert frames != []

          for frame <- frames do
            assert_drawing(exhibit.draw(frame, values))
          end

        {:error, %Steps.Failure{step: %Steps.Step{}}} ->
          :ok
      end
    end
  end

  defp missing_default?(%Param{default: nil}), do: true
  defp missing_default?(%Param{}), do: false

  defp variants(exhibit) do
    params = exhibit.params()
    defaults = Param.values(params, :default)

    [defaults] ++
      for param <- params,
          mode <- [:first, :last],
          do: Map.put(defaults, param.name, Param.values([param], mode)[param.name])
  end

  defp assert_drawing({:canvas, ops}), do: assert(ops != [])
  defp assert_drawing({:panel, rows}), do: assert(rows != [])
  defp assert_drawing({:both, ops, rows}), do: assert(ops != [] and rows != [])
end

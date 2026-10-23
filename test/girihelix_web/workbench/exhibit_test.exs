defmodule GirihelixWeb.Workbench.ExhibitTest do
  use ExUnit.Case, async: true

  alias GirihelixWeb.Workbench.Registry

  # Compile-time-ish guarantee: an exhibit that forgets its byline — or one
  # that still smuggles the old em-dash into its title — fails here.
  test "every exhibit declares a title and a byline, with no em-dash left" do
    for exhibit <- Registry.exhibits() do
      assert Code.ensure_loaded?(exhibit)

      assert function_exported?(exhibit, :title, 0), "#{exhibit} has no title/0"
      assert function_exported?(exhibit, :byline, 0), "#{exhibit} has no byline/0"

      name = "#{exhibit}"

      # The registry's entries are module *atoms*, so the compiler cannot see
      # these as static calls; apply/3 is the honest dispatch here.
      # credo:disable-for-lines:2 Credo.Check.Refactor.Apply
      title = apply(exhibit, :title, [])
      byline = apply(exhibit, :byline, [])

      assert title != "", "#{name} has an empty title"
      assert byline != "", "#{name} has an empty byline"
      refute title =~ " — ", "#{name} still carries the old em-dash title"
    end
  end
end

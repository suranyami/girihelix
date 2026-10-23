defmodule Girihelix.Engine.Tilings.CatalogueReleaseTest do
  @moduledoc """
  The catalogue reads through the code path, not the working directory.

  A release container's working directory holds only the release — the
  application's `priv/` trees live inside it at
  `<release>/lib/<app>-<version>/priv/`, reachable via `:code.priv_dir/1`.
  This module deliberately runs non-async: it moves the virtual machine's
  working directory, which every other test sees.
  """

  use ExUnit.Case, async: false

  alias Girihelix.Engine.Tilings.Catalogue

  test "load/1 resolves the fixture through :code.priv_dir, not the cwd" do
    File.cd!(System.tmp_dir!(), fn ->
      assert "4.5" |> Catalogue.load() |> elem(0) == :ok
      assert %{name: "4.5"} = Catalogue.load!("4.5")
    end)
  end
end

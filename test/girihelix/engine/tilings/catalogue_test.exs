defmodule Girihelix.Engine.Tilings.CatalogueTest do
  @moduledoc """
  The catalogue: the shipped index lists every tiling, every file loads, and
  unknown names are errors.
  """

  use ExUnit.Case, async: true

  alias Girihelix.Engine.Tilings.Catalogue

  test "the index lists all 60 tilings with unique names" do
    names = Catalogue.names()
    assert length(names) == 60
    assert names == Enum.uniq(names)
    assert "4.5" in names
    assert "6.5" in names
  end

  test "load/1 parses a known tiling" do
    assert {:ok, %{name: "4.5"} = tiling} = Catalogue.load("4.5")
    assert length(tiling.features) == 3
  end

  test "all 60 files load, including the legacy-encoded descriptions" do
    results = Catalogue.all()
    assert length(results) == 60
    assert Enum.all?(results, fn {_name, result} -> match?({:ok, _}, result) end)

    assert {:ok, mughal} = Catalogue.load("Mughal I'timad")
    assert String.valid?(mughal.description)
  end

  test "an unknown name is an error" do
    assert Catalogue.load("nope") == {:error, :unknown_tiling}
  end

  test "load!/1 returns the tiling for a known name" do
    assert %{name: "6.5"} = Catalogue.load!("6.5")
  end

  test "load!/1 raises for an unknown name" do
    assert_raise ArgumentError, fn -> Catalogue.load!("nope") end
  end
end

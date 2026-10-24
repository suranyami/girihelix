defmodule Girihelix.Engine.Render.PaletteTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Render.Palette

  test "the dataset holds 348 Wada combinations" do
    assert Palette.count() == 348
    assert length(Palette.options()) == 348
    assert hd(Palette.options()) == :"1"
    assert List.last(Palette.options()) == :"348"
  end

  test "a combination is its colours in dataset order" do
    assert {:ok, colours} = Palette.combination(:"176")
    assert Enum.map(colours, & &1.hex) == ["#ffb3f0", "#ffcfc4", "#80ffcc"]
    assert Enum.map(colours, & &1.name) == ["Hermosa Pink", "Seashell Pink", "Calamine BLue"]
    assert {:ok, ^colours} = Palette.combination(176)
  end

  test "an unknown combination is an error and the bang twin raises" do
    assert Palette.combination(349) == {:error, :unknown_combination}
    assert Palette.combination(:"0") == {:error, :unknown_combination}
    assert Palette.combination(:nope) == {:error, :unknown_combination}
    assert Palette.roles(349) == {:error, :unknown_combination}
    assert_raise ArgumentError, fn -> Palette.combination!(349) end
    assert_raise ArgumentError, fn -> Palette.roles!(349) end
  end

  test "roles order the four slots by relative luminance" do
    assert Palette.roles!(:"253") == %{
             edge: "#340059",
             darker: "#1b3644",
             lighter: "#ff7340",
             background: "#f2ff26"
           }
  end

  test "a two-colour combination keeps the light colour for both faces" do
    assert Palette.roles!(:"1") == %{
             edge: "#de4500",
             darker: "#29bdad",
             lighter: "#29bdad",
             background: "#29bdad"
           }
  end

  test "a three-colour combination uses all three" do
    assert Palette.roles!(:"176") == %{
             edge: "#ffb3f0",
             darker: "#ffcfc4",
             lighter: "#80ffcc",
             background: "#80ffcc"
           }
  end

  test "a four-colour combination maps all four in order" do
    assert Palette.roles!(:"348") == %{
             edge: "#340059",
             darker: "#172713",
             lighter: "#328e13",
             background: "#bcd382"
           }
  end

  test "a five-colour combination takes the first, second, second-to-last and last" do
    assert Palette.roles!(:"274") == %{
             edge: "#bf36e0",
             darker: "#9161f2",
             lighter: "#ff3319",
             background: "#4f8fe6"
           }
  end

  test "a one-colour combination paints every role the same colour" do
    same = "#328e13"

    assert Palette.roles!(:"5") == %{
             edge: same,
             darker: same,
             lighter: same,
             background: same
           }
  end
end

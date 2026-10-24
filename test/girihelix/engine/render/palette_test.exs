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
    assert Palette.roles(349, [:edge]) == {:error, :unknown_combination}
    assert_raise ArgumentError, fn -> Palette.combination!(349) end
    assert_raise ArgumentError, fn -> Palette.roles!(349, [:edge]) end
  end

  test "a three-colour combination uses its two extremes for faces" do
    assert Palette.roles!(:"176", [:edge, :darker, :lighter]) == %{
             edge: "#ffb3f0",
             darker: "#ffcfc4",
             lighter: "#80ffcc"
           }

    assert Palette.roles!(:"176", [:edge, :background]) == %{
             edge: "#ffb3f0",
             background: "#80ffcc"
           }
  end

  test "a four-colour combination uses its two extremes for faces" do
    assert Palette.roles!(:"348", [:edge, :darker, :lighter]) == %{
             edge: "#340059",
             darker: "#172713",
             lighter: "#bcd382"
           }
  end

  test "a five-colour combination keeps the edge and the most separated pair" do
    assert Palette.roles!(:"274", [:edge, :darker, :lighter]) == %{
             edge: "#bf36e0",
             darker: "#9161f2",
             lighter: "#4f8fe6"
           }
  end

  test "roles are the ones the content asks for" do
    assert Palette.roles!(:"253", [:edge, :darker, :lighter]) == %{
             edge: "#340059",
             darker: "#1b3644",
             lighter: "#f2ff26"
           }

    assert Palette.roles!(:"253", [:edge, :background]) == %{
             edge: "#340059",
             background: "#f2ff26"
           }
  end

  test "a two-colour combination derives its second face" do
    assert Palette.roles!(:"1", [:edge, :darker, :lighter]) == %{
             edge: "#de4500",
             darker: "#197268",
             lighter: "#29bdad"
           }
  end

  test "a one-colour combination derives both faces and its background" do
    assert Palette.roles!(:"5", [:edge, :darker, :lighter]) == %{
             edge: "#328e13",
             darker: "#153d08",
             lighter: "#4fdf1e"
           }

    assert Palette.roles!(:"5", [:edge, :background]) == %{
             edge: "#328e13",
             background: "#4fdf1e"
           }
  end

  test "an unknown role is an error tuple" do
    assert Palette.roles(:"253", [:edge, :sparkle]) == {:error, :unknown_role}
  end
end

defmodule Girihelix.Engine.Tilings.ParserTest do
  @moduledoc """
  The `.tiling` file parser: the shipped reference tilings parse into tiling
  values, malformed input comes back as error tokens.
  """

  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Loose
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Tilings.Parser

  @four_five "reference/1.1.12/tilings/4.5.tiling"
  @six_five "reference/1.1.12/tilings/6.5.tiling"

  test "parses 4.5 with its two generators, three features and seven placements" do
    assert {:ok, tiling} = Parser.parse_file(@four_five)

    assert tiling.name == "4.5"
    assert length(tiling.features) == 3
    assert length(tiling.placements) == 7
    assert Loose.equals(tiling.t1, Point.new(4.5201470213401995, 4.520147021340199))
    assert Loose.equals(tiling.t2, Point.new(-1.1213252548714083e-14, 9.040294042680392))
    assert Enum.any?(tiling.features, &(&1.regular == 4))
  end

  test "parses 6.5 with two features and seven placements" do
    assert {:ok, tiling} = Parser.parse_file(@six_five)
    assert tiling.name == "6.5"
    assert length(tiling.features) == 2
    assert length(tiling.placements) == 7
    assert Enum.any?(tiling.features, &(&1.regular == 6))
  end

  test "rejects a file whose first token is not tiling" do
    assert Parser.parse("polygon 4 1\n") == {:error, :not_a_tiling}
  end

  test "rejects an unknown feature keyword instead of desynchronising" do
    assert {:error, {:bad_keyword, "regularr"}} =
             Parser.parse(~s(tiling "x" 1\n0.0 1.0\n1.0 0.0\nregularr 4 1\n0.0 1.0\n1.0 0.0\n))
  end

  test "a missing description and author are allowed" do
    text = ~s(tiling "x" 0\n0.0 1.0\n1.0 0.0\n)
    assert {:ok, %{name: "x", description: nil, author: nil}} = Parser.parse(text)
  end

  test "sanitises a non-UTF-8 description" do
    text =
      ~s(tiling "x" 0\n0.0 1.0\n1.0 0.0\n"bad ) <>
        <<0x92>> <>
        ~s("\n"author"\n)

    assert {:ok, tiling} = Parser.parse(text)
    assert String.valid?(tiling.description)
    assert tiling.description =~ "bad"
  end
end

defmodule Girihelix.Engine.Tilings.ParserTest do
  @moduledoc """
  The `.tiling` file parser: the shipped reference tilings parse into tiling
  values, malformed input comes back as error tokens.
  """

  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Loose
  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Transform
  alias Girihelix.Engine.Tilings.Parser

  # The vendored catalogue copies (priv/tilings/, committed) rather than the
  # git-ignored reference/ originals — CI has no reference/ checkout. The
  # absolute path is baked at compile time, when the cwd is the project root,
  # so the tests survive another test moving the cwd while they run.
  @four_five Path.absname("priv/tilings/4.5.tiling")
  @six_five Path.absname("priv/tilings/6.5.tiling")

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

  test "duplicates share one id, and the distinct one does not" do
    text = """
    tiling "dup" 3
    1.0 0.0
    0.0 1.0
    regular 4 1
    1.0 0.0 0.0 0.0 1.0 0.0
    regular 4 2
    1.0 0.0 0.0 0.0 1.0 0.0
    0.5 0.0 0.0 0.0 0.5 0.0
    regular 6 1
    1.0 0.0 0.0 0.0 1.0 0.0
    """

    assert {:ok, tiling} = Parser.parse(text)

    # Three declarations come back as three features: de-duplication is by id,
    # not by list position, so the repeat of `regular 4` keeps its own entry.
    assert [first, second, third] = tiling.features
    assert first.regular == 4
    assert second.regular == 4
    assert third.regular == 6
    assert [first.id, second.id, third.id] == [0, 0, 1]

    assert Enum.map(tiling.placements, & &1.feature_id) == [0, 0, 0, 1]

    assert Enum.map(tiling.placements, & &1.transform) == [
             Transform.new(1.0, 0.0, 0.0, 0.0, 1.0, 0.0),
             Transform.new(1.0, 0.0, 0.0, 0.0, 1.0, 0.0),
             Transform.new(0.5, 0.0, 0.0, 0.0, 0.5, 0.0),
             Transform.new(1.0, 0.0, 0.0, 0.0, 1.0, 0.0)
           ]
  end

  test "rejects a regular side count of zero instead of deferring the crash" do
    text = ~s(tiling "x" 1\n0.0 1.0\n1.0 0.0\nregular 0 1\n1.0 0.0 0.0 0.0 1.0 0.0\n)
    assert Parser.parse(text) == {:error, :invalid_number}
  end

  test "rejects a negative regular side count instead of deferring the crash" do
    text = ~s(tiling "x" 1\n0.0 1.0\n1.0 0.0\nregular -1 1\n1.0 0.0 0.0 0.0 1.0 0.0\n)
    assert Parser.parse(text) == {:error, :invalid_number}
  end

  test "rejects a truncated number instead of crashing" do
    text = ~s(tiling "x" 1\n0.0 1.0\n1.0 0.0\nregular 4 1\n1. 0.0 0.0 0.0 1.0 0.0\n)
    assert Parser.parse(text) == {:error, :invalid_number}
  end

  test "rejects a number without an integer part instead of crashing" do
    text =
      ~s(tiling "x" 1\n0.0 1.0\n1.0 0.0\npolygon 2 1\n.5 0.0\n1.0 0.5\n1. 0.0 0.0 0.0 1.0 0.0\n)

    assert Parser.parse(text) == {:error, :invalid_number}
  end

  test "parses a polygon feature with its points and placements" do
    text = """
    tiling "p" 1
    1.0 0.0
    0.0 1.0
    polygon 3 2
    0.0 0.0
    1.0 0.0
    0.0 1.0
    1.0 0.0 0.0
    0.0 1.0 0.0
    1.0 0.0 0.5
    0.25 -1.0 0.25
    """

    assert {:ok, tiling} = Parser.parse(text)

    assert tiling.name == "p"
    assert [feature] = tiling.features
    assert feature.regular == nil
    assert feature.points == [Point.new(0.0, 0.0), Point.new(1.0, 0.0), Point.new(0.0, 1.0)]

    assert Enum.map(tiling.placements, & &1.feature_id) == [0, 0]

    assert Enum.map(tiling.placements, & &1.transform) == [
             Transform.new(1.0, 0.0, 0.0, 0.0, 1.0, 0.0),
             Transform.new(1.0, 0.0, 0.5, 0.25, -1.0, 0.25)
           ]
  end
end

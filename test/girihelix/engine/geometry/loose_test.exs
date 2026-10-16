defmodule Girihelix.Engine.Geometry.LooseTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Loose
  alias Girihelix.Engine.Geometry.Point

  test "the tolerances are the source's values" do
    assert Loose.tol() == 1.0e-7
    assert Loose.tol2() == 1.0e-10
  end

  test "equals/2 on numbers is a linear tolerance" do
    assert Loose.equals(1.0, 1.0 + 1.0e-8)
    refute Loose.equals(1.0, 1.0 + 1.0e-6)
  end

  test "equals/2 on points applies its tolerance to a squared distance" do
    origin = Point.new(0.0, 0.0)

    # 1e-6 apart means a squared distance of 1e-12, which is below TOL2 = 1e-10
    assert Loose.equals(origin, Point.new(1.0e-6, 0.0))
    # 1e-4 apart means 1e-8, which is above it
    refute Loose.equals(origin, Point.new(1.0e-4, 0.0))
  end

  # Review Focus 2: two predicates both spelled "equals" that disagree by a
  # factor of a hundred in linear terms. Pinned here so that any future
  # unification of them has to be a deliberate act.
  test "Point.equals/2 is stricter than Loose.equals/2" do
    origin = Point.new(0.0, 0.0)
    nearby = Point.new(1.0e-6, 0.0)

    refute Point.equals(origin, nearby)
    assert Loose.equals(origin, nearby)
  end

  test "zero/1 on a number tests a difference against TOL" do
    assert Loose.zero(1.0e-8)
    refute Loose.zero(1.0e-6)
  end

  test "zero/1 on a point tests a squared magnitude against TOL2" do
    assert Loose.zero(Point.new(1.0e-6, 0.0))
    refute Loose.zero(Point.new(1.0e-3, 0.0))
  end

  test "near/2 compares a difference against an explicit tolerance" do
    assert Loose.near(1.0e-9, 1.0e-7)
    refute Loose.near(1.0e-5, 1.0e-7)
  end

  # The tolerance handed to near/3 is squared. This is the easiest thing in the
  # whole port to misread: 1e-12 here is a linear radius of 1e-6, not 1e-12.
  test "near/3 applies its tolerance to a squared distance" do
    origin = Point.new(0.0, 0.0)
    radius = 1.0e-6
    tolerance = radius * radius

    # exactly at the radius: the squared distance equals the tolerance, and the
    # comparison is strict, so this is not "near"
    refute Loose.near(origin, Point.new(radius, 0.0), tolerance)
    # comfortably inside it
    assert Loose.near(origin, Point.new(radius / 2.0, 0.0), tolerance)
  end
end

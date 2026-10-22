defmodule Girihelix.Engine.Geometry.PointTest do
  use ExUnit.Case, async: true

  alias Girihelix.Engine.Geometry.Point
  alias Girihelix.Engine.Geometry.Segment

  test "arithmetic is pure and returns new points" do
    a = Point.new(1.0, 2.0)
    b = Point.new(3.0, 5.0)

    assert Point.add(a, b) == Point.new(4.0, 7.0)
    assert Point.subtract(b, a) == Point.new(2.0, 3.0)
    assert Point.scale(a, 2.0) == Point.new(2.0, 4.0)
    assert Point.scale(a, 2.0, 3.0) == Point.new(2.0, 6.0)
    assert Point.dot(a, b) == 13.0
    assert Point.cross(a, b) == -1.0

    # the original is untouched
    assert a == Point.new(1.0, 2.0)
  end

  test "perp/1 is a counter-clockwise quarter turn" do
    assert Point.perp(Point.new(1.0, 0.0)) == Point.new(0.0, 1.0)
  end

  test "normalize/1 returns the point unchanged when its magnitude is zero" do
    zero = Point.new(0.0, 0.0)
    assert Point.normalize(zero) == zero
  end

  test "convex_sum/3 extrapolates outside the unit interval" do
    a = Point.new(0.0, 0.0)
    b = Point.new(1.0, 0.0)

    assert Point.convex_sum(a, b, 0.5) == Point.new(0.5, 0.0)
    # t is not clamped, which the Rosette construction depends on
    assert Point.convex_sum(a, b, 2.0) == Point.new(2.0, 0.0)
    assert Point.convex_sum(a, b, -1.0) == Point.new(-1.0, 0.0)
  end

  test "equals/2 tests a squared distance below Point.TOLERANCE2" do
    base = Point.new(1.0, 1.0)

    assert Point.equals(base, Point.new(1.0, 1.0 + 1.0e-9))
    refute Point.equals(base, Point.new(1.0, 1.0 + 1.0e-5))
  end

  # The cross-tolerance check — that Point.equals/2 is stricter than
  # Loose.equals/2 — lives in Task 3, because Loose does not exist yet.

  test "compare_to/2 orders by squared magnitude, not lexicographically" do
    # both have y = 0, so this is unambiguous about which axis is being compared
    near = Point.new(2.0, 0.0)
    far = Point.new(0.0, 3.0)

    # lexicographic by x would put `far` first; by radius, `near` is smaller
    assert Point.compare_to(near, far) == -1
    assert Point.compare_to(far, near) == 1
    assert Point.compare_to(near, near) == 0
  end

  # The comparison band makes the ordering non-transitive. A
  # caller expecting a total order can get neither stability nor transitivity,
  # so the surprising behaviour is pinned here rather than discovered later.
  test "compare_to/2 is not transitive" do
    band = Point.tolerance2()

    a = Point.new(0.0, 0.0)
    b = Point.new(:math.sqrt(band * 0.75), 0.0)
    c = Point.new(:math.sqrt(band * 1.5), 0.0)

    assert Point.compare_to(a, b) == 0
    assert Point.compare_to(b, c) == 0
    # a and c span more than the band, so they compare unequal
    assert Point.compare_to(a, c) == -1
  end

  test "sorter/0 converts compare_to/2 into a predicate Enum.sort/2 accepts" do
    points = [Point.new(0.0, 3.0), Point.new(2.0, 0.0), Point.new(0.0, 0.0)]

    assert Enum.sort(points, Point.sorter()) == [
             Point.new(0.0, 0.0),
             Point.new(2.0, 0.0),
             Point.new(0.0, 3.0)
           ]
  end

  test "sorter/0 keeps the tolerance band, so a tie is true in both directions" do
    band = Point.tolerance2()
    a = Point.new(0.0, 0.0)
    b = Point.new(:math.sqrt(band * 0.75), 0.0)
    sorter = Point.sorter()

    assert sorter.(a, b)
    assert sorter.(b, a)
  end

  test "angles follow the Java conventions" do
    assert Point.angle(Point.new(1.0, 0.0)) == 0.0
    assert Point.angle(Point.new(0.0, 1.0)) == :math.pi() / 2.0

    from = Point.new(0.0, 0.0)
    assert Point.angle_to(from, Point.new(0.0, 1.0)) == :math.pi() / 2.0
  end

  test "sweep/3 returns a value in [0, 2pi)" do
    vertex = Point.new(0.0, 0.0)
    from = Point.new(1.0, 0.0)
    to = Point.new(0.0, 1.0)

    assert Point.sweep(vertex, from, to) == :math.pi() / 2.0
    assert Point.sweep(vertex, to, from) == 3.0 * :math.pi() / 2.0
  end

  test "dist2_to_line/3 is a clamped point-to-segment distance" do
    a = Point.new(0.0, 0.0)
    b = Point.new(4.0, 0.0)

    # on the segment
    assert Point.dist2_to_line(Point.new(2.0, 3.0), a, b) == 9.0

    # beyond an endpoint: the distance is to the endpoint, not to the infinite line
    assert Point.dist2_to_line(Point.new(-3.0, 0.0), a, b) == 9.0
    assert Point.dist2_to_line(Point.new(7.0, 0.0), a, b) == 9.0
  end

  # A zero-length segment makes the projection parameter NaN,
  # and every comparison against NaN is false, so the clamp falls through to the
  # second endpoint. The call returns a plausible number that means nothing.
  test "dist2_to_line/3 silently falls through on a zero-length segment" do
    degenerate = Point.new(1.0, 1.0)
    probe = Point.new(4.0, 5.0)

    # not a distance to the segment at all: it is the distance to the second endpoint
    assert Point.dist2_to_line(probe, degenerate, degenerate) ==
             Point.dist2(degenerate, probe)
  end

  test "parameterization_on_line/2 returns the parameter unclamped" do
    segment = Segment.new!(Point.new(0.0, 0.0), Point.new(4.0, 0.0))

    assert Point.parameterization_on_line(Point.new(2.0, 0.0), segment) == 0.5
    assert Point.parameterization_on_line(Point.new(-4.0, 0.0), segment) == -1.0
    assert Point.parameterization_on_line(Point.new(8.0, 3.0), segment) == 2.0
  end

  test "center/1 averages a non-empty list" do
    assert Point.center([Point.new(0.0, 0.0), Point.new(4.0, 2.0)]) == Point.new(2.0, 1.0)
  end

  # center/1 used to skip nils. It now takes points only, and a
  # nil is a caller error rather than something to average around.
  test "center/1 no longer accepts nil" do
    assert_raise FunctionClauseError, fn -> Point.center([Point.origin(), nil]) end
  end

  # The non-empty requirement lives in the function head, so the compiler
  # rejects an empty list where it is written. The second assertion is the
  # control: a well-typed call must stay silent, or the first proves nothing.
  test "center/1 rejects an empty list at the call site, not at run time" do
    assert "Girihelix.Engine.Geometry.Point.center([])"
           |> compile_diagnostics()
           |> Enum.any?(
             &(&1.message =~
                 "incompatible types given to Girihelix.Engine.Geometry.Point.center/1")
           )

    assert compile_diagnostics("Girihelix.Engine.Geometry.Point.center([Girihelix.Engine.Geometry.Point.origin()])") ==
             []
  end

  test "normalize/1 scales a non-unit vector to unit length" do
    # Not `== Point.new(0.6, 0.8)`: 3.0 * (1.0 / 5.0) is 0.6000000000000001.
    unit = Point.normalize(Point.new(3.0, 4.0))

    assert_in_delta unit.x, 0.6, 1.0e-15
    assert_in_delta unit.y, 0.8, 1.0e-15
    assert Point.normalize(Point.new(0.0, 2.0)) == Point.new(0.0, 1.0)
  end

  test "the accessors return their documented values" do
    assert Point.mag(Point.new(3.0, 4.0)) == 5.0
    assert Point.unit_x() == Point.new(1.0, 0.0)
    assert Point.unit_y() == Point.new(0.0, 1.0)
    assert Point.tolerance() == 1.0e-7
  end

  test "recenter/2 subtracts the centre, leaving nils alone" do
    points = [Point.new(1.0, 1.0), nil, Point.new(3.0, 3.0)]

    assert Point.recenter(points, Point.new(1.0, 1.0)) ==
             [Point.new(0.0, 0.0), nil, Point.new(2.0, 2.0)]
  end

  defp compile_diagnostics(expression) do
    module = "Girihelix.Engine.Geometry.PointTest.Probe#{System.unique_integer([:positive])}"

    {_result, diagnostics} =
      Code.with_diagnostics(fn ->
        Code.compile_string("defmodule #{module} do\n  def run, do: #{expression}\nend\n")
      end)

    diagnostics
  end
end

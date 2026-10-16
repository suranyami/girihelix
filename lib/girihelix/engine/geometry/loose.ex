defmodule Girihelix.Engine.Geometry.Loose do
  @moduledoc """
  Fuzzy comparisons — the tolerance surface of the port.

  Ported from `general/Loose.java`. Two constants, and one fact worth
  internalising before using either: **`near/3` applies its tolerance to a
  squared distance**, while `near/2` applies it to a difference. The Java reuses
  a single tolerance value for both, so in `Infer`'s escalating loop the `1e-12`
  floor is a linear radius of `1e-6`, and its `5.0` ceiling is a radius of about
  `2.24`.

  Three members of the Java class are deliberately omitted, because no code
  anywhere in the reference tree references them: `NEAR_TOL`, `lessThan/2` and
  `greaterThan/2`. Porting dead surface as though it were live invites someone to
  build on it. See `docs/algorithm-analysis.md`.
  """

  alias Girihelix.Engine.Geometry.Point

  @tol 1.0e-7
  @tol2 1.0e-10

  @doc "The linear tolerance, `1e-7`."
  @spec tol() :: float()
  def tol, do: @tol

  @doc """
  The squared tolerance, `1e-10`.

  Note this is a **literal in the Java, not `tol * tol`**, which would be
  `1e-14`. That is the whole reason this module and `Point` disagree.
  """
  @spec tol2() :: float()
  def tol2, do: @tol2

  @doc """
  Equality to within `tol/0`.

  Two clauses because the Java overloads on type, and they are not the same
  predicate: numbers have their difference compared against `tol/0`, points have
  a **squared** distance compared against `tol2/0`. Those thresholds sit 100x
  apart in linear terms, so a caller must know which it is asking for.
  """
  @spec equals(number(), number()) :: boolean()
  @spec equals(Point.t(), Point.t()) :: boolean()
  def equals(a, b) when is_number(a) and is_number(b), do: abs(a - b) < @tol
  def equals(%Point{} = a, %Point{} = b), do: Point.dist2(a, b) < @tol2

  @doc """
  Whether a quantity is negligible.

  A number has its magnitude compared against `tol/0`; a point has its squared
  magnitude compared against `tol2/0`. Because callers pass squared distances in
  some places and true distances in others, the *effective linear* radius here
  ranges from `1e-7` to about `3.16e-4` depending on the call site — the single
  most likely source of a subtly different map.
  """
  @spec zero(number() | Point.t()) :: boolean()
  def zero(a) when is_number(a), do: abs(a) < @tol
  def zero(%Point{} = a), do: Point.mag2(a) < @tol2

  @doc "Whether a **difference** is within an explicit tolerance."
  @spec near(number(), number()) :: boolean()
  def near(difference, tolerance) when is_number(difference) and is_number(tolerance), do: abs(difference) < tolerance

  @doc """
  Whether two points are within an explicit tolerance.

  The tolerance is applied to the **squared** distance, so passing a radius here
  is wrong by a square root. Every caller in `Infer` relies on this reading.
  """
  @spec near(Point.t(), Point.t(), number()) :: boolean()
  def near(%Point{} = a, %Point{} = b, tolerance), do: Point.dist2(a, b) < tolerance
end

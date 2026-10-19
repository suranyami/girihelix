# Engine types — design

**Date:** 2026-10-17
**Status:** approved 2026-10-18; implemented by
[the engine types plan](../plans/2026-10-19-girihelix-engine-types.md).
**Related:** [domain model design](2026-10-16-girihelix-domain-model-design.md) ·
[workbench design](2026-10-16-girihelix-workbench-design.md) ·
[porting specification](../../algorithm-analysis.md)

## Purpose

The engine currently protects itself with runtime checks. A malformed argument —
an empty polygon, a segment with no length, a singular transform — is refused at
the point of use by a function returning `{:error, reason}`, or in one case by
nothing at all.

This design moves the refusal earlier: make the malformed value **unrepresentable**,
so the function that would have rejected it never has to. The goal is that a
caller cannot pass a malformed parameter without a build failure, and that the
functions downstream become total — returning a bare value rather than a tuple a
caller must unwrap.

It also records what cannot be achieved that way, because that boundary is where
the design earns or loses its keep.

## What the toolchain already enforces

Measured on 2026-10-17 against Elixir 1.20.3 / OTP 29, not assumed. The compiler
row was re-measured and corrected on 2026-10-19:

| Mechanism | Enforces | Does not enforce |
| --- | --- | --- |
| The compiler, via inference | call sites against the types it infers from the callee's patterns, guards and body — a call a function head rules out is a warning, and an error under `--warnings-as-errors` | a `@spec` on its own, which constrains nothing at compile time; a function body against its own return spec |
| Dialyzer | a body against its spec; `call_without_opaque` when an opaque value is constructed outside its module | dynamic construction — `struct/2`, `apply/3` |
| `@opaque` | nothing at compile time (the compiler is silent on opacity) | `%Mod{}` literals, which still compile *and run* |

Two consequences shape everything below.

**The compiler polices callers and dialyzer polices bodies.** Together they close
the loop, and both are now in the gate: the compiler in `precommit.fast`, dialyzer
in `precommit`.

**`@opaque` makes misuse a dialyzer error, not an impossibility.** Elixir has no
private constructor. A struct literal is always legal; dialyzer objects when it can
see one. Measured behaviour: dialyzer catches *constructing* an opaque value
outside its module, and does **not** catch destructuring one. So opacity protects
fabrication, not secrecy — which is precisely the half this design needs, since
the failure mode being removed is a caller inventing an invalid value.

## The three tiers

Every decision below lands in one of three tiers, and the tier is chosen by asking
what kind of guarantee is available.

### Tier 1 — structural invariants: an opaque type and a smart constructor

When validity is a **property of the value itself** — non-empty, at least three,
two distinct points — the type carries it. The module declares the type opaque and
exposes the only sanctioned way to make one.

```elixir
defmodule Girihelix.Engine.Geometry.Segment do
  @opaque t :: %__MODULE__{from: Point.t(), to: Point.t()}
  @enforce_keys [:from, :to]
  defstruct [:from, :to]

  @spec new(Point.t(), Point.t()) :: {:ok, t()} | {:error, :coincident_points}
  def new(from, to), do: build(from, to, Point.dist2(from, to))

  defp build(_from, _to, squared_length) when squared_length == 0.0, do: {:error, :coincident_points}
  defp build(from, to, _squared_length), do: {:ok, %__MODULE__{from: from, to: to}}

  @spec new!(Point.t(), Point.t()) :: t()
  def new!(from, to), do: unwrap(new(from, to))
end
```

The invariant is `dist2 > 0.0`, not `from !== to`, for two reasons. On OTP 27
and later `0.0 === -0.0` is false, so strict equality would accept
`(0.0, 0.0)`–`(-0.0, 0.0)`, a segment of length zero. And two distinct points
closer than about `2e-162` have a squared distance that underflows to `0.0`,
which is exactly the divisor every consumer relies on.

A caller outside the module who passes a `%Segment{…}` literal to a function
typed `Segment.t()` gets `call_without_opaque` from dialyzer, which fails the
pre-push gate.

### Tier 2 — a function head: a caller cannot pass junk

Where the type already exists but the function accepts too much, narrow the
function head and let the compiler do the work. The non-empty list is the
clearest case: the pattern expresses "at least one" with no runtime check.

```elixir
@spec center([Point.t(), ...]) :: Point.t()
def center([_ | _] = points), do: ...
```

The **head** carries the guarantee. The compiler infers the accepted type from
it, rejects `Point.center([])` at the call site, and `--warnings-as-errors` makes
the build fail. The `@spec` alone would not: measured on 2026-10-19, a call
violating a spec over an unconstraining body compiled without a diagnostic. The
spec still matters, because dialyzer reads it.

### Tier 3 — numeric properties: a result tuple, and that is correct

Some validity is numeric and **no type can express it**: `n in 3..24`,
`q in -0.99..0.99`, `determinant != 0.0`. These keep a fallible constructor
returning `{:ok, t()} | {:error, reason}`, and the guarantee is that the failure
happens once, at construction, rather than being rediscovered downstream.

A result tuple in this tier is not a defeat. It is the only correct tool, and
pretending otherwise would mean a runtime check wearing a type's clothing.

## Applied to the engine as it stands

Every current error case, and what happens to it.

| Today | Tier | After |
| --- | --- | --- |
| `Point.parameterization_on_line/3` → `{:error, :degenerate_segment}` | 1 | **eliminated** — `parameterization_on_line/2` takes a `Segment`, so it returns `float()` |
| `Point.center/1` → `{:error, :no_points}` | 2 | **eliminated** — the head `[_ \| _]` rejects `[]` at the call site; returns `Point.t()` |
| `Polygon.area/1` → `{:error, :empty_polygon}` | 1 | **eliminated** — `Polygon.new/1` guarantees ≥3 vertices; returns `float()` |
| `Polygon.arc_length/2` → `{:error, :empty_polygon}` | 1 | **eliminated** — likewise |
| `Transform.reflect_through_line/2` → `{:error, :degenerate_line}` | 1 | **eliminated** — `reflect_through_line/1` takes a `Segment`; a line always exists; returns `t()` |
| `Transform.match_two_segments/4` → `{:error, :non_invertible}` | 1 | **eliminated** — `match_two_segments/2` takes two `Segment`s; `match_line_segment`'s determinant is the squared length of the segment, which is positive for distinct points |
| `Polygon.vertex/2` → `{:error, :out_of_range}` | — | **ambiguous**, see open questions — indexing is partial by nature |
| `Transform.invert/1` → `{:error, :non_invertible}` | 3 | **kept** — `det != 0.0` is numeric |
| `Transform.dist_from_inverted_zero/2` | 3 | **kept** — threads `invert/1` |
| `Intersect.*` → `nil` | 1 | **partly eliminated** — each entry point is now `/2` over two `Segment`s, which removes the degenerate reason; parallel and off-segment stay deliberately conflated, so `nil` stays |
| `Steps.run/3` returning an ok-or-error tuple | — | **unchanged** — already the idiomatic bang pair |

**The `Segment` type is the single largest win in this design.** It collapses five
separate error cases into one constructor, because every one of them is really the
same failure: two points that a caller believed were distinct turned out not to be.
Promoting that assumption into a type removes it as a *class* rather than handling
it at each site.

### Conventions

Settled by the above, and stated so later modules do not have to re-derive them:

- **A type with a structural invariant is `@opaque` and has a fallible `new/…`.**
- **A type without one is a plain `@type` with a total `new/…`.** `Point` and
  `Transform` are both in this class: any `(x, y)` is a point, and any six doubles
  are a transform — a singular transform is representable, only its *inverse* is
  conditional. Neither changes.
- **A fallible constructor returns `{:ok, t()} | {:error, reason}`, and its bang
  twin `new!/…` raises.** The bang pairing is Elixir's own convention, not a
  concession.
- **`reason`s are atoms naming the failure**, not strings and not exceptions.
- **Never narrate the source language in the docs.** Where a divergence from
  Taprats needs recording, record the *decision and its reason*, in
  `docs/algorithm-analysis.md` or the porting notes.

## Where this reaches next

- **Plan 3's figure constructors carry the most weight.** Star's `n`/`d`/`s` and
  Rosette's `n`/`q`/`s` hold every clamp the porting spec calls behavioural. Once
  those are fallible constructors, each figure builder becomes total and the error
  cases vanish at the source rather than being threaded through `build_unit`. This
  is tier 3, since the clamps are numeric.
- **`PlanarMap` should be `@opaque`**, but it exposes the boundary between the
  tiers. Its invariant — no edge crossing another — is a property of the
  *accumulated structure*, not of any argument, so no constructor can enforce it.
  It stays a documented precondition, exactly as the corrected analysis document
  says the Java leaves it, with the same fast unchecked path and one checked
  variant for callers who want it.
- **Numeric predicates cannot be typed, and that is the honest boundary.** A type
  can say "at least three" or "two distinct points". It cannot say "between −0.99
  and 0.99". Ranges are tier 3 forever.

## Cost

- **A public API change in the engine.** Constructors gain result tuples and one
  new type appears. Nothing is released, so there is no migration, but the Plan 1a
  tests change again.
- **Opacity is a discipline as much as a mechanism.** It is invisible at compile
  time and only enforced by dialyzer, so it works as long as dialyzer stays in the
  gate. Removing dialyzer to speed up a push would silently disable every tier 1
  guarantee.
- **The retrofit is small.** Six call sites in `Point`, `Polygon` and `Transform`,
  one new module, and test updates.

## Resolved at review

The five calls this design left open were settled on 2026-10-19:

1. **`Polygon`'s invariant is "at least 3 vertices" only.** Distinctness would be
   O(n²) and would need a tolerance — `Point.equals/2`'s `1e-14` or
   `Loose.equals/2`'s `1e-10` — which is a semantic choice, not a check. It stays
   the caller's responsibility, and the docs say so.
2. **`Polygon.vertex/2` keeps its result tuple.** Indexing is partial by nature,
   and the function mirrors `Enum.fetch/2`. A negative index is out of range.
3. **`Transform.invert/1` stays public and returns error tuples**, alongside
   `invert!/1`.
4. **Retrofit now, before Plan 1b**, so 1b is written against the finished
   conventions and two idioms never coexist.
5. **The conventions live in `AGENTS.md`** and in each plan's Global Constraints,
   so every future plan inherits them.

## Decisions taken

- **Three tiers, chosen by the kind of guarantee available** — a structural
  invariant is typed, a loose spec is sharpened, a numeric property keeps a result
  tuple.
- **`@opaque` for types with invariants, plain `@type` for types without.** No
  opacity for its own sake: `Point` and `Transform` are unchanged.
- **Segment-based constructors as the primary vehicle**, since one type removes a
  class of failure across `Point`, `Intersect` and `Transform` at once.
- **`nil` stays in `Intersect`.** Parallel and off-segment are deliberately
  indistinguishable in the source, and an error tuple would invent a distinction
  the algorithm does not make.
- **Dialyzer is load-bearing, not advisory**, and has been added to the `precommit`
  alias. Type errors now fail the push.

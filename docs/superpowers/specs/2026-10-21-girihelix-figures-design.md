# Figures — design (Plan 3)

**Date:** 2026-10-21
**Status:** implemented 2026-10-21 (Plan 3). Every decision not inherited from an
earlier design is marked "my call".
**Related:** [workbench design](2026-10-16-girihelix-workbench-design.md) ·
[engine types design](2026-10-17-girihelix-engine-types-design.md) ·
[domain model design](2026-10-16-girihelix-domain-model-design.md) ·
[planar map design](2026-10-20-girihelix-planar-map-design.md) ·
[porting specification](../../algorithm-analysis.md) ·
local only: `reference/porting-notes/figures.md`

## Intent

Figures are the decoration step of the engine. A `Feature` is a tile; a figure is
the linework drawn inside it. Plan 4's instancing pass takes a figure's map,
places it once per feature, and welds the results. Plan 5's styles draw the
welded map. Neither can start until a figure can build its map.

This plan ports the five figure builders and their shared base:

- **`Star`:** the continuous `[n/d]s` construction, from intersecting chords of
  the unit circle.
- **`Rosette`:** Lee's construction, a ray swept around the tip and intersected
  with rotated copies of itself.
- **`ScaleFigure`:** a child figure scaled by `s` and pulled out to its n-gon
  cell.
- **`ConnectFigure`:** a `ScaleFigure` whose `s` is solved so neighbouring
  cells' extended edges meet.
- **`ExplicitFigure`:** a map supplied by the caller, returned unchanged.

`Figure` and `RadialFigure` are the two abstractions the five share.

The workbench gains five exhibits — `star`, `rosette`, `scale`, `connect`,
`radial` — so each construction can be watched one stage at a time. The
workbench is also the verification instrument: a rendered figure shows a lost
vertex or a doubled seam immediately, where a vertex count only says something
is wrong.

## Inherited decisions

These are settled and are not re-decided here.

- **Faithful first.** Reproduce Taprats 1.1.12's output, flaws included. Each
  flaw is recorded at one named function and pinned by a test.
- **Algorithm separated from busy-work.** The geometric decisions are small
  named pure functions; iteration is plain `Enum`.
- **Constructors are fallible (tier 3).** Numeric clamps cannot be typed, so
  `new/…` returns `{:ok, struct} | {:error, reason}` and `new!/…` raises. The
  reasons are atoms.
- **Step sequences.** Every figure with internal stages exposes `steps/…`, a
  start state, and `result/1`. The plain builder is the steps run, pinned by a
  test.
- **Engine purity and the hard rules.** `lib/girihelix/engine/**` uses the
  standard library only. No `if` or `cond`; branch in function heads and guards.
- **`PlanarMap` is reached only through its public API.** Vertices and edges are
  handles; no module matches `%PlanarMap{}`.
- **Coordinates are `Point.t()`, rotations are `Transform.t()`.**

## The clamp tension, resolved

The source clamps parameters inside `buildUnit` (Star, ScaleFigure), in the
constructor (Rosette's `s`), or not at all and then relies on a tolerance test
(ScaleFigure's `s == 1`). The engine-types design says constructors carry the
clamps, so the builder becomes total and the clamps are not rediscovered. The
workbench design says clamps are **steps**, because a threshold the source
applies is behaviour worth seeing.

Both are satisfied by one rule, and it is the decision this plan is built on:

> **Each figure has one shared clamp function, called by both the constructor
> and the `:clamp` step. The constructor stores the clamped values.**

Consequences, stated so the plan does not have to rediscover them:

- `Star.clamp_d/2`, `Star.clamp_s/2`, `Rosette.clamp_q/1`,
  `Rosette.clamp_s/2`, `ScaleFigure.normalise_s/1` and
  `ConnectFigure.compute_scale/1` are public, pure and idempotent.
- The `:clamp` step calls the same function and records the requested and the
  clamped value in its state, so the frame's label and the panel can say
  `d = 99.0 clamped to 3.99`.
- Frame zero holds the parameters exactly as received. The `:clamp` frame holds
  the figure struct and its clamped values.
- **`build_unit/1` is total in the result sense:** it returns a
  `PlanarMap.t()`, never `{:ok, map}` or `{:error, reason}`. It may still
  **raise** where the source crashes (a failed intersection in Star, a missing
  tip in ScaleFigure). A geometric degeneracy is not a parameter error and the
  constructor cannot predict it without building the figure. `Steps.run/3`
  renders such a raise as a failure frame; `Steps.run!/3` re-raises it, which is
  the engine's faithful path.
- **Star is the one exception to "store only the clamped value".** Its closure
  chord uses the **unclamped** `d` (`getArc(d * don)`) while every other chord
  uses the clamped one. The struct therefore keeps `d` (as requested) **and**
  `clamp_d` (as applied). Dropping the raw value would silently change the
  closure geometry whenever `d` was clamped.

## Common model

### `Girihelix.Engine.Figures.Figure`

The behaviour and the dispatcher for the two operations every figure supports.

```elixir
@type t ::
        Girihelix.Engine.Figures.Star.t()
        | Girihelix.Engine.Figures.Rosette.t()
        | Girihelix.Engine.Figures.ScaleFigure.t()
        | Girihelix.Engine.Figures.ConnectFigure.t()
        | Girihelix.Engine.Figures.ExplicitFigure.t()

@callback build_unit(t()) :: Girihelix.Engine.PlanarMap.t()

@spec unit(t()) :: Girihelix.Engine.PlanarMap.t()
@spec map(t()) :: Girihelix.Engine.PlanarMap.t()
@spec radial?(t()) :: boolean()
```

- `unit/1` dispatches to the module's `build_unit/1`. It is the basic unit,
  before the c_n replication.
- `map/1` is the whole figure. For a radial figure it is `RadialFigure.map/1`;
  for `ExplicitFigure` it is the stored map itself (immutability makes the
  source's defensive clone unnecessary).
- `radial?/1` is what `ScaleFigure.new/2` and `ConnectFigure.new/1` use to
  refuse an `ExplicitFigure` child. It exists so no caller pattern-matches a
  struct to answer the question.
- **`n/1` is a `RadialFigure` callback, not a `Figure` callback.** That is what
  lets `ExplicitFigure` implement `Figure` without inventing a symmetry order
  it does not have.
- **A radial figure declares only `RadialFigure`; `ExplicitFigure` declares
  `Figure`.** Both behaviours carry `build_unit/1`, and a module cannot declare
  both without Elixir's conflicting-behaviours warning, which fails the
  warnings-as-errors gate. `Figure.unit/1` dispatches to the struct's module, so
  the split changes no caller.

### `Girihelix.Engine.Figures.RadialFigure`

A behaviour for the four radial figures plus the derived state and the
replication ladder. It is **not** a struct: `n` is a field on each figure, and
`don` and `Tr` are pure functions of `n`, so storing them would create a second
source of truth.

```elixir
@type t ::
        Girihelix.Engine.Figures.Star.t()
        | Girihelix.Engine.Figures.Rosette.t()
        | Girihelix.Engine.Figures.ScaleFigure.t()
        | Girihelix.Engine.Figures.ConnectFigure.t()

@callback build_unit(t()) :: Girihelix.Engine.PlanarMap.t()
@callback n(t()) :: pos_integer()

@spec don(pos_integer()) :: float()
@spec tr(pos_integer()) :: Girihelix.Engine.Geometry.Transform.t()
@spec arc(float()) :: Girihelix.Engine.Geometry.Point.t()
@spec mirror(Girihelix.Engine.Geometry.Point.t()) :: Girihelix.Engine.Geometry.Point.t()
@spec unit_ngon(pos_integer()) :: [Girihelix.Engine.Geometry.Point.t()]
@spec ladder(pos_integer()) :: [Girihelix.Engine.Geometry.Transform.t()]
@spec map(t()) :: Girihelix.Engine.PlanarMap.t()
```

- `don(n) = 1.0 / n`; `tr(n) = Transform.rotate(2.0 * :math.pi() * don(n))`;
  `arc(frac) = Point.new(:math.cos(frac * 2pi), :math.sin(frac * 2pi))`. `arc`
  accepts negative and greater-than-one fractions; it must not normalise.
- `mirror(p) = Point.new(p.x, -p.y)`.
- `unit_ngon(n)` is `arc(k * don(n))` for `k = 0..n-1`, counter-clockwise from
  `(1, 0)`.
- `ladder(n)` is the source's transform list: `Tr, Tr^2, …, Tr^n`, built by
  chaining `Transform.compose/2` from a starting `Tr`. **It does not start at
  the identity.** The last copy therefore carries the rounding of `n`
  compositions, exactly as the source does.
- `map(figure)` builds the unit and replicates it into an empty map:
  `PlanarMap.replicate!(PlanarMap.new(), unit, ladder(n))`. `replicate/3`
  coalesces vertices by the `1e-7` square window and does not split edges,
  which is the source's `mergeSimpleMany` behaviour. The unit is never placed
  untransformed.

`n` is derived, never duplicated: `ScaleFigure` and `ConnectFigure` answer
`n(child)`. `n >= 3` is a constructor invariant for every radial figure,
because `unit_ngon/1` and the clamps below assume it.

### Shared map-building helpers

Two details are common to Star and Rosette and are named helpers, not
duplicated:

- **The mirrored chain assembly.** Insert the tip `(1, 0)`, then for each point
  in order insert the point, insert its mirror as a fresh vertex, insert the
  top edge from the previous top vertex, insert the bottom edge from the
  previous bottom vertex, and carry both handles forward. The first step's two
  edges leave the tip **top then bottom**, which fixes the ring head and hence
  every later neighbour scan.
- **The c_n map.** `RadialFigure.map/1`, above.

## Star

### Behaviour

The unit is a symmetric chain of the crossings of one base chord with rotated
copies of itself. `n` is the symmetry order, `d` the (continuous) skip, `s` how
many crossings the unit takes. Defaults, for the exhibit and for a caller who
wants the source's default figure: `n = 8`, `d = 3.0`, `s = 2`.

The unit grows from `a = (1, 0)` to `b = arc(clamp_d * don)`. For
`idx = 1..outer_s`, the chord `(a, b)` is intersected with
`arc(idx * don) → arc((idx - clamp_d) * don)`; each crossing is inserted with
its mirror. The unit closes at the rotated apex when `clamp_s == di`: one edge
when `d` is integral, and otherwise an extra vertex `cent` at the intersection
of `arc(did * don) → arc(-dfrac * don)` with `a → arc(d * don)`.

### Parameters, defaults and clamps

| Parameter | Type | Default | Clamp |
| --- | --- | --- | --- |
| `n` | `integer` | `8` | accepted when `n >= 3`, else `:invalid_order` |
| `d` | `float` | `3.0` | `max(1.0, min(d, 0.5 * n - 0.01))`, stored as `clamp_d`; raw `d` also stored |
| `s` | `integer` | `2` | accepted when `s >= 0`; stored as `min(s, di)` where `di` is the **pre-snap** floor of `clamp_d` |

The constructor computes `di` from `clamp_d` exactly as the build does, so the
stored `s` is the source's `clamp_s`. `s < 0` is `:invalid_step_count`: the
source would allocate a negative-length array.

The `dfrac` snap is part of the clamp, not of the chord step, and belongs in the
`:clamp` step: with `dfrac < 1e-7` it becomes `0.0` and `is_int` is true; with
`1.0 - dfrac < 1e-7` it becomes `0.0`, `di` increments and `is_int` is true;
otherwise both stay and `is_int` is false. `outer_s = min(s, di - 1)` uses the
**pre-increment** `di`, so the near-one path is one step short and cannot close.
That is faithful, and is pinned by a test.

### Interface

```elixir
@enforce_keys [:n, :d, :clamp_d, :s]
defstruct [:n, :d, :clamp_d, :s]

@type t :: %__MODULE__{n: pos_integer(), d: float(), clamp_d: float(), s: non_neg_integer()}
@type reason :: :invalid_order | :invalid_step_count
@type state :: %{
        n: pos_integer(),
        d: float(),
        s: integer(),
        figure: t() | nil,
        map: Girihelix.Engine.PlanarMap.t() | nil,
        di: integer() | nil,
        dfrac: float() | nil,
        is_int: boolean() | nil,
        outer_s: integer() | nil,
        points: [Girihelix.Engine.Geometry.Point.t()],
        top: Girihelix.Engine.PlanarMap.vertex() | nil,
        bottom: Girihelix.Engine.PlanarMap.vertex() | nil
      }

@spec new(pos_integer(), float(), integer()) :: {:ok, t()} | {:error, reason()}
@spec new!(pos_integer(), float(), integer()) :: t()
@spec clamp_d(pos_integer(), float()) :: float()
@spec clamp_s(integer(), integer()) :: non_neg_integer()

@spec start(pos_integer(), float(), integer()) :: state()
@spec steps(pos_integer(), float(), integer()) :: [Girihelix.Engine.Steps.Step.t()]
@spec result(state()) :: Girihelix.Engine.PlanarMap.t()
@spec build_unit(t()) :: Girihelix.Engine.PlanarMap.t()
```

`build_unit(%Star{n: n, d: d, s: s})` is
`steps(n, d, s) |> Steps.run!(start(n, d, s)) |> Steps.final() |> result()`.
The values passed back through `start/3` are the struct's raw `d` and clamped
`s`; both clamps are idempotent, so the rebuilt struct equals the receiver.

### Stages

| Id | Label | What it does |
| --- | --- | --- |
| `:clamp` | clamp d and s | Builds the struct, snaps `dfrac`, records `di`, `is_int`, `outer_s` |
| `:chord` | the base chord | `a = (1, 0)`, `b = arc(clamp_d * don)` |
| `:crossings` | the crossings | One intersection per `idx = 1..outer_s`, no mirroring yet |
| `:assemble` | mirror and insert | Inserts the tip, each point and its mirror, and the two chains |
| `:closure` | close the unit | The `clamp_s == di` edge, or the `cent` intersection and two edges |

A failed crossing raises `ArgumentError` naming `:degenerate_crossing`; the
source stores `null` and crashes at the next dereference, so a raise is the
faithful outcome. `cent` is found with the **raw** `d`, as the source does.

## Rosette

### Behaviour

Lee's construction. `q` controls sharpness, `s` how far the unit reaches. The
unit is the tip, the key point, and up to `s` intersections of the key line
with its rotated mirror, each with its y-mirror; `c_n` supplies the rest.

The frame is built from `r_outer = 1 / cos(pi * don)`,
`up_outer = arc(0.5 * don) * r_outer`, and
`bisector = (up_outer - (0, r_outer)) * 0.5`. **`bisector` is half the
difference vector, not the midpoint of a segment.** The ray angle starts at
`angle(tip -> arc(don))` and blends: toward `pi/2` for `q >= 0`, toward
`stable_angle` for `q < 0`, where
`stable_isect = up_outer + normalize(up_outer) * (-up_outer.y)`. Then
`qtip = (1 + cos(th), sin(th))`, `key_point` is the crossing of `(tip, qtip)`
with `(up_outer, bisector)`, and
`key_end = Point.convex_sum(key_point, stable_isect, 10.0)` — a ten-fold
extrapolation past `stable_isect`, not a ten-unit segment.

### Parameters, defaults and clamps

| Parameter | Type | Default | Clamp |
| --- | --- | --- | --- |
| `n` | `integer` | `8` | accepted when `n >= 3`, else `:invalid_order` |
| `q` | `float` | `0.0` | `min(max(q, -0.99), 0.99)`, stored clamped |
| `s` | `integer` | `3` | `min(s, div(n - 1, 2))`, stored clamped; `s < 0` is `:invalid_step_count` |

The source recomputes `s_clamp` inside the builder even though the field is
already clamped. With the constructor storing the clamped value, the redundant
recomputation is collapsed; it has no effect, and the porting notes record that
the 0.3 and 1.1.12 builds are otherwise identical. `build_unit` uses the stored
`s` directly.

### Interface

```elixir
@enforce_keys [:n, :q, :s]
defstruct [:n, :q, :s]

@type t :: %__MODULE__{n: pos_integer(), q: float(), s: non_neg_integer()}
@type reason :: :invalid_order | :invalid_step_count
@type state :: %{
        n: pos_integer(),
        q: float(),
        s: integer(),
        figure: t() | nil,
        map: Girihelix.Engine.PlanarMap.t() | nil,
        frame: map() | nil,
        points: [Girihelix.Engine.Geometry.Point.t()],
        top: Girihelix.Engine.PlanarMap.vertex() | nil,
        bottom: Girihelix.Engine.PlanarMap.vertex() | nil,
        skipped: non_neg_integer()
      }

@spec new(pos_integer(), float(), integer()) :: {:ok, t()} | {:error, reason()}
@spec new!(pos_integer(), float(), integer()) :: t()
@spec clamp_q(float()) :: float()
@spec clamp_s(pos_integer(), integer()) :: non_neg_integer()
@spec with_q(t(), float()) :: t()
@spec with_s(t(), integer()) :: t()

@spec start(pos_integer(), float(), integer()) :: state()
@spec steps(pos_integer(), float(), integer()) :: [Girihelix.Engine.Steps.Step.t()]
@spec result(state()) :: Girihelix.Engine.PlanarMap.t()
@spec build_unit(t()) :: Girihelix.Engine.PlanarMap.t()
```

`with_q/2` and `with_s/2` are the immutable setters; `with_s/2` applies
`clamp_s/2`, mirroring the source's `setS`. They exist for Plan 4 and the
studio, which re-parameterise a figure without rebuilding it from raw values.

### Stages

| Id | Label | What it does |
| --- | --- | --- |
| `:clamp` | clamp q and s | Builds the struct and records requested versus clamped values |
| `:frame` | the outer frame | `r_outer`, `up_outer`, `bisector`, `th`, `stable_isect`, `stable_angle` |
| `:blend` | blend the ray | The `q >= 0` or `q < 0` blend of `th` |
| `:key` | key point and key line | `qtip`, `key_point`, `key_end`, and both mirrored key points |
| `:walk` | rotate and intersect | Up to `s` accumulated rotations of the mirrored key line, skipping a failed crossing |
| `:assemble` | mirror and insert | The shared tip-and-two-chains assembly |

### The FIXME

A failed per-step crossing is **skipped**, not substituted: the write index is
not advanced, and the assembly bridges the gap with one longer edge on both
chains. The canonical trigger is `n = 12, q = -0.8, s = 4`. The state counts
skips in `:skipped`, so the panel can report them, and a golden scenario pins
the resulting vertex count. This is faithful option 2 from the porting notes:
reproduce the skip and record it.

`key_point` has no null guard in the source beyond the crash it causes; a null
there raises `ArgumentError` naming `:degenerate_key`.

## ScaleFigure

### Behaviour

`ScaleFigure(child, s)` builds the child's unit, finds its tip, scales the unit
by `s`, and extends the figure to its n-gon cell:

1. If `s` is within `1e-7` of `1.0`, return the child's unit **unchanged**.
2. Find the vertex within `1e-5` of `(1, 0)`, in the child map's vertex order;
   error when there is none.
3. Scale every position by `s`.
4. Build the clipping n-gon `unit_ngon(n)`, unscaled.
5. Find the tip's first neighbour with `y < 0.0` in ring order; error when there
   is none.
6. Extend the ray from the tip away from that neighbour by 100 units, and clip
   it against the first n-gon edge it meets; fall back to the tip.
7. Intersect the clipped segment with its mirrored-and-rotated copy, for
   `div(n + 1, 2)` iterations, inserting each crossing and its mirror; stop at
   the first failed intersection.
8. Insert the endpoint last, and add its edge and its mirror's edge only when
   the endpoint did not coalesce onto the chain's current top vertex.

Step 6's fallback is deliberate: a zero-length extension is still inserted.
Step 8's conditional is a **vertex-identity** test in the source; handles give
the same answer.

### Parameters, defaults and clamps

| Parameter | Type | Clamp |
| --- | --- | --- |
| `child` | a radial figure | `:not_radial` for an `ExplicitFigure` |
| `s` | `float` | `1.0` when `abs(s - 1.0) < 1e-7`, else `s`; stored normalised |

`normalise_s/1` is shared by the constructor and the `:clamp` step. Storing
`1.0` for a near-one scale makes the passthrough an exact comparison and makes
ConnectFigure's half-step rotation test exact in the same way. The source's
`Loose.equals` tests are thereby evaluated once, at construction.

There is no upper or lower clamp on `s`; it is a scale, and a negative or zero
scale is representable. `s = 0` collapses the unit and the tip lookup then
fails, which is a geometric degeneracy and raises.

### Interface

```elixir
@enforce_keys [:child, :s]
defstruct [:child, :s]

@type t :: %__MODULE__{child: Girihelix.Engine.Figures.RadialFigure.t(), s: float()}
@type reason :: :not_radial
@type state :: %{
        child: Girihelix.Engine.Figures.RadialFigure.t(),
        requested_s: float(),
        figure: t() | nil,
        map: Girihelix.Engine.PlanarMap.t() | nil,
        passthrough: boolean() | nil,
        tip: Girihelix.Engine.PlanarMap.vertex() | nil,
        below: Girihelix.Engine.PlanarMap.vertex() | nil,
        endpoint: Girihelix.Engine.Geometry.Point.t() | nil
      }

@spec new(Girihelix.Engine.Figures.Figure.t(), float()) :: {:ok, t()} | {:error, reason()}
@spec new!(Girihelix.Engine.Figures.Figure.t(), float()) :: t()
@spec normalise_s(float()) :: float()
@spec with_s(t(), float()) :: t()
@spec with_child(t(), Girihelix.Engine.Figures.Figure.t()) :: {:ok, t()} | {:error, reason()}

@spec build_unit(t()) :: Girihelix.Engine.PlanarMap.t()
@spec build_unit(Girihelix.Engine.Figures.RadialFigure.t(), float()) :: Girihelix.Engine.PlanarMap.t()
@spec start(Girihelix.Engine.Figures.RadialFigure.t(), float()) :: state()
@spec steps(Girihelix.Engine.Figures.RadialFigure.t(), float()) :: [Girihelix.Engine.Steps.Step.t()]
@spec result(state()) :: Girihelix.Engine.PlanarMap.t()
```

`build_unit/2` is the shared implementation, so `ConnectFigure` can call the
scale stage without constructing a `%ScaleFigure{}`.

### Stages

| Id | Label | What it does |
| --- | --- | --- |
| `:clamp` | normalise s | Builds the struct; records the passthrough decision |
| `:child` | build the child unit | Builds the child figure's unit |
| `:scale` | find the tip and scale | The tip lookup and the uniform scale |
| `:clip` | clip to the n-gon | The border, the lower neighbour, the 100-unit ray and the clipped endpoint |
| `:extend` | extend by rotated copies | The `div(n + 1, 2)` intersections and mirrored insertions |
| `:endpoint` | add the endpoint | Inserts the endpoint and conditionally its edge and mirror |

On the passthrough path `:child` returns the child's unit and `:scale`,
`:clip`, `:extend` and `:endpoint` are no-ops; `passthrough` is true, and the
panel says so. Every stage still runs, so the step count does not depend on the
value.

## ConnectFigure

### Behaviour

A `ScaleFigure` whose scale is solved, not supplied:

- Build the child's unit at unit scale.
- In vertex order, find a vertex within `1e-5` of `(1, 0)` that has a neighbour
  with `y < 0.0`; if none, the scale is `1.0`.
- Take the 100-unit ray from the tip away from that neighbour, and its
  mirror, then rotate the mirror by one step: the moving segment is
  `Tr(tip) → Tr(mirror(seg_end))`.
- Intersect it with the full-length ray. On a failed intersection the scale is
  `1.0`; otherwise `cos(pi / n) / |isect|`.

`build_unit` is then four stages: the `ScaleFigure` stage, `rotate_half`, an
optional half-step rotation, and the normalisation.

- **`rotate_half`** selects every vertex with `y > -1e-7` (the axis and above),
  inserts each one's copy rotated by `-2pi/n`, adds an edge between the copies
  of every edge whose **both** ends were selected, then deletes the originals
  with `y > 1e-7` strictly. The two different tolerances leave a thin seam on
  the axis: the `|y| <= 1e-7` band keeps its originals as well as their rotated
  copies, rather than being moved wholesale. Handles replace the identity-keyed
  table exactly.
- **The half-step rotation** by `pi/n` runs only when the normalised `s` is not
  `1.0`, and is a full `PlanarMap.transform!/2` (positions, ring angles, both
  orders), not a scale.
- **`scale_to_unit`** scales by `1 / max_x`. A zero maximum is impossible for a
  well-formed unit, because the fold keeps the apex at `(1, 0)`; the port raises
  `ArgumentError` naming `:zero_extent` rather than carrying an infinity.

The `s = 1.0` fallback couples the two figures: the connect transform becomes a
no-op for the scaling stage, so `rotate_half` mutates the child's freshly built
unit. That is safe in this port because `build_unit` always returns a new map.

### Parameters, defaults and clamps

| Parameter | Type | Clamp |
| --- | --- | --- |
| `child` | a radial figure | `:not_radial` for an `ExplicitFigure` |
| `s` | derived `float` | `compute_scale(child)`, then `normalise_s/1`; stored |

`compute_scale/1` is the shared "clamp" function: the constructor calls it to
set `s`, and the `:clamp` step records the derived value and whether it is the
fallback. The three `1.0` fallbacks (no tip at all, a tip with
no lower neighbour, and a failed intersection) are indistinguishable in the
derived scale. The build state records only that the scale is `1.0` — the
`fallback` boolean — for the panel, without changing the geometry; it does not
claim which of the three produced it.

### Interface

```elixir
@enforce_keys [:child, :s]
defstruct [:child, :s]

@type t :: %__MODULE__{child: Girihelix.Engine.Figures.RadialFigure.t(), s: float()}
@type reason :: :not_radial
@type state :: %{
        child: Girihelix.Engine.Figures.RadialFigure.t(),
        figure: t() | nil,
        map: Girihelix.Engine.PlanarMap.t() | nil,
        fallback: nil | :no_tip | :no_lower_neighbour | :parallel,
        max_x: float() | nil
      }

@spec new(Girihelix.Engine.Figures.Figure.t()) :: {:ok, t()} | {:error, reason()}
@spec new!(Girihelix.Engine.Figures.Figure.t()) :: t()
@spec compute_scale(Girihelix.Engine.Figures.RadialFigure.t()) :: float()
@spec child_changed(t()) :: t()

@spec start(Girihelix.Engine.Figures.RadialFigure.t(), float()) :: state()
@spec steps(Girihelix.Engine.Figures.RadialFigure.t(), float()) :: [Girihelix.Engine.Steps.Step.t()]
@spec result(state()) :: Girihelix.Engine.PlanarMap.t()
@spec build_unit(t()) :: Girihelix.Engine.PlanarMap.t()
```

`build_unit(%ConnectFigure{child: child, s: s})` uses the stored `s`. It does
not recompute the scale, which mirrors the source constructor computing it
once. `child_changed/1` re-derives `s` from the child, mirroring the source's
`childChanged`.

### Stages

| Id | Label | What it does |
| --- | --- | --- |
| `:clamp` | derive the scale | Records the derived `s` and any fallback |
| `:scale_clip` | scale and clip the child | The whole `ScaleFigure.build_unit/2` |
| `:fold` | fold the upper half | `rotate_half`: copy down one step, add permuted edges, delete originals |
| `:half_step` | rotate by half a step | `pi/n` when `s` is not `1.0` |
| `:normalise` | scale to unit | Divide by the maximum x |

The `:scale_clip` stage is coarse: the `scale` exhibit shows its internals, and
the `connect` exhibit shows the post-passes that are specific to it. This is the
same accepted granularity trade-off the workbench design records for
`mergeMap` and `extractFaces`.

## ExplicitFigure

A map supplied by the caller. There is nothing to construct and no step
sequence.

```elixir
@enforce_keys [:map]
defstruct [:map]

@type t :: %__MODULE__{map: Girihelix.Engine.PlanarMap.t()}
@type reason :: :not_a_map

@spec new(Girihelix.Engine.PlanarMap.t()) :: {:ok, t()} | {:error, reason()}
@spec new!(Girihelix.Engine.PlanarMap.t()) :: t()
@spec build_unit(t()) :: Girihelix.Engine.PlanarMap.t()
```

`new/1` returns `{:error, :not_a_map}` for anything that is not a
`PlanarMap.t()`, which is only reachable from a dynamic caller; the tuple and
its bang twin are kept because every figure constructor has the same shape.
`build_unit/1` returns the stored map. Maps are immutable, so the source's
defensive clone disappears.

No harness operation is needed: `ExplicitFigure` wraps a map the existing
`dump` already describes, and the round trip is a unit test.

## Step sequences, summary

| Module | Start | Steps | Result | Plain builder |
| --- | --- | --- | --- | --- |
| `Star` | `start/3` | `steps/3` | `result/1` | `build_unit/1` |
| `Rosette` | `start/3` | `steps/3` | `result/1` | `build_unit/1` |
| `ScaleFigure` | `start/2` | `steps/2` | `result/1` | `build_unit/1`, `build_unit/2` |
| `ConnectFigure` | `start/2` | `steps/2` | `result/1` | `build_unit/1` |
| `ExplicitFigure` | none | none | none | `build_unit/1` |

Every plain builder is exactly
`steps(...) |> Steps.run!(start(...)) |> Steps.final() |> result()`, and a test
pins each pair. `Figure.map/1` is the c_n replication on top of the unit.

## The harness

The reference harness stays local-only and is never committed. It gains one
terminal script operation with two modes and a recursive figure expression.

### Script syntax

```text
figure map <expr>
figure unit <expr>

<expr> := star <n> <d> <s>
        | rosette <n> <q> <s>
        | scale <expr> <s>
        | connect <expr>
```

`n` and `s` are integers; `d`, `q` and the scale accept any Java double
literal, including one written without a decimal point. Examples:

```text
figure map star 8 3.0 2
figure unit rosette 12 -0.8 4
figure map scale rosette 8 0.0 3 1.5
figure map connect scale star 8 3.0 2 1.4
```

`figure map` calls `getMap()`; `figure unit` calls `buildUnit()`. Both are
terminal: like `faces` and `fill`, they replace the final `dump` line. The
expression parser is recursive and postfix for `scale`, so no parentheses are
needed and no expression is ambiguous.

### Dump expectations

A successful figure dump is a header followed by **the existing map dump body,
unchanged**:

```text
figure ok
vertices 8
v 1.0 0.0
...
edges 8
e 0 1
...
rings
r 0 ...
verify true
```

`figure unit` uses the same body with the header `figure unit ok`. Structure is
compared exactly and coordinates to `1e-12`, as the existing map goldens do.
Where Java throws a `NullPointerException`, the dump is the single line
`figure error null`; the Elixir side maps any raise from the port to
`{:error, :null}` and compares that. A port raise is the faithful outcome for
those parameters, so the golden also pins that the port still crashes there.

### Harness changes

- `HarnessDriver.java` gains `parseFigure(String[] tokens, int from, int to)`
  returning a `Figure`, and the terminal `figure` branch. Reuse the existing
  `Map` dump by extracting its body into `mapDump(Map)`, so the figure dump and
  the map dump cannot drift.
- `Girihelix.TapratsHarness` gains:
  - a parsed expression type
    `{:star, n, d, s} | {:rosette, n, q, s} | {:scale, expr, s} | {:connect, expr}`;
  - the ops `{:figure, :map | :unit, expr}`;
  - `build_figure/1`, which constructs with the port's `new!/…` and returns
    `Figure.map/1` or `Figure.unit/1`;
  - `%{figure: {:ok, map_dump} | {:error, :null}}` as a dump shape;
  - a `compare/2` clause for it, reusing the map comparison.

### Golden scenarios

One scenario per construction, plus the clamps and the documented failures:

| Scenario | Pins |
| --- | --- |
| `figure-star-default` | `Star(8, 3.0, 2)`: five-vertex unit, open chains, `clamp_s != di` |
| `figure-star-unit` | The unit before replication |
| `figure-star-fractional` | `d = 2.5`: `is_int` false and the `cent` closure |
| `figure-star-closure` | `s = 3`: the closure fires with an edge |
| `figure-star-clamped` | `d = 99`: the clamp, with the raw `d` still driving `cent` |
| `figure-star-crash` | Parameters whose crossing fails: `figure error null` |
| `figure-rosette-default` | `Rosette(8, 0.0, 3)` |
| `figure-rosette-negative-q` | `q = -0.5`: the stable-ray blend |
| `figure-rosette-clamped` | `q = 2.0, s = 9`: both clamps |
| `figure-rosette-fixme` | `(12, -0.8, 4)`: the skipped step and the bridged edge |
| `figure-scale-passthrough` | `s = 1.0`: the child unit unchanged |
| `figure-scale-rosette` | A nested rosette scaled and clipped |
| `figure-connect-rosette` | The solved scale and the three post-passes |
| `figure-connect-star` | The same with a Star child, whose ring head differs |
| `figure-connect-nested` | `connect scale rosette …` and `connect connect …` layering |

## The exhibits

All five are `category: :figures` and are registered after the geometry
exhibits. Each uses the framework unchanged: declarative `params/0`, an
`initial/1` that builds the engine's start state, `steps/1` delegating to the
engine, a `draw/2` that reads the frame's state, and a `reproduce/1` holding the
plain call.

The shared drawing contract, so the five do not invent markup:

- The **whole map** is drawn as `{:line, from, to, []}` for every edge, in map
  edge order.
- The **unit** is drawn as a heavier line (`width: 2.0`) over the whole map,
  so the replicated region and the unit read together.
- **Vertices** are `{:point, at, 4.0, []}`; construction points that are not
  vertices are `{:point, at, 3.0, [opacity: 0.6]}`.
- **Diagnostics** are `{:guide, from, to, []}` and carry a `{:label, at, text,
  []}`.
- A frame whose state has `map: nil` draws only what the state does have; an
  empty op list is legal and the canvas renders an empty SVG.
- Coordinates go through `Exhibits.Format.pair/1`.

A shared module, `GirihelixWeb.Workbench.Exhibits.Figures`, holds the map and
unit ops so the five exhibits share one edge walker. It is workbench code, not
engine code: it may use `PlanarMap`'s public API and the draw ops.

### `star`

Parameters: `n` 3..24 default 8, `d` 1..10 step 0.1 default 3.0, `s` 1..6
default 2.

Draws the whole map, the unit heavier, the tip marked, the base chord
`a → b` as a guide, and every crossing the current frame has found as a small
point. The `:closure` frame adds the closure edge or the `cent` point in a
distinct stroke.

Panel rows: `n`, `d requested`, `d clamped`, `di`, `frac`, `is integer`,
`s stored`, `outer s`, `closure` (yes or no), `vertices`, `edges`, `verify`.

Reproduce:

```elixir
Girihelix.Engine.Figures.Star.build_unit(
  Girihelix.Engine.Figures.Star.new!(8, 3.0, 2)
)
```

### `rosette`

Parameters: `n` 3..24 default 8, `q` -2..2 step 0.05 default 0.0, `s` 1..6
default 3. A declared range is integer-backed, so `-2..2` is the widest float
domain the framework can express; the engine's `[-0.99, 0.99]` clamp is the
one the exhibit shows.

Draws the whole map, the unit heavier, the tip, the `up_outer → bisector` guide,
the tip→qtip ray, the key line `key_point → key_end`, and the stable ray when
`q < 0`. Each `:walk` point is marked as it appears.

Panel rows: `n`, `q requested`, `q clamped`, `s requested`, `s stored`,
`key point`, `steps emitted`, `steps skipped`, `vertices`, `edges`, `verify`.

Reproduce:

```elixir
Girihelix.Engine.Figures.Rosette.build_unit(
  Girihelix.Engine.Figures.Rosette.new!(8, 0.0, 3)
)
```

### `scale`

Parameters: `child` enum `[:rosette, :star]` default `:rosette`, `n` 3..12
default 8, `q` -2..2 step 0.05 default 0.0 (read only for a rosette child), `d`
1..10 default 3.0 (read only for a star child), `child_s` 1..6 default 3,
`s` 0..3 step 0.1 default 1.5. The `q` and `s` declarations follow the same
integer-backed-range rule as `rosette`.

Draws the child unit as a dashed guide, the scaled unit and its extended
vertices, the clipping n-gon as a guide, the 100-unit ray, the clipped endpoint
as a marked point, and the rotated copies' crossings as they are added.

Panel rows: `child`, `s requested`, `s stored`, `passthrough`, `tip`,
`below-axis neighbour`, `endpoint`, `vertices`, `edges`, `verify`.

Reproduce:

```elixir
Girihelix.Engine.Figures.ScaleFigure.build_unit(
  Girihelix.Engine.Figures.ScaleFigure.new!(
    Girihelix.Engine.Figures.Rosette.new!(8, 0.0, 3),
    1.5
  )
)
```

### `connect`

Parameters: `child` enum `[:rosette, :star]` default `:rosette`, `n` 3..12
default 8, `q` -2..2 step 0.05 default 0.0, `d` 1..10 default 3.0, `child_s`
1..6 default 3. There is no `s` parameter: it is solved.

Draws the child unit dashed, the folded unit solid, the half-step rotation as a
guide from the apex, and the normalised result. The panel reports the derived
`s`, which is the point of the exhibit.

Panel rows: `child`, `derived s`, `fallback`, `vertices`, `edges`, `max x`,
`verify`.

Reproduce:

```elixir
Girihelix.Engine.Figures.ConnectFigure.build_unit(
  Girihelix.Engine.Figures.ConnectFigure.new!(
    Girihelix.Engine.Figures.Rosette.new!(8, 0.0, 3)
  )
)
```

### `radial`

Parameters: `kind` enum `[:star, :rosette]` default `:rosette`, `n` 3..24
default 8, `d` 1..10 default 3.0, `q` -2..2 step 0.05 default 0.0, `s` 1..6
default 3.

This exhibit is about the ladder, not the figure. Its single `:replicate` step
calls `Figure.unit/1` and then `RadialFigure.map/1`. It draws the coalesced map
faintly beneath, then every copy as the unit's edges mapped through one ladder
transform, labelled `Tr^k` at the copy's own bounding-box centre. Each copy is
drawn from the unit, not from the coalesced map, because replication has already
merged the copies' shared vertices. The unit itself is drawn heavier. The panel
reports the transform count and whether the unit's first and last copies
coalesced.

Panel rows: `kind`, `n`, `unit vertices`, `unit edges`, `transforms`,
`vertices`, `edges`, `verify`.

Reproduce:

```elixir
Girihelix.Engine.Figures.RadialFigure.map(
  Girihelix.Engine.Figures.Rosette.new!(8, 0.0, 3)
)
```

### Viewports

`star`, `rosette`, `scale` and `connect` pin a viewport centred on the origin
with a radius of `1.25` (or the figure's extent when larger), because
auto-fitting makes the figure jump as each stage adds geometry. `radial` pins
the same square. This is the workbench design's own rule: pin when a figure
would visibly jitter.

## Goals

- `Star`, `Rosette`, `ScaleFigure`, `ConnectFigure` and `ExplicitFigure` build
  their units and their whole maps, matching real Taprats 1.1.12 through the
  local harness, flaws included.
- The constructors are fallible and store the clamps; the `:clamp` frame shows
  the same clamp, and a test pins constructor and step together.
- Every stepped builder and its plain function agree, pinned by a test.
- Five exhibits render, step and reproduce, and the registry property test
  covers them at their defaults and range extremes.
- `Star(8, 3.0, 2)` produces the vertices its construction specifies, and the
  expected unit and map counts are asserted.

## Non-goals

- `DesignElement` and its default-figure rule (`Rosette(numPoints, 0.0, 3)`
  when a feature is regular with more than four points, otherwise an empty
  `ExplicitFigure`). It is a Plan 6 concern and is recorded here as an input to
  that plan.
- `Infer`, contact inference and irregular tiles.
- Tilings, `Feature`, `PlacedFeature` and instancing (Plan 4).
- The three render styles (Plan 5).
- The Ash union and its per-variant validation (Plan 6).
- Caching a unit or a map on a figure. The source has none, and immutability
  makes recomputation the simple choice.
- Fixing any FIXME. The Rosette skip, Star's null crash, ScaleFigure's missing
  tip and ConnectFigure's zero extent are pinned as they are.
- Performance work beyond avoiding accidental re-construction inside a step.

## Review focus candidates

1. **A parameter the source clamps.** `d = 99`, `q = -2` and an oversized `s`
   must produce the clamped geometry from both the constructor and the step
   path, and the two figures must be equal.
2. **A degenerate construction.** Star's failed crossing, Rosette's skipped
   step, ScaleFigure's missing tip and ConnectFigure's zero extent must each
   behave as the source does, or raise where the source crashes, never silently
   produce a different figure.
3. **The unit-to-map boundary.** The ladder must start at `Tr`, and boundary
   vertices must coalesce. A wrong start or a wrong tolerance doubles the seam.
4. **A nested child.** Scale and Connect must build the child afresh, must not
   alter it, and must honour the `s = 1` passthrough.

## Left to the builder

- Internal state keys beyond the ones named above.
- The exact panel wording and the order of rows within the listed fields.
- The shared `Exhibits.Figures` helper's function names.
- Additional golden scenarios, as long as each named behaviour above has one.
- The exact pinned viewport radius, within the stated rule.

## Decisions taken

- **One shared clamp per figure, called by constructor and step, constructor
  stores the result.** This resolves the tension between tier-3 constructors
  and visible clamps.
- **`build_unit/1` returns a map and may raise; it never returns a tuple.** A
  parameter error is a constructor error; a geometric degeneracy is the
  source's crash, rendered by the workbench as a failure frame.
- **`Figure.map/1` replicates with `PlanarMap.replicate!/3`,** into an empty
  map, with the ladder beginning at `Tr`. Two operations, no cached unit.
- **`RadialFigure` is a behaviour plus a helper module, not a struct.** `n` is
  the only stored derived quantity, and it lives on each figure.
- **Star stores raw `d` beside `clamp_d`,** because the closure chord uses the
  raw value after clamping. Every other figure stores only the clamped value.
- **Rosette's redundant `s` clamp is collapsed** into the constructor's stored
  value; it has no behavioural effect.
- **ScaleFigure stores a normalised `s`:** exactly `1.0` when the source's
  tolerance would take the passthrough, otherwise the given scale.
- **ConnectFigure stores the derived `s`** and does not recompute it in
  `build_unit/1`; `child_changed/1` re-derives it.
- **One harness operation, `figure`, with `map` and `unit` modes, and a
  recursive expression.** `ExplicitFigure` gets no harness operation.
- **The five exhibits share one map-drawing helper** in the workbench layer.
- **The exhibits read exactly these engine state keys.** `star` reads `map`,
  `n`, `d`, `clamp_d`, `di`, `did`, `dfrac`, `is_int`, `clamp_s`, `outer_s`,
  `a`, `b`, `points` and `top`; `rosette` reads `map`, `n`, `q`, `q_clamp`, `s`,
  `s_clamp`, `frame` (`tip`, `up_outer`, `bisector`, `stable_isect`, `qtip`,
  `key_point`, `key_end`), `points` and `skipped`; `scale` reads `map`,
  `child`, `requested_s`, `figure`, `passthrough`, `tip_pos`, `below`,
  `endpoint` and `border`; `connect` reads `map`, `child`, `s`, `fallback`,
  `figure` and `max_x`. The `radial` exhibit owns its state instead and reads
  `figure`, `unit`, `map` and `transforms`. Every key except the `radial`
  exhibit's own four is one the engine's `start/…` state defines.
- **`Exhibits.Figures` finished with a fixed, verified API:** `map_ops/1`,
  `map_ops/2`, `unit_ops/1`, `vertex_ops/2`, `rows_for/1`, `whole_map/1`,
  `tip_op/0`, `construction_op/1`, `map_label/2`, `number/1`, `integer/1`,
  `child_params/1` and `build_child/1`. The midpoint helper lives beside the
  other number spellings in `Exhibits.Format.midpoint/2`.
- **Star's canonical crash parameters are `n = 8, d = 7.02, s = 3`.** The
  closure's `cent` intersection is nil, so `Star.build_unit/1` raises
  `star: degenerate_crossing`; the `figure-star-crash` golden and the unit test
  pin the parameters.
- **ConnectFigure's derived scale records a fallback flag, not a reason.** The
  three `1.0` paths are geometrically identical, so the build state holds
  `fallback: true` rather than inventing a reason the engine cannot observe.

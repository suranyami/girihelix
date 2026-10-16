# Algorithm analysis: the Taprats reference implementation

This document is the porting specification for **girihelix**, an Elixir
reimplementation of Taprats — Craig S. Kaplan's Java design tool for
computer-generated Islamic star patterns. It is derived directly from the Java
source preserved under [`reference/`](../reference/), and describes
**Taprats 1.1.12**, the current maintained release at changeset `b6c172`, which
is the version girihelix ports.

The original 2000 release, `reference/0.3/`, is kept alongside as a second
opinion and is the baseline for the change summary near the end of this
document. Where the two differ behaviourally, the difference is called out
inline. Neither tree is committed to the repository, and neither is compiled by
this project.

The subject is the computational core: tilings, figures, the contact-inference
pass, the planar map, and the interlace renderer. The Swing/AWT user interface
is out of scope, except where a UI class shows how a core class is driven.

---

## Layers of the system

The system is an evaluator with three layers, each parameterizable at a high
level, sitting on a shared geometry substrate that all three speak in terms of.

| Layer | Reference classes | Java package |
| --- | --- | --- |
| Tiling | `Tiling`, `Feature`, `PlacedFeature`, `KnownTilings` | `csk.taprats.tile` |
| Figure | `Figure`, `RadialFigure`, `Star`, `Rosette`, `ScaleFigure`, `ConnectFigure`, `ExplicitFigure` | `csk.taprats.app` |
| Prototype | `Prototype`, `DesignElement` | `csk.taprats.app` |
| Inference | `Infer` | `csk.taprats.app` |
| Geometry | `Map`, `Vertex`, `Edge`, `Point`, `Transform`, `Polygon`, `Rect`, `Faces` | `csk.taprats.geometry` |
| Style | `Style`, `Interlace`, `Plain`, `Filled`, `Outline`, `Emboss`, `Sketch`, `Colored`, `Thick` | `csk.taprats.style` |
| Support | `Loose`, `Signal` | `csk.taprats.general` |
| Text | `L`, `Taprats`, `Taprats_fr` | `csk.taprats.i18n` |

One structural quirk to keep in mind: in 1.1.12 the source tree does **not**
mirror these package names. Files sit at `src/app/`, `src/geometry/` and so on,
while their declarations still read `package csk.taprats.app;`. Paths quoted in
this document are relative to `reference/1.1.12/src/`.

Data flows downward. A `Figure` is a high-level object that knows how to *build*
a `Map`. The class comment in `Figure.java` gives the rationale directly: maps
are "a very low level geometry and topological structure. Not so good for
interacting with users." The UI therefore manipulates figures, and only the
evaluator touches maps.

### How a design is assembled

`Prototype.construct( Polygon region )` in `app/Prototype.java` is the
top-level entry point. Its algorithm is unchanged from 0.3; the class has gained
generics, `equals`/`hashCode`, and `Serializable`. It instances the design in
four nested passes:

1. `FillRegion.fill` walks the lattice, firing a callback for each integer
   `(t1, t2)` pair whose translational unit meets the region.
2. For each `Feature` bound to a `Figure`, `Figure.getMap()` builds that
   figure's map once, at unit scale.
3. `Map.mergeSimpleMany` instances it at every `PlacedFeature` transform that
   reuses that feature inside one translational unit.
4. `mergeSimpleMany` again stamps that composite at every lattice translation,
   then `Map.mergeMap` slow-merges it into the finished design.

The serialization is worth noting because it constrains the port. A `Prototype`
writes only its tiling's *name* and its feature-to-figure table, and `readObject`
reconstitutes the tiling through `KnownTilings.find( name )`, raising
`IOException` with `"Tiling <name> not found."` when the registry lacks it. A
saved design therefore depends on the tiling registry still holding that name —
a coupling worth either reproducing or deliberately dropping.

---

## The tiling layer

A `Tiling` is the skeleton a design is drawn on: two translation vectors plus a
set of `PlacedFeature`s that together form one *translational unit*. The plane is
covered by placing a copy of that unit at every integer linear combination of the
two vectors — in practice only those overlapping the viewport, which is precisely
what `FillRegion` computes.

| Class | Role |
| --- | --- |
| `Feature` | A tile: an array of `Point`s plus a `regular` flag |
| `PlacedFeature` | A `Feature` with a `Transform`, so tiles can be shared and re-placed |
| `Tiling` | Vectors `t1`, `t2`, the `PlacedFeature` list, a name, description and author |
| `KnownTilings` | The static registry of built-in and loaded tilings |
| `DesignElement` | A `Feature` bound to a `Figure` — the pairing `Prototype` stores |

`Feature` keeps its points in an array rather than wrapping a `Polygon` because
per-point metadata is added and removed over time, while the vertex count never
changes after construction. The `regular` flag is load-bearing: `DesignElement`'s
one-argument constructor gives a regular polygon with more than four sides a
default `Rosette( n, 0.0, 3 )` and an empty `ExplicitFigure` otherwise. That
constructor is byte-identical to 0.3.

### A behavioural change to watch: `Feature` equality

This matters more than it looks. In 0.3, `Feature` declared no `equals`, so
`Prototype`'s figure table and its `if( f.equals( feature ) )` match both used
**reference identity**. Sharing one `Feature` object across several
`PlacedFeature`s was therefore meaningful, and `PlacedFeature`'s own comment says
so. In 1.1.12, `Feature` overrides `equals` and `hashCode` **structurally** — the
`regular` flag plus every vertex — so two distinct but geometrically identical
tiles now compare equal and hash alike.

Both `Prototype` and `Infer` match features by equality, so this changes which
tiles count as the same tile. A port should decide deliberately: structural
equality reproduces 1.1.12, identity reproduces 0.3.

### Where the built-in tilings live

`Tiling` itself no longer knows any tilings. `KnownTilings` is the registry,
offering `add`, `find( name )`, `countTilings`, `getTilingNames` and `getTilings`,
and it loads from three sources in order:

1. `addCodeTilings()` — the generated Java block, some 3,200 lines of it;
2. `readExternalTilings()` — tilings found in the `tilings/` directory;
3. `readJarTilings()` — tilings bundled inside the distributed jar.

**Fifty-eight** tilings ship as built-ins, against fourteen in 0.3. All fourteen
originals survive unchanged in name (`4^4`, `6`, `10`, `18`, `4.6.12`, `8.12`,
`9.12`, `16.8`, `3.12^2`, `4.8^2`, `csk_5`, `csk_7`, `csk_9`, `square_12`); the
other forty-four are additions, several named for the buildings that inspired
them — `alhambra16`, `Seville Alcazar 12.8.6`, `Al-Mustansiriyya`, `Ilkhanid
Uljaytu`, `Great Mosque of Malatya`, `Mughal I'timad` and others.

The built-ins are still not hand-written. `exportTilingAsCode` regenerates the
Java for a `Tiling` — the tool that produces `addCodeTilings` — with
`regroupFeatures` keeping each feature written only once. `Tiling.readTiling`
parses the same format through a `StreamTokenizer`, and the new `writeTiling`
emits it, so a tiling now round-trips through a file.

---

## Radial figures

`RadialFigure` is the base for every figure with d_n symmetry: invariant under
rotation by 360/n degrees, and under reflection in certain lines through the
origin. It exploits that symmetry by having subclasses build only a *basic unit*
— the smallest piece which, rotated by c_n, generates the whole figure.
Reflections are each subclass's own business, which is why the base class applies
rotations only. It holds `n`, `don = 1/n` and `Tr = Transform.rotate( 2π/n )`;
`getArc( frac )` returns the point `frac` of the way round the unit circle, and is
the primitive every construction below is written in terms of. `getMap` composes
`Tr` with itself n times and hands the transform list to `Map.mergeSimpleMany`.

| Figure | Parameters | Builds its unit by |
| --- | --- | --- |
| `Star` | `n`, `d`, `s` (default 8, 3.0, 2) | Intersecting chords of the unit circle |
| `Rosette` | `n`, `q`, `s` | Lee's construction around an angle bisector |
| `ScaleFigure` | a child figure, `s` | Scaling a child unit and clipping to the n-gon |
| `ConnectFigure` | a child figure | `ScaleFigure` with `s` solved so extended edges meet |
| `ExplicitFigure` | a `Map` | Returns a clone of the stored map |

These six constructions are **behaviourally unchanged from 0.3**. Diffing the two
releases leaves only mechanical edits: added generics (`Vector<Transform>`,
`Enumeration<Vertex>`), the removal of casts those generics made redundant, and
reformatting. The only deletion is `RadialFigure`'s `time` field, which was never
read. The descriptions below were therefore verified against both releases — and
where they hold in both, that is stated rather than assumed.

### `Star` — the [n/d]s construction

`d` is the skip: how far round the circle each edge reaches. Because it is a
`double`, this family is continuous rather than limited to the {n/d} star
polygons. `clamp_d = max( 1, min( d, n/2 − 0.01 ) )` keeps the chord from
degenerating, and `dfrac` snaps to 0 whenever it comes within `Loose.TOL` of 0 or
1 — in the latter case the integer part is rounded up, and `is_int` records which
happened. `clamp_s = min( s, di )` and `outer_s = min( s, di − 1 )`.

The unit grows from the chord `a = (1,0)` to `b = getArc( clamp_d · don )`. For
each `idx` in `1 .. outer_s`, the chord `(a, b)` is intersected with the chord
from `getArc( idx · don )` to `getArc( (idx − clamp_d) · don )`; those crossings
are where the star's points meet. Each is mirrored about the x-axis (y → −y) and
both chains are inserted, so the unit is symmetric about the axis while c_n
supplies the rest of the figure. When `clamp_s == di` the unit closes at the
rotated apex: a single edge when `d` is integral, and otherwise an extra vertex
`cent`, found by intersecting `getArc( di·don ) → getArc( −dfrac·don )` with
`a → getArc( d·don )`.

### `Rosette` — Lee's construction

`q`, clamped to `[−0.99, 0.99]`, controls sharpness; `s` controls how many steps
the unit reaches out. The `s` clamp moved between releases — 0.3 computed
`s_clamp = Math.min( s, (n−1)/2 )` inside `buildUnit`, whereas 1.1.12 applies
`this.s = Math.min( s, (n-1)/2 )` in *both* constructors. The effect is identical,
but the location differs, which will mislead a naive diff. From `tip = (1,0)` and
`up_outer = getArc( 0.5·don )` scaled by `r_outer = 1 / cos( π·don )`, the code
derives `bisector` — the midpoint of the drop from `up_outer` to `(0, r_outer)`.
Kaplan's comment identifies this as the centre of the bottom edge of an
equilateral triangle, i.e. the bisector of the angle leaving `up_outer`.

The ray angle `th` begins as the angle of `rtip − tip`, then blends. For `q ≥ 0`
it rotates toward vertical: `th ← th·(1−q) + (π/2)·q`. For `q < 0` it moves
toward a *stable* ray derived from `stable_isect = up_outer +
normalize( up_outer )·(−up_outer.y)`, giving `th ← th·(1+q) − stable_angle·q`.
Then `qtip = (1 + cos th, sin th)`, `key_point` is the intersection of
`(tip, qtip)` with `(up_outer, bisector)`, and
`key_end = key_point.convexSum( stable_isect, 10.0 )` projects a long segment
through `key_point` for the steps that follow. Each of the `s` steps intersects
that key line with its `Tr`-rotated copy, mirroring every hit in y.

A FIXME in the source records a genuine failure mode. For some `(n, q, s)` —
Kaplan cites `n = 12`, `q = −0.8`, `s = 4` — the segments being intersected end
up parallel, the intersection returns `null`, and that vertex is silently
skipped. He checks after the fact rather than deriving when it happens. A port
must either reproduce the null check exactly or detect the degenerate case
properly; drifting here changes the output geometry.

### `ScaleFigure` — pulling a figure out to its cell

`ScaleFigure( child, s )` wraps another radial figure plus a scale factor. When
`s` is 1 within `Loose`, `buildUnit` passes straight through to
`child.buildUnit()`. Otherwise it locates the tip vertex at `(1,0)`, scales the
whole unit by `s`, builds the clipping n-gon from `getArc( idx·don )`, finds the
tip's neighbour below the x-axis, extends the ray `tip → below_tip` outward by
100 units, and clips it against the n-gon to obtain `endpoint`. It then
intersects that ray with its `Tr`-rotated copy, inserting each intersection and
its mirror, for up to `(n+1)/2` iterations, and adds `endpoint` last. The effect
is to pull the figure's edges out to the boundary of its n-gon cell — an
*extended* figure.

### `ConnectFigure` — solving for the scale

`ConnectFigure` is a `ScaleFigure` that derives `s` rather than accepting it.
`computeConnectScale` repeats the tip / below-axis neighbour / 100-unit probe,
intersects that with the rotated copy, and takes `α = cos( π/n ) / |isect|` — the
factor at which the extended edges of neighbouring cells meet exactly. If the
intersection fails it returns 1.0. This is how a Rosette becomes an *extended*
rosette, and how several can be layered by wrapping repeatedly.

Its `buildUnit` then does three post-passes: `rotateHalf` folds the top half of
the unit under the bottom half so the apex returns to `(1,0)` — Kaplan's comment
explains the reshuffle is needed so the result still lines up with the feature
that will contain it — a `π/n` rotation when `s ≠ 1`, and `scaleToUnit`, which
scales so the maximum x coordinate is 1.

---

## Contact inference: `Infer`

`Infer` is what Kaplan calls "the black magic part of the Islamic design
system". Given a feature that has no figure of its own — an irregular tile in a
custom tiling — it invents a map for that tile by extending line segments inward
from the figures of its adjacent tiles.

The header comment is blunt that this is heuristic. There will be features where
natural extensions do not exist, so the class carries fallbacks whose only job is
to produce something that "doesn't break the rest of the system". Kaplan also
warns that if you see weird behaviour in Taprats, it "probably" comes from here.
For a port this matters: every threshold in this file is behavioural
specification, not an implementation detail to be tidied away.

### Seven strategies, one analysed here

In 0.3 `Infer` had a single entry point. In 1.1.12 it has **seven**, and the class
grew from 645 to 1,570 lines:

| Strategy | Signature | Approach |
| --- | --- | --- |
| `infer` | `( feature )` | Contact inference — the 0.3 algorithm, analysed below |
| `inferStar` | `( feature, d, s )` | Builds star half-branches per polygon side |
| `inferHourglass` | `( feature, d, s )` | Hourglass filler |
| `inferRosette` | `( feature, q, s, r )` | Rosette filler, with a radius parameter |
| `inferIntersect` | `( feature, starSides, starSkip, s )` | Ranks side-to-side intersections |
| `inferIntersectProgressive` | `( feature, starSides, starSkip, s )` | Progressive variant of the above |
| `inferGirih` | `( feature, starSides, starSkip )` | Derives the branch angle from the gap it hops |

`inferGirih` is the most explicit about its mathematics: it computes
`polygonInnerAngle = π(sides−2)/sides`, then
`starBranchInnerAngle = starSkip · polygonInnerAngle − (starSkip − 1) · π`, and
finally `requiredRotation = (π − starBranchInnerAngle) / 2`. Fractional skips are
supported, which is what makes the family continuous.

The rest of this section analyses **`infer` only** — the contact-inference
algorithm that the 2000 system was built on and that the port should land first.
The other six are additions, and their internals have not been read.

Two new helpers support them: `intersection_info` (side, other side, which edge
is left, a *squared* distance to avoid a square root, and the intersection point;
`Comparable`) and `edges_length_info` (also `Comparable`). Both are ordering
machinery for picking the best intersection, and both are new in 1.1.12.

Three package-private helpers carry the state.

| Type | Holds |
| --- | --- |
| `placed_points` | A `Feature`, its `Transform`, and `mids` — its transformed edge midpoints |
| `adjacency_info` | Which `Feature`, which edge index, which `Transform` lies across an edge, and the tolerance at which that match was found |
| `contact` | One contact on the boundary: `position`, `other`, the probe ray `end`, plus `isect`, `isect_idx`, `colinear`, `taken` |
| `intersection_info` | One side-to-side intersection: sides, side-ness, squared distance, point |
| `edges_length_info` | Edge lengths, used to order candidates |

The midpoint trick is load-bearing. Because these tilings are edge-to-edge, an
edge is uniquely identified by its midpoint, so edges are matched by comparing
`mids` rather than testing endpoint pairs, with `Loose.near` supplying the
tolerance. A `contact`'s `end` is
`position + normalize( position − other ) · 100` — a probe long enough to reach
crossings well beyond the tile. The `contact` class is unchanged from 0.3.

The six contact kinds are ordered by desirability, and that ordering *is* the
heuristic:

| Rank | Kind | Meaning |
| --- | --- | --- |
| 0 | `INSIDE_EVEN` | Cross inside the tile, equidistant from both contacts |
| 1 | `INSIDE_COLINEAR` | The two segments are already collinear |
| 2 | `INSIDE_UNEVEN` | Cross inside the tile, at unequal distances |
| 3 | `OUTSIDE_EVEN` | Meet outside the tile, equidistant |
| 4 | `OUTSIDE_UNEVEN` | Meet outside the tile, at unequal distances |
| 5 | `NONE` | No connection at all |

The constructor caches `figure.getMap()` for every feature in the prototype, then
enumerates the 3×3 block of translational units with `x, y ∈ {−1, 0, 1}` into
`placed`, an array of `numFeatures · 9` entries. That block is guaranteed to
surround every feature of the `(0,0)` unit, which is what makes neighbour lookup a
finite search. `findPrimaryFeature` then picks the instance inside `(0,0)` — the
index range `numFeatures·4` to `numFeatures·5` — and throws `InternalError` if it
is missing, asserting that the block really did surround the feature.

### Progressive tolerance: a real robustness fix

This is the most interesting change to `infer` between the releases, and it is an
improvement rather than a rewrite.

In **0.3**, `getAdjacencies` scanned for a midpoint match at one fixed tolerance
(`Loose.equals`, so `TOL2`-based) and **threw `InternalError( "Couldn't find
adjacent feature!" )`** when it failed — the 3×3 block being expected to guarantee
a neighbour.

In **1.1.12**, `getAdjacency` *escalates*: it starts at `tolerance = 1e-12`,
doubles until it exceeds `5.0`, and returns the first match at the tightest
tolerance that works, **recording that tolerance on the `adjacency_info`**.
Failure returns `null` rather than throwing, and `buildContacts` substitutes an
empty map for a null adjacency. The only `InternalError` left in `Infer` is
`findPrimaryFeature`'s, for a feature absent from the `(0,0)` unit.

`buildContacts` then uses the discovered tolerance instead of a global one. For
each edge `(a, b)` it clones the adjacent feature's map, applies the adjacency's
transform, and scans its vertices with:

```java
double dist2 = pos.dist2ToLine( a, b );
if(   Loose.near( dist2, adj.tolerance )
&&  ! Loose.near( pos, a, adj.tolerance )
&&  ! Loose.near( pos, b, adj.tolerance ) )
```

Two details differ from 0.3 and both matter. The distance is **squared**
(`dist2ToLine`, avoiding a square root), and the endpoint exclusion tests **both**
`a` and `b`, where 0.3 tested only `a` via `pos.dist2( a ) > Loose.TOL2`. Every
edge incident on an accepted vertex becomes a `contact`; Kaplan's comment still
notes he wants "hopefully *both*" of them. The contacts are therefore the
neighbouring figure's edges arriving at the tile boundary, and `infer`'s
remaining job is to decide which pair off and where they cross.

### The pairing heuristic

`infer( feature )` runs the whole pipeline: find the primary instance, compute
`fpts` (the transformed tile corners), gather adjacencies, build contacts, then
pair them greedily. For each contact not yet `taken` it scans the others —
skipping any that share the same `position`, which would mean two contacts at one
vertex — and scores each candidate.

- **Collinear case.** If `other_i → position_i → position_j → other_j` all lie on
  one line (two `isColinear` tests), the segments must additionally point at each
  other. With `d1 = position_i − other_i`, `d2 = position_j − other_j` and
  `dc = position_i − position_j`, the candidate is rejected when `d1·d2 > 0` (both
  facing the same way), when `d1·dc > 0`, or when `d2·dc < 0`. Survivors score
  `INSIDE_COLINEAR`, with distance `|position_i − position_j|`.
- **Otherwise** it calls `Intersect.getTrueIntersection` on the two 100-unit probe
  rays. The *true* variant matters: a crossing must lie on the segments, not
  merely on their infinite extensions. A `null` result, or one landing within
  `Loose` of either contact position, is discarded. Then
  `inside = Polygon.pointInPoly( fpts, 0, fpts.length, isect )` and the kind
  follows from comparing `dist = |position_i − isect|` against
  `odist = |position_j − isect|`. Unequal distances give `INSIDE_UNEVEN` or
  `OUTSIDE_UNEVEN`, scored by `|dist − odist|`; equal distances give `INSIDE_EVEN`
  or `OUTSIDE_EVEN`, scored by `dist`.

Candidates are compared with `lexCompareDistances`, which is lexicographic on
`(kind, distance)` — kind first, distance only to break ties. That is the entire
ranking: a crossing *inside* the tile always beats one outside, and equidistance
always beats unevenness, however far away it is.

When the best partner is chosen, both contacts are marked `taken`. A collinear
match records `COLINEAR_MASTER` and `COLINEAR_SLAVE` on the pair; every other
match stores the shared intersection point on both, along with each other's index.

### Assembling the result, and the fallback

The output map is built from those stored decisions. For each contact: if it holds
an intersection, an edge runs from `position` to `isect`; if it is instead the
colinear master, an edge runs from `position` to the partner's `position`; if
neither, it is left to the fallback. Each fragment is merged in with
`mergeMap( tmap, true )`.

The fallback handles contacts that never found a partner (`isect_idx == −1`). Two
such contacts are joined by a three-edge detour: each `position` steps outward
along `normalize( position − other )` by `minlen · 0.5`, where `minlen` is the
shortest edge of the tile polygon, and the two stubs are then connected across.
This is the "black magic" — a plausible connection manufactured where the geometry
offers none, and the part most likely to look arbitrary. Tellingly, the
map-verification debug hook at the end of `infer` is commented out in the source.

Finally, since everything above was computed in the primary instance's frame, the
result is mapped back with `ret.transformMap( pmain.T.invert() )`.

---

## The geometry engine

### `Map`: the planar map

A `Map` is an undirected graph embedded in the plane so that no edge crosses a
vertex or another edge. Kaplan is explicit that this is not the textbook
construction: the correct structure is a doubly-connected edge list with
half-edges and explicit faces, and he deliberately built something simpler —
"more like an ordinary graph" — because of "the sheer coding involved". He also
names the cost, and it is the detail that matters most for a port: faces are
never maintained explicitly, which "can make face colouring for islamic patterns
tricky later". Anything girihelix wants to do with filled regions or per-face
colour has to reconstruct that information.

Internally it is two `Vector`s, one of vertices and one of edges. The interface
is where the meaning lives:

| Method | Purpose |
| --- | --- |
| `insertVertex`, `insertEdge` | Build the graph; `insertEdge` maintains the no-crossing invariant |
| `mergeSimpleMany( other, transforms )` | Replicate `other` once per transform, rebuilding edges between copies |
| `mergeMap( other, consume )` | Slow merge that welds `other` in and unifies coincident vertices |
| `transformMap`, `scale`, `translate` | Apply an affine transform to every vertex in place |
| `verify` | Structural sanity check, used throughout as a debug assertion |

The gap between the two merge paths carries real weight. `mergeSimpleMany` simply
maps each source vertex to a copy at the transformed position and rebuilds the
edges, then sorts; `mergeMap` does the expensive work of reconciling topology.
`Prototype` uses the fast path for mass replication and the slow path only to weld
the final pieces together.

Three 1.1.12 changes sit on top of that, none of which alter the merge semantics:

- **Every mutator is `synchronized`** — `insertVertex`, `insertEdge`, `mergeMap`,
  `mergeSimple`, `mergeSimpleMany`, `scale`, `translate`, `transformMap`,
  `transformVertex`, `removeVertex`, `removeEdge`, `clone`. A port onto a
  single-process model can ignore this, but it is a hint that the class is shared
  across threads in the Swing UI.
- **The home-grown sort is gone.** 0.3 called `Sort.quickSort` with its own
  `Comparison` interface; 1.1.12 uses `Collections.sort` with anonymous
  `Comparator<Vertex>` and `Comparator<Edge>`. That is why `general/Sort.java` and
  `general/Comparison.java` disappear entirely.
- **`cleanCopy()` was added**, called at the head of `mergeMap`, `mergeSimple` and
  `mergeSimpleMany`. It nulls the scratch `copy` pointer on every vertex, so stale
  state from a previous merge cannot leak into the next. Worth reproducing: it is
  cheap and it removes a whole class of bug.

### `Intersect`: segment crossings

`Intersect` is deliberately minimal. It is segment-to-segment only, and it is
built around a parameter pair rather than a point.
`getIntersectionParams( p1, q1, p2, q2 )` returns a `Point( s, t )` where `s` is
the fraction along `p1 → q1` at which the crossing occurs and `t` the fraction
along `p2 → q2`; `null` means no crossing. The determinant `d1x·d2y − d1y·d2x`
identifies parallel segments, and the arithmetic is adapted from O'Rourke's
*Computational Geometry in C*.

Two behaviours are worth carrying over exactly:

- **Parallel returns `null`, and that is deliberate.** The comment concedes that
  endpoint contact and overlapping collinear segments are unhandled, concluding —
  with some humour — that this leaves "um, nothing". Callers that need the
  degenerate case must handle it themselves, which is precisely the `null` check
  in `Rosette`.
- **There are three entry points, not two.** All of them take a crossing found by
  `getIntersectionParams` and filter it by a different amount of slack:
  `getIntersection` accepts only parameters inside `[0, 1]` (through
  `stayOnSegments`); `getNearIntersection` accepts up to `0.2` beyond either end
  (through `stayNearSegments`); and `getTrueIntersection` additionally rejects a
  crossing that lands at the endpoints of *both* segments, which is the variant
  `infer` uses so two contacts never pair at a shared vertex. The near variant is
  new in 1.1.12 and is what the added inference modes reach for when tidy
  intersections do not exist.

One trap, and it is a 0.3 trap that 1.1.12 removed: 0.3 declared
`private static final double TOL = 1.0E-9` and never referenced it, with every
real test using `Loose.TOL` at 1e-7 — two orders of magnitude looser. 1.1.12
deleted the dead constant. Porting 0.3 by copying the declared value would
therefore diverge; there is nothing to copy in 1.1.12.

### `Transform` and `FillRegion`

`Transform` is a 2D affine transform held as the top two rows of the homogeneous
3×3 matrix — the linear part plus the translation `(c, f)`. It provides exactly the
constructors the figures need: `scale`, `translate`, `rotate`, `rotateAroundPoint`,
`reflectThroughLine`, and the segment-matching helpers `matchLineSegment` and
`matchTwoSegments`. `compose` multiplies, `invert` reverses, and `flips` reports
whether the transform reverses orientation. `RadialFigure` leans on `compose` to
build its c_n rotation ladder; `Infer` leans on `invert` to return from its working
frame.

1.1.12 adds three methods to `Transform`, all conveniences rather than changes:
`distFromZero` and `distFromInvertedZero`, which measure how far a point sits from
the transform's origin and from its inverse image, and `assign`, an in-place copy
of another transform. The arithmetic is otherwise untouched.

`FillRegion` answers the question `Prototype` opens with: which integer
combinations of `t1` and `t2` place a copy of the translational unit over a given
region. It changes basis into the translation-vector coordinate system and then
fills the quadrilateral in the usual scanline way, calling the `UnitCallback` once
per translate.

Its own comment flags a limitation a port must decide about rather than inherit
silently: the fill "can leave gaps around the edge of the region", and the
workaround belongs to the client — "the region is simply expanded before filling".
Seamless output in girihelix needs either that same expand-then-fill convention or
a correct fill. `FillRegion` is otherwise **unchanged** between the releases: five
lines of difference, all reformatting. So this is not an oversight that was later
corrected.

---

## Rendering: `Interlace`

The renderer is `csk.taprats.style.Interlace`, the renamed and relocated
`ui/RenderInterlace`. It is, in Kaplan's words, "probably the most important
rendering style from an historical point of view". It assigns an over-under rule
to the map's edges and draws a weave that follows it. The rule is "conceptually
simple but difficult in practice", and he notes he wants robustness against
degenerate maps produced elsewhere in the program — "(*sigh*)". The class comment
is otherwise carried over verbatim from 0.3, stale `RenderInterlace` reference
included.

The premise is that if a diagram can be interlaced at all, one choice at a single
vertex determines every other one. So the assignment is a graph traversal, and its
state lives on the map objects themselves:

| Payload | Fields |
| --- | --- |
| `vertex_info` | `visited` |
| `edge_info` | `visited`, `start_under` |

`assignInterlacing` initialises that state and seeds `buildFrom( edge, true )` from
every unvisited edge — one seed per connected component. `buildFrom` records the
edge's `start_under` and recurses into its two endpoints with *opposite* states,
since a single edge cannot be under at both ends. `propagate` then carries the
relation across the vertex:

- **Degree 2, a bend.** The path continues without flipping, and the state handed
  on depends only on whether the outgoing edge *starts* at this vertex:
  `buildFrom` receives `!edge_under_at_vert` if it does, and `edge_under_at_vert`
  otherwise.
- **Degree > 2, a crossing.** Neighbours are walked from the incoming edge's index
  and the under/over state **alternates** at each step, `cur_under` being flipped
  after every hand-off. That alternation is the entire weave rule.

1.1.12 keeps that rule exactly but stops recursing: `propagate` and `buildFrom`
now take a `Stack<Edge>` and iterate, which is precisely the fix 0.3's FIXME
proposed. Both became `private static final`, as did `assignInterlacing`, so the
traversal is no longer part of the public surface.

Drawing is a separate pass, and it is where the trigonometry lives. For each edge
`getPoints` produces three points — `below`, `cen`, `above` — for each end, so
`setMap` stores six points per edge. Which case applies depends on the degree of
the vertex being approached, and on whether the edge is under there:

- **free end** (`nn == 1`): a cap, drawn with a perpendicular offset;
- **bend** (`nn == 2`): delegated to `RenderOutline.getPoints`;
- **over**: the join point is taken against the neighbour two positions round,
  `(edge_idx + 2) % nn`, falling back to a perpendicular offset;
- **under**: the case Kaplan calls "fraught with pitfalls for the imprudent
  (i.e., me)" — the before-and-after neighbours supply three `getJoinPoint` calls,
  each with its own fallback.

`draw` then fills every six-point polygon with a pale interior colour and strikes
two black lines across the gap. The weave is an illusion produced by geometry
alone: the ribbon that is *over* is drawn unbroken, and the one that is *under* is
interrupted.

Three changes land on the drawing half in 1.1.12. `getPoints` became `void` — it
writes into the style's representation instead of returning an array of three
points per edge end — and the cap case moved behind a helper, `capGap`. And a new
**shadow** property appears (`getShadow`, `setShadow`, `getShadowVector`), letting
the weave be drawn with a drop shadow; it has no counterpart in 0.3. The gap and
shadow are both exposed as style properties with setters, which is how the editor
sliders drive them.

Two FIXMEs in this file are worth carrying forward rather than rediscovering:

- **Recursion depth.** The propagation is recursive and can go very deep. Kaplan
  documents the resulting stack overflow and the workaround of starting the JVM
  with `java -Xss10M`, noting the proper fix is an explicit stack. A port should
  use an explicit stack from the start; the traversal is equally unbounded in
  Elixir, where deep recursion is still a real cost rather than a crash.
- **The gap width is wrong by a factor of `sin θ`.** The gap is opened by
  subtracting `gap`-scaled unit vectors, so between edges meeting at an angle it is
  not perpendicular. The comment names the fix — scale by `1/sin( θ )` — but it is
  not applied in the original. Reproducing the original's gap exactly will
  therefore look subtly wrong at shallow crossings, and that is expected.

---

## Porting map to Elixir

| Taprats | girihelix | Note |
| --- | --- | --- |
| `Loose` | a tolerance module | `TOL = 1e-7`, `TOL2 = 1e-10`, `NEAR_TOL = 1e-4`; the `near/2` and `near/3` overloads take an explicit tolerance and are what `Infer` relies on |
| `Point`, `Transform`, `Map`, `Vertex`, `Edge`, `Polygon` | immutable structs | Every mutating call becomes a returned value |
| `Figure`, `RadialFigure` | behaviour plus implementations | `build_unit/1` returning a map; the c_n replication in one shared helper |
| `Prototype.construct` | a pure function over a region | Four nested instancing passes; maps onto `Enum` and `Stream` |
| `Infer.infer` | the contact-inference pass, thresholds preserved | A behavioural specification, not a template to improve |
| `Infer.inferStar` and the rest | six further strategies | Documented here by signature only — see the scope note below |
| `KnownTilings` | tiling data, not code | 58 tilings from three sources; belongs in a data file, not in a module body |
| `Feature` equality | an explicit decision | Structural in 1.1.12, reference identity in 0.3; the port must choose one |
| `Style` hierarchy | a render module | Keep the weave assignment separate from SVG path building |
| AWT `Graphics` | SVG | The only layer with no meaningful port |
| Swing UI | Phoenix LiveView | Figures become assigns on a socket, not mutable objects |

### What to port first

The honest scope of this document: **`Infer.infer` is analysed in detail**, and
the six other inference strategies are recorded by name and signature only. That
ordering is deliberate. `infer` is the algorithm Taprats was built around and the
one the 2000 system depends on; the others are 2010s additions for particular
tiling families. Land `infer`, plus the figure constructions, the map and the
interlace renderer, and girihelix reproduces the original tool. The remaining
strategies can then be ported one at a time, each read properly against 1.1.12
source rather than from this summary, and each checked against the `Infer` UI
editors that drive them (`ui/figure/ExplicitStarEditor`,
`ExplicitHourglassEditor`, `ExplicitIntersectEditor`, `ExplicitGirihEditor`,
`ExplicitRosetteEditor`).

Three things stand out as the real work, none of which that table conveys.

**Mutability is the structural change.** The Java mutates in place almost
everywhere: `Point`'s `scaleD`, `addD`, `subtractD`, `normalizeD` and `perpD`
alongside their pure siblings, plus `Map.scale` and `Map.transformMap`, and — most
awkwardly — the traversal flags in `Infer` (`taken`, `isect_idx`) and
`RenderInterlace` (`visited`, `start_under`), written through `setData`. The pure
`Point` operations port directly. The traversal flags do not: they must become
explicit state, threaded through a fold or held in a keyed map. That rewrite,
rather than the geometry, is where the port will actually spend its time.

**Object identity does not translate.** Several places key on identity rather than
value. `ConnectFigure.rotateHalf` uses a `Hashtable` keyed by `Vertex`.
`RenderInterlace` decides an edge's direction with `edge.getV1().equals( vertex )`.
`Loose.equals` on points is a value comparison and ports cleanly, but
identity-keyed lookups need an explicit scheme — indices, or a stable vertex key
mapped to state.

**Decide about the degenerate cases explicitly.** The source carries three known
imperfections, each with its own comment: `Rosette`'s parallel-segment `null` skip
(`n = 12`, `q = −0.8`, `s = 4`), `FillRegion`'s gaps at the region edge, and
`RenderInterlace`'s `sin θ` gap error. Each can be reproduced faithfully or fixed,
but fixing changes output, so each is a deliberate decision to record rather than a
refactor to make quietly.

Finally, the face situation is more nuanced than `Map`'s own comment implies.
`Map` does not maintain faces *as part of the graph*, but `geometry/Faces.java`
exists precisely to pay that debt, and its header says so: "Here's where I pay the
price for not implementing a complete doubly-connected edge list data structure."
The extraction is implemented, not left to the caller.

`Faces.extractFaces( map, blk, wht )` walks the map to build every face, then
propagates colours with a depth-first search over an explicit `java.util.Stack`,
filling the two vectors with the corner points of a **two-colouring** of the
faces. Two properties belong in a port:

- It assumes a *checkerboard* diagram — every vertex of even degree, except
  possibly at the borders. When that assumption fails it does not silently return
  nonsense; it throws `InternalError( "Filling problem 1" )` on an inconsistent
  colouring.
- It returns `Polygon`s rather than graph structures, because "the only code that
  cares about faces doesn't need graph information about the faces, just the
  coordinates of their corners". Anything needing face *adjacency* has to redo the
  walk rather than reuse this.

So face-based work is a **port**, not new development — but it carries the
even-degree precondition with it. `Faces` changed only by generics between the
releases (`Vector<Vertex>` in `extractFace`), so both caveats carry over
verbatim.

---

## Changes from 0.3 to 1.1.12

This document describes 1.1.12. The original 2000 release, `reference/0.3/`, is
kept alongside as the baseline, and this section records what changed — both
because the deltas matter for a port, and because it is the evidence behind the
corrections made above.

The 2000 header promised the licence might be relaxed, and it was: Taprats now
lives on SourceForge, credited to Kaplan with Pierre Baillargeon, last touched
2019.

That release is a substantial refactor rather than a patch. Since 1.1.12 is the
version to port from, the size of the change is worth stating precisely.

- **It is not a patch.** Of the 36 paths the two releases share, **32 differ
  substantively**. Only four are unchanged once reformatting and comments are
  discounted: `DesignElement`, `Rect`, `UnitCallback`, `WindowCloser`.
- **30 files disappear and 66 appear.** Most disappearances are relocations, not
  deletions: UI classes are redistributed into new subpackages, and
  `tile/DesignerPanel`, `FeatureView`, `Selection` and `TilingViewer` move under
  `ui/tile/`. `general/Comparison` and `general/Sort` are genuinely gone,
  replaced by the standard library — the commit message reads "Replaced the
  home-grown sorting with the faster…".
- **The directory layout stops mirroring packages.** Sources move from
  `csk/taprats/app/` to `app/`, but the declarations still read
  `package csk.taprats.app;` — the layout is flatter, the namespace is not. The
  package count actually *grows*, from 7 to 16: new top-level `i18n`, `plugins`
  and `style`, and `ui` splitting into `ui/figure`, `ui/geometry`, `ui/style`,
  `ui/tile` and `ui/toolkit`.
- **Render styles leave the UI.** `ui/Render*` becomes `style/*` with the prefix
  dropped — the split `RenderStyle`'s own comment predicted — and two styles are
  added, `Colored` and `Thick`.
- **Built-in tilings stop being code.** `Tiling.java` sheds roughly 480 lines,
  and `KnownTilings` takes over the dictionary, loading the tilings at startup
  instead of emitting them as Java.
- **New material**: `i18n/` (three classes, including a French translation),
  `Version.java`, and `plugins/SVGExporter.java` — SVG export arriving as a
  plugin, years before girihelix makes SVG its native output.
- **Indentation is converted from tabs to four spaces** throughout, which is
  worth knowing when diffing the two trees by hand.

What this means for the imperfections recorded above:

| Imperfection | Status upstream |
| --- | --- |
| `Rosette` parallel-segment `null` skip | **Still open** — FIXME and punt verbatim |
| `FillRegion` gaps at the region edge | **Still open** — comment verbatim, client still expands |
| `RenderInterlace` gap wrong by `sin θ` | **Still open** — FIXME still present |
| `RenderInterlace` recursion / stack overflow | **Fixed** — rewritten around an explicit `Stack<Edge>`, precisely the remedy the 2000 comment itself proposed; the `-Xss10M` note is gone |
| `Intersect`'s dead `TOL = 1e-9` | **Fixed** — the unused constant was deleted |
| `Loose` tolerances | **Extended** — `TOL`/`TOL2` unchanged, with `NEAR_TOL` and `near/2,3` added |

Two consequences follow. Three of the degenerate cases are still unfixed more
than fifteen years later, so they are not oversights awaiting a tidy-up; they are
judgement calls about the design space, and should be treated as decisions rather
than defects. And the newer release contains algorithms the 2000 source does not.
Its UI corroborates the feature list directly: `ui/figure/` gains
`ExplicitGirihEditor`, `ExplicitHourglassEditor` and `ExplicitIntersectEditor`
alongside the star and rosette editors. Wanting any of that means choosing to
derive from GPL code.

### Licensing consequence

Two facts must be kept apart, because the upstream project contradicts itself.

The **2000 source** carries no licence file, only a per-file header reserving all
rights — "You may not copy, redistribute or reuse this source code". It cannot be
published, so it lives in `reference/0.3/`, which is git-ignored.

The **newer source** is clearly redistributable but not clearly versioned. The
project page and bundled `License.txt` both say GPLv2, while every source file
header says "either version 3 of the License, or (at your option) any later
version". The file headers are the operative grant, so the code reads as
**GPLv3-or-later**, with the GPLv2 `License.txt` looking like a stale artifact
from before relicensing. That discrepancy is upstream's and cannot be resolved by
preference here.

Either way it is copyleft, so a girihelix ported from this code is a derivative
work and carries the same licence. GPLv3 also adds terms GPLv2 lacks — a patent
grant and anti-tivoization.

**Decision taken.** girihelix is licensed **GPLv3-or-later**, matching what the
upstream file headers actually grant. Neither reference tree is published: both
`reference/0.3/` and `reference/1.1.12/` are git-ignored and kept locally only,
so the repository contains no third-party source, and contributors fetch the
upstream reference themselves. The licence text is at the repository root.

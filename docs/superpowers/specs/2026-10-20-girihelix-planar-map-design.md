# Planar map and Taprats reference harness — design (Plan 1b)

**Date:** 2026-10-20
**Status:** implemented 2026-10-20 (Plan 1b).
**Related:** [engine types design](2026-10-17-girihelix-engine-types-design.md) ·
[workbench design](2026-10-16-girihelix-workbench-design.md) ·
[porting specification](../../algorithm-analysis.md) ·
local only: `reference/porting-notes/geometry.md` sections 3–5 and 13–15

## Rulings made during planning

These were made while planning Plan 1b and supersede the design text below where
they differ.

1. **`replicate` takes three arguments:** `replicate(receiver, unit, transforms)`.
   The design's "`replicate/2`" counted only Taprats' parameters, not the
   receiver.
2. **`verify/1` is a test aid, not ported behaviour.** Taprats' own `verify` is
   unreachable from its application path, apart from one debug entry point. It
   throws a `NullPointerException` on a missing ring entry, and that is not
   reproduced: ours reports a problem instead. Golden comparison of `verify` is
   made only where Taprats reports `true`.
3. **Three more flaws join the five listed below.** All are reproduced and
   recorded in `docs/algorithm-analysis.md`:
   - **6, flips leave rings reversed.** `scale/2` with a negative factor, or
     `transform/2` with a flipping transform, leaves every neighbour ring in its
     old rotational order.
   - **7, `replicate/3` never splits.** It finds or creates vertices without
     splitting edges, so two unit vertices landing on one receiver vertex make a
     self-edge.
   - **8, `transform/2` reangles against partly-moved neighbours.** Ring order is
     unaffected, but later insertions land where Taprats puts them, not where the
     true angles would.

The `TimSort` risk described under the faithful flaws materialised. A single
golden probe (`sort-probe-replicate`) agreed with Elixir's stable sort, but only
by chance: a fuzz of reversed edge keys in overlapping `1e-7` windows diverged
from Taprats in 10 of 12 cases. The user chose to reproduce Java's sort.
`Order.sort/3` now does so, through `JavaSort` (binary insertion below 32
elements, `TimSort` above), pinned by the twelve `sortfuzz-*` goldens.

## Intent

Port Taprats' planar map: the graph of vertices and edges, embedded in the plane,
that every later stage builds. The figures write into it, `Prototype` replicates
and welds it into a design, `Faces` walks it, and the renderers draw it. Nothing
downstream can be verified until this is right.

Alongside it, build a **Taprats reference harness**. This means running the real
Taprats 1.1.12 to capture its answers for known inputs, so the port is checked
against the program it ports rather than against hand-derived expectations. The
same harness later supports the side-by-side comparison that any deliberate fix
must pass.

This is the first half of what the workbench design called Plan 1's remainder. It
was split at review: Plan 1b is `Vertex`/`Edge`, `PlanarMap` and the harness;
Plan 1c is `Faces`, `FillRegion` and `Rect`.

## Goals

- **A `PlanarMap` that matches Taprats exactly in structure.** Same vertices and
  edges, same sort order, same neighbour order around every vertex (including
  which neighbour comes first), same results from `replicate` and `weld`.
- **Coordinates that match Taprats to `1e-12`.**
- **A harness that makes that checkable**, locally, with one command, for any
  scenario written down as a script.
- **Code a reader can follow**: the geometric decisions as small named functions,
  the iteration as plain `Enum`.

## Non-goals

- `Faces`, `FillRegion` and `Rect`. They are Plan 1c.
- The per-vertex and per-edge `data` payload. Plan 5's renderer needs it. Plan 1b
  only guarantees that handles are stable, so a side table can be keyed by them.
- Any fix to a Taprats flaw. Flaws are reproduced and recorded here, and fixed
  later behind side-by-side evidence.
- Workbench exhibits for the map. They are Plan 2.
- Better asymptotic performance than Taprats has.

## Anti-goals

These would count as failure even if the tests passed:

- **Silently "fixing" Taprats.** Every divergence from its behaviour is either a
  recorded decision or a bug.
- **Vertex or edge values living outside the map.** A caller holding a vertex
  struct across a change to the map sees a stale snapshot. Callers hold handles.
- **Committing reference material.** The harness and its fixtures stay local, like
  `reference/` itself.

## Decisions taken with the user

- **Faithful first, fixes later.** Known flaws are reproduced, each isolated at one
  named function, so a corrected sibling can be added later rather than an edit
  made. A fix is accepted only after rendering both versions side by side in the
  workbench shows it is a real improvement.
- **Handles, not live objects.** Vertices and edges are named by integer handles,
  and only the `PlanarMap` holds their state. Every operation returns the new map,
  plus the handle it created where that is useful. Callers thread the map through
  `Enum.reduce` and friends:

  ```elixir
  {map, tip} = PlanarMap.insert_vertex(map, a)

  {map, _ends} =
    Enum.reduce(points, {map, {tip, tip}}, fn point, {map, {top_prev, bot_prev}} ->
      {map, top} = PlanarMap.insert_vertex(map, point)
      {map, bot} = PlanarMap.insert_vertex(map, Point.new(point.x, -point.y))
      map = map |> PlanarMap.insert_edge!(top_prev, top) |> PlanarMap.insert_edge!(bot_prev, bot)
      {map, {top, bot}}
    end)
  ```

- **Algorithm separated from busy-work.** Each Taprats method is restructured so
  that the geometric decision — which edge to split, which crossings count, which
  vertex survives a coincidence — is a small named pure function, and the
  iterating, index juggling and re-sorting is plain `Enum`. Restructuring the
  source's control flow to get there is expected. The named decisions are also
  the natural step labels for the workbench.
- **`PlanarMap` is `@opaque`.** Its invariant, that no edge crosses another, is a
  property of everything inserted so far, so no constructor can enforce it. It
  stays a documented precondition. There is a fast unchecked insert, as Taprats
  has, and one checked variant for callers who want it.
- **Explicit mappings instead of scratch pointers.** Taprats' `copy` field, written
  onto every vertex during a merge and swept up afterwards by `cleanCopy()`,
  becomes an explicit old-handle-to-new-handle map returned by the merge.
- **Renderer data in a side table**, keyed by handle (Plan 5).
- **The comparators stay as Taprats has them**: `1e-7` windows, non-transitive,
  with the early-exit scans that depend on the sort order.
- **Names:** `PlanarMap`; `replicate/3` for `mergeSimpleMany`; `weld/2` for
  `mergeMap`.
- **The Taprats reference harness is local only.** Its driver code and fixtures are
  not committed.
- **A handle that is not in the map is an error a caller can match.** Every
  function that takes a handle returns `{:ok, …}` or
  `{:error, :unknown_vertex | :unknown_edge}`, and has a bang twin that raises
  `ArgumentError` instead. Code that has just created the handles it passes,
  such as a figure builder, uses the bang twins, so the threading stays a plain
  pipe. A handle goes stale after `remove_vertex/2`, after `weld/2` (where the
  other map's handles mean something only through the returned mapping), or
  when it comes from a different map.

## The planar map

### What it holds

My call on the shape, with the requirement it serves:

- Vertices by handle, each with its position and its **neighbour ring**: the
  incident edges in angle order, with a definite first element. Taprats inserts
  into the ring without moving its head, and `ScaleFigure`/`ConnectFigure` scan
  "the first neighbour below the axis", so the head is behaviour, not
  presentation.
- Edges by handle, each with its two endpoint handles in order (`v1`, `v2`).
- The vertex handles in Taprats' vertex order (lexicographic by position, `1e-7`
  per component) and the edge handles in its edge order (by minimum x, `1e-7`).
  Both orders are maintained the way Taprats maintains them — by insertion into
  position, or by a stable re-sort at the points where Taprats sorts — not
  recomputed from scratch. With non-transitive comparators the two can differ.
- The next free handle. Handles are never reused within a map.

Angles in the ring use Taprats' `pseudoAtan2`, not `:math.atan2/2`. The notes
allow substituting `atan2` if every comparison comes out the same, but the
faithful function costs nothing and removes the question.

### Operations in scope

Each has a v1 caller in the reference tree. The checked names are my call.

Functions that take only points or transforms cannot meet a stale handle, so
they return bare values. Functions that take a handle follow the decision above:
the table names the non-bang form, and each also has a `!` twin returning the
bare value.

| Elixir | Taprats | v1 callers |
| --- | --- | --- |
| `new/0` | `new Map()` | everything |
| `insert_vertex/2` → `{map, v}` | `insertVertex` (`getVertex_Complex`: find or create, then split at most one edge) | figures, `Infer` |
| `insert_edge/3` → `{:ok, map}` | `insertEdge` | figures, `Infer` |
| `insert_edge_checked/3` → `{:ok, map} \| {:error, :crosses}` | none | callers who want the check |
| `remove_vertex/2` → `{:ok, map}` | `removeVertex` | `ConnectFigure` |
| `transform/2` | `transformMap` | `Infer`, `ConnectFigure` |
| `scale/2`, `translate/3` | `scale`, `translate` | `Prototype`, `Infer`, figures |
| `replicate/3` | `mergeSimpleMany` | `Prototype`, `RadialFigure` |
| `weld/2` → `{map, mapping}` | `mergeMap` | `Prototype`, `Infer` |
| `verify/1` → `:ok \| {:error, problems}` | `verify` | `Prototype`, `ConnectFigure`, `Infer` (debug) |

Three details, each my call:

- **`insert_edge/3` returns the map, not the new edge.** No v1 caller uses the
  edge Taprats returns: Star, Rosette, `Infer`, `ScaleFigure` and
  `ConnectFigure` all discard it. Returning the map keeps the bang twin
  pipeable. A caller that needs the edge can find it with `neighbour/3`.
- **`weld/2`'s mapping covers the other map's original vertices only**, from each
  original handle to the receiver handle it became. Nothing in Taprats reads the
  `copy` pointers after a merge, so the narrowest useful mapping is enough. It
  includes neither edges nor the vertices that step 2's splits create.
- **`insert_edge_checked/3` reports `:crosses` whenever the new edge would meet
  the map anywhere except at its own two endpoint vertices.** That includes:
  - a proper crossing
  - passing through an existing vertex
  - an endpoint lying inside an existing edge (a T-junction)
  - a collinear overlap
  - a duplicate of an existing edge
  - an edge from a vertex to itself

  That is the invariant as Taprats' class comment states it: no edge crosses a
  vertex or another edge. Because `Intersect` treats parallel segments as no
  crossing, overlaps and duplicates need their own test.

Queries, which every downstream stage needs:

- counts
- vertices and edges in Taprats order
- a vertex's position
- an edge's endpoints
- a vertex's neighbour ring from its head
- `neighbour/3` (`getNeighbour`)
- `before_and_after/3` (`getBeforeAndAfter`, used by `Faces` and the renderers)

`clone` needs no port, because values are immutable.

**Out of scope,** because it is unreachable from v1:

- `transformVertex`, called only by the desktop app's map-viewer. Its skipped
  re-sort bug therefore never arises.
- `mergeSimple`, which has no callers.
- `dump`, a debug printer.

`removeEdge` exists only as the internal helper `remove_vertex/2` needs.

### Step sequences

Per the workbench design, an algorithm with internal stages is a step sequence
with a plain function built from it, pinned together by a test.

- **`weld/2` is a step sequence.** Its stages are:
  1. find every crossing between the two maps
  2. force a vertex at each crossing, in both maps
  3. unify coincident vertices, receiver winning ties
  4. copy the other map's edges across
- **`replicate/3` is my call:** one step per transform, labelled with the
  transform.
- `insert_vertex/2` and the rest are primitives with no `steps/…`. A
  one-step-per-call sequence would be a tautology.

### Faithful flaws, each at one named seam

Each is reproduced, recorded in `docs/algorithm-analysis.md`, and isolated so a
corrected sibling can be added beside it:

1. **Non-transitive `1e-7` comparators** for the vertex and edge orders.
2. **At most one edge split per `insert_vertex/2`.** A point on two edges splits
   one; the repeat calls in `weld/2` rely on the second call being harmless.
3. **The receiver wins ties in `weld/2`**, and a cluster of the other map's
   vertices near one receiver vertex can partly map onto it and partly create new
   vertices.
4. **Overlapping collinear edges are not welded**: `Intersect` reports parallel
   segments as no crossing.
5. **Duplicate angles in a neighbour ring** take whichever slot is met first.
6. to 8. Added by ruling 3 above: flips leave rings reversed, `replicate/3` never
   splits, and `transform/2` reangles against partly-moved neighbours.

**The `TimSort` risk.** Java's `Collections.sort` is stable and can throw on a
non-transitive comparator. Elixir's `Enum.sort/2` is stable and never throws.
Both are stable, so for real data — where near-equal keys are the same geometric
point — they usually produce the same order. On short lists Java falls back to
binary insertion sort, which can disagree with a merge sort when the
comparator is non-transitive. The coincident-cluster `weld/2` scenario is the
likeliest place for this to show.

My call, following "faithful first": if a scenario differs from Taprats
**only** because the two sorts order near-equal keys differently, the fix is to
port Java's sort — binary insertion below 32 elements, `TimSort` above — into
the comparator seam. A recorded divergence is not an acceptable end state. The
plan should run that scenario early, so the cost of the port is known before
the rest is built on the order.

## The Taprats reference harness

### Where it lives

`reference/oracle/`, already git-ignored. It contains:

- `build`: a script that compiles Taprats' `src/`, excluding `plugins/`, and the
  drivers.
- Java driver sources, in Taprats' own `csk.taprats.geometry` package so they can
  reach package-private methods.
- `fixtures/`: the generated output.

Measured on 2026-10-20: Taprats compiles with the installed Java 21 and runs
headless (`-Djava.awt.headless=true`). It needs no Batik, which is only used by
the SVG-export plugin.

### Scenarios as scripts

My call: a scenario is a short **operation script**, a list of steps like these:

```text
insert_vertex 0.0 0.0
insert_vertex 2.0 0.0
insert_edge 0 1
insert_vertex 1.0 0.0
weld <scenario-name>
```

Both sides interpret the same script:

- the Java driver against Taprats
- an Elixir test helper against `PlanarMap`

Each vertex operation names its result by the order it was created (0, 1, 2, …),
so the script never depends on handle values. One format then serves every
scenario, and adding a scenario is writing a script, not writing code twice.

### What a fixture records

After the script runs, the map is dumped:

- every vertex in Taprats order, with its position written by `Double.toString`
- every edge in Taprats order, by its endpoints' positions in the vertex order
- every vertex's neighbour ring from its head, as edge positions

Positions in Taprats' order are the common language, because neither side's
internal handles mean anything to the other. Java's `Double.toString` and
Elixir's float printing both produce the shortest string that round-trips, so a
coordinate in a fixture is exactly the value the JVM computed.

### How the comparison works

- **Exact:** vertex and edge counts, both orders, every ring and every ring head.
- **To `1e-12`:** coordinates, because Java and Erlang trigonometry can differ in
  the last bit.

A coordinate difference larger than that is a real divergence to investigate,
never a tolerance to widen.

### Running without fixtures

The golden tests carry a tag. `test_helper.exs` excludes that tag when
`reference/oracle/fixtures/` is absent, so a fresh clone's suite passes without
them. On a machine with the harness built, the golden tests run in the normal
gates.

### Scenarios for Plan 1b

The scenarios cover each operation and each faithful flaw. At minimum:

- a vertex landing on an edge
- a point on two edges
- a vertex near an endpoint
- the duplicate-angle ring
- `remove_vertex/2`
- `transform/2`, `scale/2` and `translate/3`
- `replicate/3` of a small unit under a rotation ladder
- `weld/2` of two crossing squares
- `weld/2` with a coincident cluster
- `weld/2` with overlapping collinear edges
- `verify/1` on a good map and on a deliberately broken one

The builder may add scenarios. Figures arrive in Plan 3, and their output becomes
a further, richer source of scenarios then.

## Constraints

- **Engine purity:** `lib/girihelix/engine/` uses the standard library only.
- **The hard rules in `AGENTS.md`:**
  - branch in function heads and guards
  - error tuples, not raises, except in `name!` twins
  - reasons are atoms
- **The type tiers from the engine types design.** A `Segment` built from computed
  points goes through `Segment.new/2`, and `{:error, :coincident_points}` takes the
  same path as a `nil` crossing (see the `Intersect` section of the analysis
  document).
- **No module over 800 lines.** `PlanarMap` will want splitting — for example the
  ring, insertion and splitting, and `weld` — behind the one public module.
- **Dialyzer must stay clean.** It is what enforces `@opaque`.

## Left to the builder

- Internal field names and the exact module split.
- The exact `problems` returned by `verify/1`, provided they cover Taprats' checks.
- Whether vertex and edge records are structs or tuples inside the map.
- The fixture file format, provided it records what is listed above.
- The checked insert's algorithm, provided it reports `{:error, :crosses}`
  exactly when the unchecked insert would break the invariant.
- Additional scenarios.

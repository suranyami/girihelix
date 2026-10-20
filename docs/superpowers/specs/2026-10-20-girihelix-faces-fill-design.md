# Faces, fill region and rect — design (Plan 1c)

**Date:** 2026-10-20
**Status:** implemented 2026-10-20 (Plan 1c). The user opted out of
brainstorming questions, so every decision not inherited from earlier designs
is marked "my call".
**Related:** [planar map design](2026-10-20-girihelix-planar-map-design.md) ·
[engine types design](2026-10-17-girihelix-engine-types-design.md) ·
[workbench design](2026-10-16-girihelix-workbench-design.md) ·
[porting specification](../../algorithm-analysis.md) ·
local only: `reference/porting-notes/geometry.md` §9–12

## Intent

This plan finishes Plan 1's geometry layer, porting the three modules left after
the planar map:

- **`Faces`:** walks a planar map's faces and two-colours them, so neighbouring
  faces get opposite colours. Plan 5's "Filled" render style paints with it.
- **`FillRegion`:** finds every lattice translate whose unit lands over a
  region. `Prototype` (Plan 4) uses it to stamp the translational unit across
  the view.
- **`Rect`:** an axis-aligned rectangle with union, intersection and a
  fit-inside transform, used for viewports and bounds.

## Inherited decisions

These are settled by earlier designs and the user's standing guidelines, not
re-decided here:

- **Faithful first.** Reproduce Taprats' output, flaws included. Record each
  flaw at one named function, pinned by a test. Fix later, only with
  side-by-side evidence.
- **Algorithm separated from busy-work.** The geometric decisions are small
  named pure functions; the iteration is plain `Enum`.
- **Error tuples.** A Java `throw` on input a caller can supply becomes
  `{:error, reason}`, with a `name!` twin that raises. The reasons are atoms.
- **Step sequences.** The workbench design names `extract_faces` and `fill`
  as step-sequence subjects, so each gets a `steps/…` function plus a plain
  function built from it, pinned together by a test.
- **Verified against Taprats.** New harness operations extend the local
  reference harness, and golden scenarios compare the port with real Taprats.
- **Engine purity, the hard rules, and dialyzer clean.**
- **`PlanarMap` is reached only through its public API.**

## Faces

### Behaviour

`Faces.extract_faces/1` takes a `PlanarMap.t()`. It follows porting notes §9:

1. **Discover faces.**
   - For every edge in Taprats edge order, walk the face on its v1→v2 side, then
     its v2→v1 side, skipping a side that is already registered.
   - The walk turns at each vertex using the ring's "before" neighbour.
   - It abandons the whole face, with no result, on entering a vertex of
     degree 1.
   - It stops at the first return to its starting vertex. A figure-eight
     therefore yields a partial face, faithfully.
   - Clockwise faces are rejected as the outer face, but their edges still
     register. That registration affects which faces the colouring can reach,
     so it must be kept.
2. **Two-colour the faces.**
   - Start a depth-first search, with a stack, from the first face discovered.
   - Mark each popped face from its already-coloured neighbours. A neighbour
     that is still `PROCESSING` contributes nothing.
   - Conflicting neighbours are Taprats' `InternalError("Filling problem 1/2")`.
3. **Collect** the black faces and the white faces.

### Interface (my calls)

- **`extract_faces(PlanarMap.t())`** returns
  `{:ok, %{black: [[Point.t()]], white: [[Point.t()]]}} | {:error, :filling_conflict | :no_faces}`,
  and has a bang twin.
  - A face is its corner points in traversal order, with no repeated closing
    point. It is **not** a `Polygon`, because a face can have two corners (for
    example between two parallel edges) and `Polygon` requires three.
  - `:no_faces` covers a map with no discoverable face, where Taprats throws
    `ArrayIndexOutOfBoundsException`.
  - Faces within each colour are listed in Taprats' discovery order.
- **The face state lives in plain Elixir maps.** Taprats keys its two tables on
  edge identity. Here they are maps keyed by `PlanarMap` edge handle, and the
  `face_info` state is an explicit accumulator.
- **Steps:** discover the faces, colour them, collect the colours.

## FillRegion

### Behaviour

`FillRegion.fill` follows porting notes §10:

1. Change basis into translation-vector coordinates.
2. Scanline-fill the quadrilateral in that basis, from `floor(ymin)` to
   `floor(ymax)` inclusive.
3. Report each integer cell `{t1, t2}`, in Taprats' emission order.

Two behaviours are kept faithfully:

- **The documented edge gaps.** The fill can leave gaps around a region's edge;
  Taprats leaves the workaround to the client, which expands the region first.
- **The 999-row cap.** More rows than that is Taprats'
  `IllegalArgumentException("Too many units")`.

### Interface (my calls)

- **`fill([Point.t(), Point.t(), Point.t(), Point.t()], t1 :: Point.t(), t2 :: Point.t())`**
  returns `{:ok, [{integer(), integer()}]} | {:error, :degenerate_basis | :too_many_units}`,
  and has a bang twin.
  - The four-point list is in the function head, so the compiler rejects any
    other length at the call site (tier 2).
  - `:degenerate_basis` covers `t1` and `t2` being parallel. Taprats divides by
    a zero determinant and carries Infinity or NaN; Elixir's `/` raises. This
    is a deliberate, recorded divergence on input that has no meaningful
    answer.
- **A list, not a callback.** Taprats streams cells into a `UnitCallback` with
  no way to cancel; the cell list is the same information, in the same order.
- **Horizontality** keeps Taprats' exact `fy == ty` test.
- **Steps:** change basis, find the rows, scan each row.

## Rect

`Rect` follows porting notes §11:

- **The y-down convention is kept:** `bottom = y - height`.
- **Constructors:** from x, y, width and height; from a point plus width and
  height; and from top-left and bottom-right points.
- **Accessors:** left, right, top, bottom, width and height.
- **Operations:** `union/2`, `intersection/2`, `central_scale/2`, and
  `center_inside/2`, which returns the `Transform` fitting one rect inside
  another.

My calls:

- **`Rect` is a plain `@type`**, because any four doubles make a rectangle.
- **`intersection/2` returns `{:ok, rect} | {:error, :disjoint}`.**
  - It returns `{:error, :disjoint}` exactly where Taprats returns `null`,
    which is when the rectangles are strictly disjoint (`nrx < nx` or
    `nry > ny`).
  - Rectangles that merely touch give a zero-extent rect, faithfully.
  - It is a tuple rather than `nil`, because a disjoint pair is expected data
    the caller matches.
- **No step sequence:** `Rect` is a value type.

## The harness

My call: the reference harness gains three script operations, and the dump
gains three record types.

| Script op | Taprats call | Dump record |
| --- | --- | --- |
| `faces <map>` | `Faces.extractFaces` | `black <x y …>` and `white <x y …>` lines, in Taprats' order, or `faces error` |
| `fill <x y ×4> ; <t1x t1y> ; <t2x t2y>` | `FillRegion` with a recording callback | `cell <t1> <t2>` lines, or `fill error` |
| `rect …` ops | `Rect` methods | one line per result |

The plan fixes the exact syntax. As before, structure compares exactly and
coordinates to `1e-12`.

## Goals

Golden scenarios from Taprats cover:

- every map shape Plan 1b's harness already builds;
- a hub with dangling edges, so a face is abandoned on reaching a degree-1
  vertex;
- a figure-eight;
- a conflicting colouring;
- a degenerate fill basis;
- a fill that hits the 999-row cap;
- a fill that shows the edge gaps.

## Non-goals

- Fixing the fill gaps, or Taprats' colouring order. Both are faithful flaws.
- Face adjacency. Taprats returns coordinates only.
- Rendering. That is Plans 2 and 5.

## Left to the builder

- Internal state shapes.
- The exact harness script syntax, within the table above.
- Additional scenarios.

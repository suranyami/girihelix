# girihelix domain model — design

**Date:** 2026-10-16
**Status:** designed in brainstorming; awaiting review of this document
**Porting source:** Taprats 1.1.12 (changeset `b6c172`)
**Specification:** [`docs/algorithm-analysis.md`](../../algorithm-analysis.md)

## Purpose

girihelix is an Elixir/Phoenix/Ash reimplementation of Taprats, Craig S.
Kaplan's tool for generating Islamic star patterns. It is primarily a **learning
reference** — the algorithmic core should read like the specification it ports —
and secondarily an **online showcase**.

## Success criteria

1. A user can pick a built-in tiling, decorate its regular tiles with stars,
   rosettes and extended rosettes, choose a render style, see the result, and
   save it as a Design they can return to.
2. The engine is testable as pure functions, with no database.
3. The code is legible enough to serve as a worked example of the algorithms.

## Scope — v1

**In:**

- Radial figures: `Star` (the `[n/d]s` construction), `Rosette` (Lee's
  construction), `ScaleFigure`, `ConnectFigure`
- The tiling catalogue, seeded read-only from Taprats data
- The instancing pass (Taprats' `Prototype.construct`)
- Render styles: `Plain`, `Filled`, `Outline`
- Persisted `Design` resources

**Out**, and recorded as intentions below:

- Contact inference for irregular tiles — so irregular tiles render undecorated
- `ExplicitFigure`
- `Interlace` rendering
- Aperiodic tilings
- Colour systems, ornamentation techniques, alternative geometries

## Architecture

Two layers, with a single direction of dependency.

**Catalogue and authored data — Ash and Postgres.** The tiling catalogue
(read-only, seeded) and `Design`, the only thing a user writes.

**Engine — pure Elixir, no Ash and no database.** Geometry, figure builders, the
instancing pass, and SVG rendering.

The rule that holds this together: **the engine never imports Ash.** Ash
resources may hold engine values through custom types; never the reverse. Two
consequences follow, and both matter here: the engine is testable without a
database, and the algorithms stay readable.

## Resources

| Resource | Role | Mutability |
| --- | --- | --- |
| `Tiling` | Two translation vectors, name, description, author | Read-only |
| `Feature` | A polygon: its points plus a `regular` flag | Read-only |
| `PlacedFeature` | A `Feature` plus a `Transform` | Read-only |
| `Design` | The aggregate root | Writable |
| `DesignElement` | A feature bound to a figure | Writable |

Relationships:

- `Tiling` has many `PlacedFeature`
- `PlacedFeature` belongs to `Feature`
- `Design` belongs to `Tiling`
- `Design` has many `DesignElement`
- `DesignElement` belongs to `Feature`

`Feature` deserves a note. Taprats shares one `Feature` across several
`PlacedFeature`s so that a repeated tile is stored once; the join models that
directly, where embedding would have silently duplicated it.

Points are a typed array attribute on `Feature`, not a table. Coordinate pairs
carry no identity, and a `Point` table would hold millions of meaningless rows.
This is a plain attribute, distinct from an Ash embedded resource.

## Figures

A `DesignElement` carries one `figure` value: an `Ash.Type` union over four
variants.

| Variant | Parameters | Meaning |
| --- | --- | --- |
| `Star` | `n`, `d`, `s` | The classic `[n/d]s` star |
| `Rosette` | `n`, `q`, `s` | Lee's construction, `q` controlling sharpness |
| `ScaleFigure` | child, `s` | A child figure scaled out to its cell |
| `ConnectFigure` | child | A `ScaleFigure` whose scale is solved so rays meet |

`ScaleFigure` and `ConnectFigure` nest a child figure. That nesting is how a
rosette becomes an extended rosette, and how extended rosettes layer.

Validation is per-variant, and mirrors the clamps in the source rather than
inventing thresholds:

- `Star`: `d` clamped to `[1, n/2 − 0.01]`; `s` bounded by the integer part of `d`
- `Rosette`: `q ∈ [−0.99, 0.99]`; `s ≤ (n−1)/2`

Those clamps are behavioural specification. The analysis document makes the same
point for `Infer`: every threshold in the source is behaviour, not an
implementation detail to be tidied away.

## Rendering

A `style` value on the `Design`, together with its parameters. v1 ships `Plain`
(linework), `Filled` (filled faces) and `Outline`.

Rendering is a pure function: `Design` to a constructed map, then to SVG.

`Filled` depends on face extraction. `Faces.extract_faces/1` produces a
two-colouring of a map's faces, and assumes a checkerboard diagram — every vertex
of even degree, except possibly at the borders. On an inconsistent colouring it
raises rather than returning nonsense, and that behaviour should be preserved.

## Testing

- **Engine.** Pure-function tests against known outputs. `Star(8, 3.0, 2)` must
  produce the vertices its construction specifies; a constructed map must have
  the expected counts.
- **Ash.** Validation tests, especially the figure union's per-variant clamps,
  and the tiling and design relationships.
- **End to end.** A seeded tiling plus a design renders non-empty SVG.

## Recorded intentions

None of these are designed, built, or scheduled. They are recorded so the
architecture does not foreclose them.

1. **Contact inference.** All seven strategies, restoring decoration of
   irregular tiles. Together with `ExplicitFigure`, this is the largest single
   piece of the source not in v1.
2. **Interlace rendering.** The over-under weave, and the historical signature of
   the tradition. It is the hardest renderer, and it carries two inherited
   defects: the gap width is wrong by `sin θ` at shallow crossings, and the under
   case is the one Kaplan's own comment calls "fraught with pitfalls".
3. **Aperiodic tilings.** Smith, Myers, Kaplan and Goodman-Strauss's "hat"
   (2023, needing reflections to avoid periodicity) and the stricter "spectre"
   (2023). `Tiling` stores two translation vectors because every v1 tiling is
   periodic; an aperiodic family has no such lattice. Adding one will therefore
   require the instancing pass to take a general enumerator of placements rather
   than assume a lattice.
4. **Colour.** Historical palettes and systems, such as Sanzo Wada's.
5. **Ornamentation.** Embedding, motifs from nature, traditional patterns.
6. **Alternative geometries.** The hyperbolic plane and spheres.

## Decisions taken during brainstorming

- **Thin Ash over a pure engine**, with custom types for figure parameters.
  Modelling `Tiling`, `Feature` and figures as first-class resources throughout
  was rejected: it forces computed and often ephemeral structures into a
  persistence shape. A `Map` has hundreds of vertices, and a figure is a function
  of its parameters rather than a row.
- **Tilings as read-only Postgres rows**, rather than name-referenced data files,
  so the database enforces design-to-tiling integrity. Taprats serialised a
  prototype by tiling name and raised when the registry lacked it; this design
  removes that coupling.
- **`Feature` and `PlacedFeature` as their own tables**, not embedded, so the
  shared-feature relationship is explicit.
- **Interlace deferred.** v1 proves the pipeline with the three simple renderers
  before taking on the hardest one and its inherited defects.

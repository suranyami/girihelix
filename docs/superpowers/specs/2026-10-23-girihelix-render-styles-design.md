# Render styles — design (Plan 5)

**Date:** 2026-10-23
**Status:** accepted (2026-10-24)
**Porting source:** Taprats 1.1.12 (changeset `b6c172`)
**Depends on:** Plans 1b/1c (`PlanarMap`, the harness, `Faces` two-colouring), Plan 2 (draw ops, SVG serializer, viewport, exhibit behaviour), Plan 4 (`Construct`, the catalogue)
**Follows:** the plan series (`2026-10-16-girihelix-workbench-design.md`, Plan 5 row) and the domain model design (`2026-10-16-girihelix-domain-model-design.md`, "Render styles" section)

## Intent

Plan 5 makes a constructed tiling presentable. The engine gains render styles —
`Plain`, `Filled`, `Outline` — that turn a `PlanarMap` into draw ops, and the
workbench gains a `:styles` category whose exhibit paints the finished result of
`Construct`: pick a tiling, a figure binding, a style and a palette; the page
renders the final SVG.

This is the first plan whose output is judged by eye. Fidelity still follows
Taprats — `reference/porting-notes/rendering.md` fixes the style call sequence,
the two-colouring propagation, where it raises, and the coordinate pipeline —
but the acceptance test is a human comparing against historical patterns and
Taprats' own renders, not a canonical golden.

## Goals

- Engine styles `Plain`, `Filled`, `Outline` as values; each consumes a
  `PlanarMap` and produces the existing draw-op vocabulary.
- Face two-colouring drives `Filled`: the checkerboard propagation from
  `Faces.java` colours every face, with Taprats' consistency errors surfaced as
  error tuples, not silent paint.
- A palette model built on Sanzo Wada's *Dictionary of Color Combinations*
  (157 colours, 348 combinations), vendored with provenance.
- One `:styles` exhibit: tiling + figure binding + style + palette, rendering
  the finished map. The step-through exhibits stay uncoloured.

## Non-goals

- An interlace/weave renderer — explicitly deferred by the series with two
  inherited defects recorded; the over-under assignment is its own future
  exhibit.
- Redrawing the construct steps in colour; a style stepper. The exhibit's
  deliverable is the final frame — the construct's existing frames remain
  available but the style application is one terminal step.
- A figure-focused styled exhibit (styled stars/rosettes without a tiling) —
  agreed follow-up once the tiling-based one feels right.
- Colour systems beyond palettes, ornamentation techniques, aperiodic tilings,
  SVG export from a studio — the domain spec's recorded intentions, Plan 7's
  ground.

## Constraints

- **Engine purity.** Styles live under `lib/girihelix/engine/`, standard
  library only. Hex colours are plain data and are allowed; Phoenix/Ash are not.
- **No new dependencies.** The palette dataset is vendored JSON decoded at
  compile time with the standard library's `JSON` module and
  `@external_resource`, so the colours are embedded in the beam: there is no
  runtime file read and no `:code.priv_dir/1` path to resolve. (The tiling
  catalogue is the distinct case: it keeps its compile-time index and resolves
  its runtime `.tiling` reads through `:code.priv_dir/1`.)
- **Faithful first.** The two-colouring follows `Faces.java`'s face walk,
  clockwise test and parity propagation; the styles follow `rendering.md`'s
  class graph and call sequence. Where a style's Taprats behaviour is ambiguous,
  the porting notes win, then the Java under `reference/1.1.12/src/`, then our
  eyes.
- **Consume, don't redefine.** The Plan 2 draw ops and SVG serializer are the
  only render surface. A style's output is ordinary `[Op.t()]` values; the
  serializer needs no colour awareness it does not already have.
- **Gates.** `mix dialyzer` `Total errors: 0` before every commit; no module
  over 800 lines; `mix format --check-formatted`; no new engine `if`/`cond`.

## The styles

Taprats' style hierarchy paints the same map differently. The three v1 styles
(domain spec: `Plain`, `Filled`, `Outline`):

| Style | What it draws | Porting anchor |
| --- | --- | --- |
| `Plain` | One stroke per planar edge; the workhouse view | `rendering.md` §4, `Plain` |
| `Outline` | One mitred six-point ribbon polygon per planar edge, filled rather than stroked; no closed figure outline | `rendering.md` §6, `Outline` |
| `Filled` | Every two-coloured face as a fill (darker/lighter), plus the boundary treatment | `rendering.md` §5, `Filled` |

A style is a function of a `PlanarMap` (plus palette) — no mutable builder
state crosses the port; the exact `setMap`/`computeMapShape` call sequence from
the porting notes is consulted, and what survives as mutable Java becomes a
pure function here.

## Two-colouring

`Faces.extract_faces/1` and its parity propagation already exist from Plan 1c.
`Filled` consumes faces, not map internals: for each face, a `{:polygon,
points, :fill, opts}` op carrying its assigned colour role. An inconsistent
colouring (a vertex of odd degree — possible on hand-built maps, not on
catalogue tilings) is an error tuple from the style, matching §2.6's raise
point.

## Palettes (our call)

> **Superseded by `2026-10-24-girihelix-styles-presentation-design.md`** for the
> role mapping: missing tones are now derived by shifting lightness, not
> recycled. Kept as the Plan 5 record.

- **Dataset.** `colors.json` from `dblodorn/sanzo-wada` (MIT — the data behind
  <https://sanzo-wada.dmbk.io>): 157 colours with names, slugs, hex and
  combination membership; 348 numbered combinations. Vendored to
  `priv/palettes/` with a provenance README naming the source repo, its MIT
  licence, and Wada's 1918/1933 dictionaries as the ultimate origin.
- **Palette module.** An engine module loads the dataset at compile time
  (`combination/1` returning the palette's colours, `options/0` for the workbench
  enum). 348 combinations is the full set — a dropdown enum is fine at this
  size; browsing by base colour (the swatch pages' mode) is a follow-up.
- **Role mapping.** A combination carries 1–5 colours and a paint needs roles:
  edge/boundary, darker face, lighter face (+ background for `Outline`/`Plain`
  pages). The mapping rule is the one recorded under "Decisions taken at
  implementation" (ascending WCAG relative luminance, hex breaking ties, then
  mapped by count), and its failure mode is documented there: a two-colour
  combination with near-identical luminances reads muddy — acceptable for v1.
- **Serialisation.** Ops carry their final hexes; the palette choice happens
  when the style produces ops, and the SVG serializer emits them unchanged.

## The exhibit

> **Superseded by `2026-10-24-girihelix-styles-presentation-design.md`**: the
> shipped exhibit adds a `tiles` boolean and pins a content-centred viewport
> instead of `:fit`. Kept as the Plan 5 record.

`GirihelixWeb.Workbench.Exhibits.Styles` — `slug/0 == "styles"`, `category/0 ==
:styles`, registered after the tilings exhibits.

- Parameters: `tiling` enum (catalogue, default `8.5`), `figure` enum
  (`:rosette` / `:star` / `:none`, default `:rosette`), `style` enum
  (`:plain` / `:filled` / `:outline`, default `:filled`), `palette` enum (the
  348 Wada combinations, default `253`).
- The default tiling is `8.5` for a reason: tiling `4.5` with a rosette has one
  kept face, so `Filled` paints one flat region, while `8.5` produces 9 black
  and 8 white faces.
- Steps: the `Construct` sequence as in `instancing`, plus one terminal `:paint`
  step that runs the chosen style over the constructed map. The construct's
  frames remain for review; the last frame is the deliverable.
- `draw/2` renders the painted ops; the panel rows carry tiling, figure, style,
  palette, faces (filled), vertices, edges, and the failure reason or `none`.
- Failure frames carry over: a raising `Star`, a degenerate tiling or an
  inconsistent colouring render as failure frames, per the workbench contract.

## Decisions taken (our calls, for review)

1. One `:styles` exhibit for v1; a figure-focused styled exhibit is the agreed
   follow-up.
2. Step-through exhibits stay uncoloured; styles are a new category, not a
   parameter bolted onto `instancing`.
3. The full 348 combinations ship; browsing by base colour is a follow-up (the
   dataset supports it — each colour lists its combinations).
4. Fidelity is eye-judged with Taprats as the guide. No canonical goldens and
   no new harness operation are built for this plan; the engine's own tests
   pin counts and structure instead.
5. Palettes resolve to final hexes when the style runs; the serializer stays
   palette-agnostic.
6. The dataset is the 157-colour/348-combination JSON from `dblodorn/sanzo-wada`
   (MIT), vendored with provenance.
7. The palette-to-role mapping rule (boundary, darker, lighter, background) is
   documented at the point of decision; near-identical-luminance combinations
   may read muddy and that is acceptable for v1.

## Decisions taken at implementation

> **Superseded by `2026-10-24-girihelix-styles-presentation-design.md`** for the
> role mapping recorded below: the shipped mapping derives missing tones by
> shifting lightness. The rest of this section is the Plan 5 record.

- **Module split.** `Style` is the behaviour: it declares `paint/2`, lists the
  ids in control order, dispatches an id to its module, and owns the padded
  background op. The three styles are `Styles.Plain`, `Styles.Filled` and
  `Styles.Outline`; `Palette` holds the dataset and the role mapper. A caller
  that holds only an id never names a module.
- **Role mapping.** Colours sort ascending by WCAG relative luminance (hex
  breaks ties) and map to `edge`, `darker`, `lighter` and `background` by their
  count: one colour fills every role; two make the dark one the edge and the
  light one everything else; three map `[dark, mid, light]` to the edge and
  darker, with the light colour filling both `lighter` and `background`; four
  map in order; five or more take the first, second, second-to-last and last.
  Near-identical luminances sort arbitrarily and read muddy, and a one-colour
  combination paints flat. Both are visual, not errors, and are accepted for
  v1.
- **`Outline`'s geometry.** Each edge is one six-point ribbon polygon: the
  mitred offset points at each end with the vertex between them. A degree-one
  end is capped perpendicular; a degree-two end is mitred against its only
  neighbour; a higher-degree end is mitred against the neighbours either side
  of the edge. `abs(sin θ) < 1.0e-7` means the miter is unbounded — covering
  both the straight-through and coincident-direction cusps — so the corner
  falls back to the perpendicular offset.
- **`Filled`'s order.** White faces paint first in the lighter colour, then
  black faces in the darker one, then every map edge is stroked once in the
  edge colour. The boundary stroke stays and no background op is emitted: the
  faces cover the box themselves, and a background would paint a colour the
  picture does not use.
- **The paint step lives in the exhibit.** `Construct`'s step list is
  unchanged; `Styles` composes the construct sequence plus one terminal
  `:paint` step over the welded map. Painting is presentation, not
  construction, and the step-through exhibits stay uncoloured.
- **Defaults.** The exhibit defaults to tiling `8.5` because it yields nine
  black and eight white faces, while `4.5` with a rosette paints one flat
  region; the default palette is Wada `253`.

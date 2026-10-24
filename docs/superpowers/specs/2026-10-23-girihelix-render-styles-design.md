# Render styles — design (Plan 5)

**Date:** 2026-10-23
**Status:** draft for builder review
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
  (171 colours, 348 combinations), vendored with provenance.
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
- **No new dependencies.** The palette dataset is vendored JSON read at compile
  time exactly as the tiling catalogue is (`Jason` + `@external_resource`,
  compile-time index, runtime path resolution through `:code.priv_dir/1` — the
  Plan 4 lesson, not a CWD-relative read).
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
| `Plain` | One stroke per planar edge; the workhouse view | `rendering.md` §1, the `Style` base |
| `Outline` | The closed outline of each figure/ring as a stroke | `rendering.md` §1, `Outline` |
| `Filled` | Every two-coloured face as a fill (darker/lighter), plus the boundary treatment | `rendering.md` §2, `Filled` |

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

- **Dataset.** `colors.json` from `dblodorn/sanzo-wada` (MIT — the data behind
  <https://sanzo-wada.dmbk.io>): 171 colours with names, slugs, hex and
  combination membership; 348 numbered combinations. Vendored to
  `priv/palettes/` with a provenance README naming the source repo, its MIT
  licence, and Wada's 1918/1933 dictionaries as the ultimate origin.
- **Palette module.** An engine module loads the dataset at compile time
  (`combination/1` returning the palette's colours, `options/0` for the workbench
  enum). 348 combinations is the full set — a dropdown enum is fine at this
  size; browsing by base colour (the swatch pages' mode) is a follow-up.
- **Role mapping.** A combination carries 3–4 colours and a paint needs roles:
  edge/boundary, darker face, lighter face (+ background for `Outline`/`Plain`
  pages). The mapping rule (e.g. by luminance ordering) is the builder's, and
  must be documented as a decision with its failure mode (a two-colour
  combination with near-identical luminances reads muddy — acceptable; note it).
- **Serialisation.** Ops carry their final hexes; the palette choice happens
  when the style produces ops, and the SVG serializer emits them unchanged.

## The exhibit

`GirihelixWeb.Workbench.Exhibits.Styles` — `slug/0 == "styles"`, `category/0 ==
:styles`, registered after the tilings exhibits.

- Parameters: `tiling` enum (catalogue, default `4.5`), `figure` enum
  (`:rosette` / `:star` / `:none`, default `:rosette`), `style` enum
  (`:plain` / `:filled` / `:outline`, default `:filled`), `palette` enum (the
  348 Wada combinations, default a curated one).
- Steps: the `Construct` sequence as in `instancing`, plus one terminal `:paint`
  step that runs the chosen style over the constructed map. The construct's
  frames remain for review; the last frame is the deliverable.
- `draw/2` renders the painted ops; the panel rows carry tiling, figure, style,
  palette, faces (filled), vertices, edges.
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
6. The dataset is the 171-colour/348-combination JSON from `dblodorn/sanzo-wada`
   (MIT), vendored with provenance.
7. The palette-to-role mapping rule (boundary, darker, lighter, background) is
   documented at the point of decision; near-identical-luminance combinations
   may read muddy and that is acceptable for v1.

## Left to the builder

- The exact module split (`Style` behaviour vs three structs, the palette
  module, where role mapping lives).
- `Outline`'s precise geometry: which cycles become outlines (porting notes §1
  vs the Java `Outline` implementation).
- The role-mapping rule and the default palette.
- How `Filled`'s boundary pass composes with the face fills (Java order).
- Whether the exhibit's `:paint` step belongs in `Construct`'s list or the
  exhibit composes its own sequence over the construct's result.

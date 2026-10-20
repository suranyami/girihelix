# girihelix workbench — design

**Date:** 2026-10-16
**Status:** written, awaiting review. Implementation planning (the `writing-plans`
skill) has not yet been run.
**Related:** [domain model design](2026-10-16-girihelix-domain-model-design.md) ·
[porting specification](../../algorithm-analysis.md) ·
[porting notes](../../porting-notes/)

## Purpose

Two surfaces over one engine.

`/workbench` is a gallery of engine components. Each component is an *exhibit*
that renders its current state, lets you change its parameters, steps through the
construction one step at a time in either direction, shows the source that
produced the current step, and offers a copyable snippet that reproduces the frame
on screen.

`/studio` is the designer surface the domain spec's first success criterion
describes: pick a tiling, decorate its tiles, choose a render style, see the
result, save a Design.

They share the engine, the draw-op vocabulary, the SVG serializer and a set of UI
components. They are separate routes with separate state, because they answer
different questions: the workbench asks *how does this work*, and the studio asks
*what would this look like*.

The workbench also serves the port itself. For geometry, figures and instancing, a
rendered picture is a far better check than an assertion about vertex counts. It
is a verification instrument as well as a teaching aid.

## Success criteria

1. A visitor can open `/workbench`, choose any component, set its parameters, step
   through its construction forward and backward, see the lines of code
   responsible for the current step, and copy a snippet reproducing that step.
2. Every engine algorithm that has internal stages — `Map.merge_map`,
   `Faces.extract_faces`, `FillRegion.fill`, the figure builders and the instancing
   pass — exposes its construction as steps, and a test guarantees the stepped view
   and the plain function agree, so the debugger cannot drift from the engine. Value
   types and single-operation primitives are exempt: a sequence wrapping them would
   be a list of one-line delegations, and the agreement test would be a tautology.
3. `/studio` satisfies the domain spec's success criterion 1.
4. The engine stays pure: no Ash, no Phoenix, no LiveView, no web modules.
5. Adding a component to the workbench is adding one file, with no change to the
   framework.

## Architecture

Three layers with one direction of dependency.

| Layer | Modules | May import |
| --- | --- | --- |
| Engine | `lib/girihelix/engine/**` | the standard library only |
| Workbench | `lib/girihelix_web/workbench/**` | engine, Phoenix, LiveView |
| Studio | `lib/girihelix_web/live/**`, Ash resources | engine, Ash, Phoenix |

Three rules hold this together, and each is enforced rather than aspirational.

- **The engine never imports Ash, Phoenix, LiveView or any web module.** This
  extends the domain spec's rule. A guard test walks the engine tree and fails on
  a forbidden reference, so the boundary cannot erode by accident.
- **The source pane never reads `reference/`.** The 1.1.12 tree is GPL but
  deliberately unvendored, and 0.3 is all-rights-reserved; `/workbench` is
  publishable, so serving that source would breach its licence. The pane reads
  girihelix's own source only.
- **The draw-op vocabulary is closed.** Every producer emits the same primitives
  and one serializer renders them, so no exhibit invents markup.

## The step model

An algorithm is a labelled sequence of pure steps over a state. One interpreter
runs them and retains every frame.

```elixir
# Girihelix.Engine.Steps.Step
%Step{
  id: :clamp_d,
  label: "clamp d",                   # one line, shown on the transport
  doc: "d is clamped to [1, n/2 − 0.01]; the chord must not degenerate",
  run: &clamp_d/1,                    # (state -> state), pure
  source: {"lib/girihelix/engine/figures/star.ex", 42}
}

# Girihelix.Engine.Steps.Frame
%Frame{index: 3, step: step, state: state}

# Girihelix.Engine.Steps.Failure
%Failure{frames: [...], index: 4, step: step, exception: e, stacktrace: st}
```

The public surface:

```elixir
Steps.run(steps, initial, opts \\ [])  # {:ok, [Frame.t]} | {:error, Failure.t}
Steps.run!(steps, initial, opts \\ []) # [Frame.t], raising on failure
Steps.final(frames)                    # the state a plain caller wants
Steps.at(frames, index)                # Frame.t | nil
```

`run/3` catches a raise and reports the failing step; `run!/3` lets it propagate.
The distinction matters: **engine callers use `run!` so they get the faithful
exception** the port promises, while the workbench uses `run/3` to render the
failure as a state. `opts` accepts `:max_frames`, so a pathological construction
cannot exhaust memory on a published page; a truncated run reports the cap.

Steps are built with a macro that captures the call site at compile time:

```elixir
import Girihelix.Engine.Steps

def steps(n, d, s) do
  [
    step(:clamp_d, "clamp d", "d is clamped to [1, n/2 − 0.01]", &clamp_d/1),
    step(:chord, "the chord", "the unit grows from a → b", &chord/1),
    step(:crossings, "crossings", "intersect the chord with its rotated copy", &crossings/1)
  ]
end
```

`step/4` records `__ENV__.file` and `__ENV__.line`, which is what makes the source
pane exact: a frame knows the lines that produced it, with no introspection and no
heuristic search.

The **initial state is the parameter map**, and the first step is conventionally
`:init`, turning those parameters into the algorithm's working state. That keeps
the calling convention uniform — `Steps.run(steps, params)` — and gives the
workbench a frame zero that shows the parameters as they were received, before
anything is computed or clamped.

**Two entry points, one implementation.** Every algorithm exposes its steps and a
plain function:

```elixir
def steps(n, d, s), do: [...]

def build_unit(%Star{n: n, d: d, s: s}) do
  n |> steps(d, s) |> Steps.run!() |> Steps.final()
end
```

The studio, the tests and any future command-line caller use the plain form and
never see a frame. The workbench uses the steps. Nothing is computed twice and
nothing is stored twice.

### The trade-off this accepts

A literal transliteration of the Java would be a single function whose control
flow mirrors `buildUnit`. The step form instead names each clause of Kaplan's
prose as its own small function. That is a deliberate deviation, and it cuts both
ways.

- **For:** the code reads closer to the specification, which is the port's primary
  purpose. Frames, backward stepping, scrubbing, URL-shareable positions and
  per-frame source highlighting all fall out of one structure rather than being
  bolted on.
- **Against:** it is not the Java's shape, and for two algorithms the granularity
  has to be coarse. `Map.mergeMap` is a two-pointer walk and `Faces.extractFaces`
  is a depth-first search; for those a step is *one iteration*, not one statement.
  That is accepted rather than worked around.
- **Mitigation:** correctness is pinned by golden geometry and by invariants
  (symmetry, closure, expected vertex and edge counts), not by resemblance to the
  Java.

## The draw-op vocabulary

A closed set of primitives every producer emits and one serializer renders.

| Op | Meaning |
| --- | --- |
| `{:line, from, to, opts}` | a segment |
| `{:polygon, points, mode, opts}` | a closed shape, `mode` being `:fill` or `:stroke` |
| `{:point, at, radius, opts}` | a marker |
| `{:label, at, text, opts}` | text anchored at a point |
| `{:guide, from, to, opts}` | a diagnostic segment, dashed by default |

`opts` carries presentation overrides: `:stroke`, `:fill`, `:width`, `:dash`,
`:opacity`. The serializer raises on an unknown op, which is the gate that stops
exhibits inventing markup.

The three Taprats styles are producers of these ops, as are the workbench's
diagnostic overlays (construction points, guide rays, crossing markers). So the
renderer the studio uses and the pictures the workbench draws are the same code
path.

An exhibit returns one of three shapes, so non-geometric concepts are first-class
without polluting the vocabulary:

```elixir
{:canvas, ops}          # geometry
{:panel, rows}          # [{label, value}] rendered as a table
{:both, ops, rows}      # a picture and its numbers
```

`Loose` (a tolerance table), `Feature` equality (two features compared) and
`Polygon` (shape plus area and centroid) all need the panel form.

## Viewport and SVG

Taprats has no viewport to match: its SVG export carries no size and no `viewBox`,
and its coordinates are already floored to integers by the Swing panel. girihelix
therefore defines its own, which is a decision rather than a port.

`%Viewport{left, top, width, scale}` with `Viewport.fit(bounds, opts)` deriving a
`viewBox` from a frame's bounding box plus padding. Map space is y-up and SVG is
y-down, so the viewport applies the flip; the extract confirms Taprats flips the
same way, `Y = (top − y) · s`.

Frames auto-fit by default, but **an exhibit may pin its viewport**, because
auto-fitting every frame makes a figure appear to jitter as it is constructed —
the picture rescales each time the bounding box grows. Pinning is what makes
stepping legible. The behaviour expresses this as an optional callback:

```elixir
@callback viewport(params :: map) :: :fit | Girihelix.Engine.Render.Viewport.t()
@optional_callbacks viewport: 1
```

An exhibit that omits it gets `:fit`.

## Exhibits

An exhibit is one module implementing one behaviour.

```elixir
defmodule GirihelixWeb.Workbench.Exhibits.Star do
  @behaviour GirihelixWeb.Workbench.Exhibit

  def slug, do: "star"
  def title, do: "Star — the [n/d]s construction"
  def summary, do: "Intersecting chords of the unit circle."

  def params do
    [
      %Param{name: :n, type: :integer, range: 3..24, default: 8, doc: "rotational order"},
      %Param{name: :d, type: :float, range: 1..10, step: 0.1, default: 3.0, doc: "skip"},
      %Param{name: :s, type: :integer, range: 1..6, default: 2, doc: "steps out"}
    ]
  end

  def steps(p), do: Girihelix.Engine.Figures.Star.steps(p.n, p.d, p.s)
  def draw(frame, _p), do: {:both, ops_for(frame), rows_for(frame)}
  def reproduce(p), do: "Star.build_unit(%Star{n: #{p.n}, d: #{p.d}, s: #{p.s}})"
end
```

`params/0` is **declarative**, and that is what keeps the framework from growing
special cases: one component renders the controls, the URL encodes them,
validation is uniform, and clamping can be displayed rather than hidden.

`Param` supports `:integer`, `:float`, `:boolean` and `:enum`. Range, step and
default drive both the control and the URL decoder, so an out-of-range URL is
clamped the same way a dragged slider is.

`GirihelixWeb.Workbench.Registry` lists exhibits in display order, grouped by
category (geometry, figures, tilings, styles). `/workbench` renders the index;
`/workbench/:slug` renders one exhibit.

### The four panes

- **Canvas** — the SVG of the current frame, plus that exhibit's diagnostic
  overlays, or the panel rows for a non-geometric exhibit.
- **Transport** — first, previous, next, last, a scrub slider, and the current
  step's label and prose.
- **Source** — the real file, with the current step's lines highlighted.
- **Reproduce** — the exact call that yields this frame, copyable, with the frame
  index so a reader can navigate back to it.

### URL is the state

`?n=8&d=3.0&s=2&frame=5`, handled through `handle_params` and `push_patch`. This
buys three things at once: exhibits are shareable, which is the showcase use; a
bug is reproducible from its URL; and the transport needs no state of its own.

## The source pane

Frames carry the file and line captured by `step/3`, so the pane resolves a frame
to a line range directly. No introspection, no searching for the module on disk,
no guessing.

Highlighting is server-side via `makeup` and `makeup_elixir`, which are pure
Elixir. A JavaScript highlighter is deliberately avoided: `AGENTS.md` forbids
inline `<script>` and vendored `<script src>`, so it would have to be bundled into
`app.js` for no benefit. If the dependency is unwanted, plain monospace is an
acceptable fallback — the line pointer is the essential part, not the colour.

If the file cannot be read, the pane says so and the exhibit still works. The pane
renders girihelix's own source only, never `reference/`.

## Errors are exhibit states

Every extraction of the reference confirmed the same thing: the Java *crashes*
where it does not quietly skip. Star has no null guard where Rosette has one.

So a failure is not a 500. `Steps.run/3` returns the frames that did build, the
step that died, its label, its prose, its source line, and the exception. The
workbench renders that as an ordinary state, which means the debugger answers the
question the port keeps asking: *at which parameters, and in which step, does this
construction break?*

Clamping is displayed for the same reason. Setting `d = 99` produces a frame that
says it was clamped to `n/2 − 0.01`. This is why clamps are steps rather than
local variables: in a learning reference, a threshold the source applies is
behaviour worth seeing, not an implementation detail to be tidied away.

## Exhibit inventory

| Plan | Exhibits |
| --- | --- |
| 2 | `loose`, `point`, `transform`, `intersect`, `polygon`, `map`, `faces`, `fill-region` |
| 3 | `star`, `rosette`, `scale`, `connect`, `radial` |
| 4 | `catalogue`, `tiling`, `instancing` |
| 5 | `plain`, `filled`, `outline` |
| 6 | `design` browse |
| 7 | the studio, which reuses the canvas, param and transport components |

## Testing

Five layers, each guarding a specific way this could rot.

1. **Trace invariant.** For every algorithm, `Steps.final(steps) == plain function`.
   This is the load-bearing test: it pins the two entry points together, so the
   debugger can never show something the engine would not compute.
2. **Registry property test.** Every registered exhibit, at its defaults and at
   every parameter's range extremes, produces at least one frame and a non-empty
   picture or panel. Adding an exhibit that cannot render fails the suite. The same
   test asserts slugs are unique and every param has a default.
3. **LiveView tests.** Mount renders a canvas with SVG; next and previous change
   the frame index and label; a parameter change changes the frame count and the
   picture; an exhibit that raises renders the failure state rather than a 500.
4. **Source resolver.** A known step resolves to the expected file and line range,
   which guards the `__ENV__` capture.
5. **Engine purity guard.** The guard test behind the architecture rule: no file
   under `lib/girihelix/engine/` references Ash, Phoenix, LiveView or the web
   layer.

## Revised plan series

The domain spec's plan series assumed the workbench did not exist. It becomes
seven plans, and two boundaries move.

| # | Plan | Deliverable | Change |
| --- | --- | --- | --- |
| 1 | Engine foundation and geometry — `Steps`, `Loose`, `Point`, `Transform`, `Intersect`, `Polygon`, `Map`, `Faces`, `FillRegion` | Pure geometry authored as steps, golden-tested | gains `Steps`, loses literal transliteration as a goal |
| 2 | Workbench foundation — draw ops, SVG serializer, viewport, exhibit behaviour, `/workbench`, controls, transport, source and reproduce panes, geometry exhibits | A publishable workbench over the geometry layer | new |
| 3 | Figures — `Figure`, `RadialFigure`, `Star`, `Rosette`, `ScaleFigure`, `ConnectFigure` | `Star(8, 3.0, 2)` builds its vertices, and you can watch it do so | gains exhibits |
| 4 | Catalogue and instancing — engine `Tiling`, `Feature`, `PlacedFeature`, `construct`, `.tiling` data and parser | Tiling plus figures to a constructed map you can step through | gains exhibits |
| 5 | Render styles — `Plain`, `Filled`, `Outline` over the shared draw ops, face two-colouring | Constructed map to SVG, matching Taprats' geometry | consumes the Plan 2 serializer instead of defining it |
| 6 | Ash layer — resources, figure union type, migrations, catalogue seeding | A Design round-trips through Postgres | unchanged |
| 7 | Studio — tiling picker, figure controls, style, preview, save and load | The domain spec's success criterion 1 | was the LiveView showcase |

Plan 1's remainder, after `Steps` and the geometry value types, became Plans 1b
(`PlanarMap` and the Taprats reference harness) and 1c (`Faces`, `FillRegion` and
`Rect`). **Plan 1 is complete as of 2026-10-20.**

`Steps` lands in Plan 1 rather than Plan 2 because it decides how Plan 1's
algorithms are written; introducing it later would mean rewriting them. The SVG
substrate lands in Plan 2 rather than Plan 5 because the workbench needs it and
Plan 5's styles consume it.

The workbench is therefore publishable from Plan 2 onward. It is not scaffolding
that Plan 7 replaces.

## Out of scope

- Auto-play animation, breakpoints, conditional stepping and per-frame diffing.
- Any execution of user-supplied code. The workbench is an inspector, not a REPL.
- Pan and zoom on the canvas, which pinning makes unnecessary for v1.
- Persistence of workbench state. The URL is the state.
- Authentication. Both surfaces are public in v1.

## Recorded intentions

None of these are designed, built or scheduled.

1. **Live progress for long constructions.** A tiling over a large region, or the
   fill across thousands of units, can take long enough that a progress indication
   belongs in the studio. That is a push from a running job, so `Phoenix.PubSub` is
   the right tool there — a genuinely different feature from stepping, which is a
   pull from a finished computation and cannot work by notification.
2. **An interlace exhibit.** Plan 5 ships three styles; the weave renderer is out
   of v1 with two inherited defects. When it lands, its over-under assignment is a
   graph traversal and would step beautifully.
3. **Aperiodic tilings.** An exhibit for the hat and spectre tilings, once the
   instancing pass takes a general enumerator rather than assuming a lattice.
4. **SVG export from the studio**, so a visitor can take a design away.

## Decisions taken during brainstorming

- **Two surfaces rather than one.** The workbench is the component gallery; the
  studio is the designer. One page serving both was considered and rejected,
  because the two answer different questions and one page would leave both
  compromised. Shared components keep the duplication small.
- **The debugger goes all the way.** Parameter-driven rendering alone, and a
  pause-and-step debugger, were both offered; the full step-through was chosen,
  accepting that it constrains how every algorithm is written.
- **Steps and an interpreter, not instrumentation.** Four mechanisms were
  compared: step sequences, `Trace.checkpoint` calls inside a faithful port,
  re-running with a stop index, and a process computing one step per message.
  Step sequences were chosen because the history is then just a list, so backward
  stepping and shareable frames are free, and the engine stays pure functions that
  tests and a future command-line tool can call plainly.
- **PubSub is not the stepping mechanism.** A broadcast cannot pause a pure
  function, and it carries no state to draw. It is recorded as an intention for
  live progress on long jobs instead.
- **`Steps`, not `Trace`.** The first name collided with Erlang and Elixir's
  tracing vocabulary (`:dbg`, `:erlang.trace/3`), which is VM-level and the wrong
  altitude for this.
- **Clamps become visible steps**, not local variables, so the source's thresholds
  are shown rather than hidden.
- **A `makeup` dependency is acceptable** for server-side highlighting, in
  preference to a bundled JavaScript highlighter.
- **The engine purity rule gets a guard test**, so the boundary is mechanical
  rather than a convention.

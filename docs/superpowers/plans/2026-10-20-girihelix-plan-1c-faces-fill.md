# Faces, fill region and rect implementation plan (Plan 1c)

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port Taprats' `Faces` (face discovery and two-colouring), `FillRegion`
(lattice translates over a quadrilateral) and `Rect`, faithfully, verified
against real Taprats 1.1.12 through the reference harness.

**Architecture:**

- **Faces.** `Girihelix.Engine.Faces` works on a `PlanarMap` through its public
  API only. The face walk and orientation test are in `Faces.Walk`.
  `extract_faces` is a step sequence with three stages: discover, colour,
  collect.
- **FillRegion.** `Girihelix.Engine.FillRegion` is a step sequence with three
  stages: basis, rows, scan.
- **Rect.** `Girihelix.Engine.Geometry.Rect` is a plain value type.
- **Harness.** The reference harness gains two terminal script operations,
  `faces` and `fill`.

**Tech Stack:** Elixir 1.20.3, ExUnit, dialyxir; Java 21 for the local harness.

**Spec:** `docs/superpowers/specs/2026-10-20-girihelix-faces-fill-design.md`.
Read it in full first. The exact Taprats behaviour is in the local, git-ignored
porting notes, `reference/porting-notes/geometry.md`:

- §9: `Faces` (9.2 `extractFace`, 9.3 `getTwin`, 9.4 `isClockwise`,
  9.5 `handleVertex`, 9.6 `extractFaces`)
- §10: `FillRegion`
- §11: `Rect`

The Java is in `reference/1.1.12/src/geometry/`.

## Global Constraints

- **Faithful first.** Reproduce Taprats' behaviour, flaws included, and record
  each flaw. Never "fix" one in this plan.
- **Reach `PlanarMap` only through its public API:**
  - `vertices/1` and `edges/1`, in Taprats order
  - `position!/2`, `endpoints!/2`, `ring!/2`, `neighbour!/3`
  - `before_and_after!/3`, `num_vertices/1`, `num_edges/1`

  Never touch `%PlanarMap{}`.
- **Errors and bang twins.**
  - A Taprats `throw` on caller input becomes `{:error, reason}`.
  - Each such function has a `name!` twin that raises `ArgumentError` naming
    the reason.
  - Reason atoms, exactly: `:filling_conflict`, `:no_faces`,
    `:degenerate_basis`, `:too_many_units`, `:disjoint`.
- **Step sequences.**
  - `Faces` and `FillRegion` each expose `steps/0`, `start/…` and `result/1`.
  - Each plain function is `steps() |> Steps.run!(start(…)) |> Steps.final() |> result()`.
  - A test pins the plain function and the step sequence together.
  - No step raises on caller input. Failure is carried in the state, as
    `PlanarMap`'s `weld` does.
- **Engine purity, the hard rules and dialyzer.**
  - Engine purity: standard library only.
  - Hard rules from `AGENTS.md`: no `if` or `cond`; branch in function heads and
    guards.
  - `mix dialyzer` reports `Total errors: 0` before every commit.
  - No module may exceed 800 lines.
- **Docs carry decisions, not narration.** Write each doc as a decision in the
  caller's terms; never narrate the Java source.
- **The harness stays local.** Everything under `reference/oracle/` is
  git-ignored. Never `git add` anything under `reference/`.
- **Git, Markdown and tooling.**
  - Run `git commit` as its own command, with no bare `-n` token.
  - If a 1Password signing error occurs, stop and ask the user. Never disable
    signing.
  - Lint Markdown with `markdownlint-cli2 --config ~/.markdownlint-cli2.jsonc`.
  - `mix format` runs Styler, which can displace `# --` section comments; check
    them after formatting.
  - Never start or stop the dev server on :4000.

## Rulings against the design

1. **`Rect` is tested with hand-derived values, not the harness.** Its
   arithmetic is closed-form and transform-free except for `center_inside/2`,
   which is pinned by properties instead. The harness's `rect` operations from
   the design's table are therefore dropped.
2. **The degenerate-basis fill has no golden scenario.** Taprats carries
   Infinity or NaN and produces arbitrary cells; the port returns
   `{:error, :degenerate_basis}`. A unit test pins the port's behaviour, and the
   divergence is recorded in Task 5.

## Review Focus

1. **An empty map, or a map whose only faces are abandoned.** A path with only
   dangling ends must give `{:error, :no_faces}`, not a crash. Owner: Task 4.
2. **A face with two corners.** Two vertices joined by two parallel edges give a
   two-point face. Taprats returns it, so the port must too, not reject it as a
   polygon. Owner: Task 4.
3. **A conflicting colouring.** A map whose faces cannot be two-coloured, such as
   three faces around a vertex of odd degree, must give
   `{:error, :filling_conflict}` exactly where Taprats throws. Owner: Task 4.
4. **A fill exactly at the row cap.** The cap must match Taprats to the row:
   999 rows pass and 1,000 rows fail. Owner: Task 3.
5. **Touching rectangles.** Their `intersection/2` is a zero-extent rect, not
   `:disjoint`. Owner: Task 2.

## The new harness operations

Both are **terminal**: each replaces `dump <map>` as the script's last line.

```text
faces <map>
fill <x1> <y1> <x2> <y2> <x3> <y3> <x4> <y4> ; <t1x> <t1y> ; <t2x> <t2y>
```

The dump for `faces`:

```text
faces ok
black <x> <y> <x> <y> …        # one line per black face: corners in traversal order
white <x> <y> …                # one line per white face
```

On failure it is `faces error filling`, where Taprats throws `InternalError`, or
`faces error empty`, where it throws `ArrayIndexOutOfBoundsException`. Black
lines come first, then white, each in Taprats' order.

The dump for `fill`:

```text
fill ok
cell <t1> <t2>                 # one line per callback, in emission order
```

On failure it is `fill error too_many`, where Taprats throws
`IllegalArgumentException`.

The comparison is exact on structure, words and integers, and to `1e-12` on
coordinates.

---

### Task 1: The harness — `faces` and `fill`, both halves

**Files:**

- Modify (local): `reference/oracle/src/csk/taprats/geometry/HarnessDriver.java`
- Modify: `test/support/taprats_harness.ex`
- Modify: `test/girihelix/taprats_harness_test.exs`
- Create: `test/girihelix/engine/faces_golden_test.exs`
- Create: `test/girihelix/engine/fill_region_golden_test.exs`

**Interfaces:**

- **The Java driver** handles `faces` with `Faces.extractFaces(map, blk, wht)`,
  catching `InternalError` and `ArrayIndexOutOfBoundsException`. It handles
  `fill` by calling `new FillRegion().fill(polygon, t1, t2, recordingCallback)`
  on a four-point `Polygon`, catching `IllegalArgumentException`. Both write
  the formats above.
- **The Elixir harness:**
  - `parse_script/1` adds `{:faces, map}` and
    `{:fill, [Point.t()], Point.t(), Point.t()}`.
  - `parse_dump/1` returns, besides the map-dump shape, either
    `%{faces: {:ok, %{black: [[{x, y}]], white: [[{x, y}]]}} | {:error, :filling | :empty}}`
    or `%{cells: {:ok, [{t1, t2}]} | {:error, :too_many}}`.
  - `compare/2` handles both shapes.
  - `run_script/1` raises "not yet supported" for `faces` and `fill` until
    Tasks 3 and 4 add them.
- **Two golden modules,** each with `@moduletag :taprats` and an empty
  `@scenarios` list, which later tasks fill.

- [ ] **Step 1: Write the failing parser and compare tests,** in
  `taprats_harness_test.exs`, using inline strings:
  - `parse_script("A faces\n")` gives `[{:faces, "A"}]`.
  - `parse_script("fill 0 0 4 0 4 3 0 3 ; 1 0 ; 0 1\n")` gives
    `[{:fill, [Point.new(0.0, 0.0), Point.new(4.0, 0.0), Point.new(4.0, 3.0), Point.new(0.0, 3.0)], Point.new(1.0, 0.0), Point.new(0.0, 1.0)}]`.
  - A `faces ok` dump with one black and one white face parses as expected.
  - `faces error filling` parses to `{:error, :filling}`.
  - `fill ok` with two cells parses to `{:ok, [{0, 0}, {1, 0}]}`.
  - `fill error too_many` parses to `{:error, :too_many}`.
  - `compare/2` accepts a face coordinate within `1e-12`, and rejects a swapped
    cell order.
- [ ] **Step 2: Run them to see them fail.**
  Run `mix test test/girihelix/taprats_harness_test.exs`. Expected: FAIL.
- [ ] **Step 3: Implement both halves.** Extend the Java driver, and run it on a
  throwaway `fill` script and a throwaway `faces` script outside
  `scenarios/` to confirm it writes the formats. Then extend the Elixir harness.
- [ ] **Step 4: Run the tests to see them pass.** Run `mix test`. Expected: PASS.
- [ ] **Step 5: Gates and commit.**
  Run `mix precommit.fast && mix dialyzer` (`Total errors: 0`), then:

  ```bash
  git add test/support/taprats_harness.ex test/girihelix/taprats_harness_test.exs test/girihelix/engine/faces_golden_test.exs test/girihelix/engine/fill_region_golden_test.exs
  ```

  ```bash
  git commit -m "test: extend the Taprats reference harness with faces and fill"
  ```

### Task 2: `Rect`

**Files:**

- Create: `lib/girihelix/engine/geometry/rect.ex`
- Create: `test/girihelix/engine/geometry/rect_test.exs`

**Interfaces.** These are in `Girihelix.Engine.Geometry.Rect` (§11). The
convention is y-down: `top = y` and `bottom = y - height`.

- `@type t :: %Rect{x: float(), y: float(), width: float(), height: float()}`
- **Constructors:**
  - `new(x, y, width, height) :: t()`
  - `from_point(Point.t(), width, height) :: t()`
  - `from_corners(top_left :: Point.t(), bottom_right :: Point.t()) :: t()`.
    Width is `br.x - tl.x` and height is `tl.y - br.y`.
- **Accessors:** `left/1`, `right/1`, `top/1`, `bottom/1`, `width/1`,
  `height/1` and `center/1`.
- **`union(t(), t()) :: t()`**
- **`intersection(t(), t()) :: {:ok, t()} | {:error, :disjoint}`.** It returns
  `:disjoint` exactly when `nrx < nx` or `nry > ny` (§11.4).
- **`central_scale(t(), number()) :: t()`** (§11.5)
- **`center_inside(inner :: t(), outer :: t()) :: Transform.t()`** (§11.6)

- [ ] **Step 1: Write the failing tests:**

```elixir
test "the y-down accessors" do
  r = Rect.new(1.0, 10.0, 4.0, 3.0)
  assert {Rect.left(r), Rect.right(r), Rect.top(r), Rect.bottom(r)} == {1.0, 5.0, 10.0, 7.0}
  assert Rect.from_corners(Point.new(1.0, 10.0), Point.new(5.0, 7.0)) == r
end

test "union/2 spans both rects" do
  u = Rect.union(Rect.new(0.0, 10.0, 10.0, 10.0), Rect.new(5.0, 20.0, 10.0, 10.0))
  assert u == Rect.new(0.0, 20.0, 15.0, 20.0)
end

test "intersection/2 of overlapping, touching and disjoint rects" do
  a = Rect.new(0.0, 10.0, 10.0, 10.0)
  assert Rect.intersection(a, Rect.new(5.0, 15.0, 10.0, 10.0)) == {:ok, Rect.new(5.0, 10.0, 5.0, 5.0)}
  # touching along x = 10: a zero-width rect, not :disjoint
  assert {:ok, %Rect{width: +0.0}} = Rect.intersection(a, Rect.new(10.0, 10.0, 5.0, 10.0))
  assert Rect.intersection(a, Rect.new(20.0, 10.0, 5.0, 5.0)) == {:error, :disjoint}
end

test "center_inside/2 maps the inner centre onto the outer centre and fits inside" do
  inner = Rect.new(0.0, 2.0, 4.0, 2.0)
  outer = Rect.new(10.0, 30.0, 20.0, 20.0)
  t = Rect.center_inside(inner, outer)
  assert Transform.apply_to(t, Rect.center(inner)) == Rect.center(outer)
end
```

  Also add a `central_scale/2` test, with expected values derived from §11.5.
  Check every expected value in these tests against §11's formulas before
  running them. If a formula disagrees with a value here, the formula wins: fix
  the test, and say so in your report.

- [ ] **Step 2: Run them to see them fail.**
  Run `mix test test/girihelix/engine/geometry/rect_test.exs`.
- [ ] **Step 3: Implement `Rect` from §11.**
- [ ] **Step 4: Run them to see them pass.**
- [ ] **Step 5: Gates and commit.**
  Commit message: `feat: add Rect, with the y-down convention`.

### Task 3: `FillRegion`

**Files:**

- Create: `lib/girihelix/engine/fill_region.ex`
- Create: `test/girihelix/engine/fill_region_test.exs`
- Modify: `test/support/taprats_harness.ex`, so `run_script/1` handles `fill`
- Modify: `test/girihelix/engine/fill_region_golden_test.exs`
- Create (local): `reference/oracle/scenarios/{fill-unit-square,fill-skewed,fill-rotated-region,fill-edge-gaps,fill-cap-999,fill-cap-1000}.ops`

**Interfaces,** in `Girihelix.Engine.FillRegion` (§10):

- `fill([Point.t(), Point.t(), Point.t(), Point.t()], t1 :: Point.t(), t2 :: Point.t()) :: {:ok, [{integer(), integer()}]} | {:error, :degenerate_basis | :too_many_units}`
  and `fill!/3`. The four-point list is in the function head.
- `steps() :: [Steps.Step.t()]`, with ids `:change_basis`, `:find_rows` and
  `:scan_rows`.
- `start(region, t1, t2) :: state`
- `result(state) :: {:ok, …} | {:error, …}`
- The basis change uses the inverse of `[[t1.x, t2.x], [t1.y, t2.y]]`. A zero
  determinant (exact `== 0.0`) is `:degenerate_basis`.
- Rows run from `floor(ymin)` to `floor(ymax)` inclusive. More than 999 is
  `:too_many_units`, with Taprats' exact threshold (§10.3–10.4).
- Horizontality is the exact test `fy == ty`.
- Cells are emitted in Taprats' order (§10.5).

- [ ] **Step 1: Write the failing tests.**
  - **Unit tests:**
    - The unit square under the identity basis gives the cells Taprats would
      emit. Derive them from §10.3, and show the derivation in a comment.
    - Parallel `t1` and `t2` give `{:error, :degenerate_basis}`, and `fill!/3`
      raises.
    - `fill/3` equals the final frame of its steps.
  - **Golden scenarios:**
    - `fill-unit-square`
    - `fill-skewed`, with a non-orthogonal basis
    - `fill-rotated-region`
    - `fill-edge-gaps`, a thin sliver showing the documented gaps
    - `fill-cap-999` and `fill-cap-1000`, sized to land exactly on either side
      of the cap (Review Focus 4)

  Write the `.ops` files, run `reference/oracle/run`, and append the names to
  the golden module's `@scenarios`.
- [ ] **Step 2: Run them to see them fail (record the RED run).**
- [ ] **Step 3: Implement.** The basis, the row bounds and the per-row span are
  small named functions; the scan is plain `Enum`.
- [ ] **Step 4: Run every test and the goldens** (`mix test --only taprats`) to
  see them pass.
- [ ] **Step 5: Gates and commit.**
  Commit message: `feat: add FillRegion, filling a region with lattice translates`.

### Task 4: `Faces`

**Files:**

- Create: `lib/girihelix/engine/faces.ex`
- Create: `lib/girihelix/engine/faces/walk.ex`
- Create: `test/girihelix/engine/faces_test.exs`
- Modify: `test/support/taprats_harness.ex`, so `run_script/1` handles `faces`
- Modify: `test/girihelix/engine/faces_golden_test.exs`
- Create (local): `reference/oracle/scenarios/faces-*.ops`, as listed in Step 1

**Interfaces:**

- **In `Girihelix.Engine.Faces.Walk`** (§9.2–9.4), using the `PlanarMap` public
  API only:
  - `walk(PlanarMap.t(), from :: vertex, edge) :: [vertex] | nil`.
    - It turns by the "before" edge of `before_and_after!/3` at each vertex.
    - It returns `nil` on entering a vertex of degree below 2.
    - It stops at the first return to `from`.
  - `clockwise?([Point.t()]) :: boolean()` is Taprats' orientation test,
    exactly.
- **In `Girihelix.Engine.Faces`** (§9.5–9.6):
  - `extract_faces(PlanarMap.t()) :: {:ok, %{black: [[Point.t()]], white: [[Point.t()]]}} | {:error, :filling_conflict | :no_faces}`,
    and `extract_faces!/1`.
  - `steps/0`, with ids `:discover`, `:colour` and `:collect`.
  - `start/1` and `result/1`.
- **The rules to reproduce.** The registration tables are maps keyed by
  `{direction, edge}`, or by two maps as Taprats has (`v1`, `v2`). Discovery
  follows §9.5 exactly:
  - Faces are walked in edge order: the v1 side, then the v2 side, each only if
    not yet registered.
  - A rejected clockwise face still registers its edges.

  Colouring follows §9.6 exactly:
  - The seed is the first discovered face; no faces at all is `:no_faces`.
  - A stack is used.
  - A neighbour still `PROCESSING` contributes nothing.
  - The conflict cases are `:filling_conflict`.
  - A face with no coloured neighbour is black.

- [ ] **Step 1: Write the failing tests.**
  - **Unit tests:**
    - Two triangles sharing an edge give one black face and one white.
    - Review Focus 1: a path whose ends dangle gives `{:error, :no_faces}`.
    - Review Focus 2: two parallel edges give a two-corner face.
    - `extract_faces/1` equals the final frame of its steps.
    - `extract_faces!/1` raises on the error.
  - **Golden scenarios** (`faces-*`):
    - a square split by its diagonal
    - a 3×3 grid
    - a hub with six spokes closed by a hexagon
    - the replicate-ladder map from Plan 1b
    - a map with dangling edges
    - a figure-eight
    - Review Focus 3: a conflicting colouring
    - a two-corner face
    - a map with no faces, which should give `faces error empty`
- [ ] **Step 2: Run them to see them fail (record the RED run).**
- [ ] **Step 3: Implement.** `Walk` holds the geometric decisions. Discovery and
  colouring are folds with an explicit accumulator; the stack is a list.
- [ ] **Step 4: Run every test and all goldens to see them pass,** including
  Plan 1b's 46.
- [ ] **Step 5: Gates and commit.**
  Commit message: `feat: extract and two-colour a planar map's faces`.

### Task 5: Homogenisation pass

**Files:**

- `docs/algorithm-analysis.md`
- the spec
- `docs/backlog.md`
- the module docs from this plan

**Steps:**

1. **Record the faithful flaws** in `docs/algorithm-analysis.md`, each with its
   pinning test or golden:
   - the fill's edge gaps;
   - the 999-row cap;
   - the abandoned faces;
   - the rejected-but-registered outer face;
   - the figure-eight's partial face;
   - the order-dependent conflict check.

   Also record the degenerate-basis divergence and the two rulings above.
2. **Strip source narration.** Run the wide grep:

   ```bash
   grep -rniE "java|taprats|ported|reference tree|source's|extractFace|handleVertex|getTwin" lib/girihelix/engine/faces* lib/girihelix/engine/fill_region.ex lib/girihelix/engine/geometry/rect.ex
   ```

   Restate each hit as a decision.
3. **Update the documents.**
   - Set the spec's status to implemented.
   - Mark Plan 1 complete in the workbench spec's plan-series note.
4. **Lint, then run the gates.** Run `markdownlint-cli2` and `mix precommit`.
5. **Commit.** Commit message:
   `docs: record the faces and fill flaws, and complete Plan 1`.

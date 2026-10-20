# Planar map and Taprats reference harness implementation plan (Plan 1b)

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port Taprats' planar map — vertices, edges, angle-ordered neighbour
rings, insertion with edge splitting, rigid motions, `replicate` and `weld` — as
an immutable, handle-based `PlanarMap`. Verify it against the real Taprats
1.1.12, run locally through a reference harness.

**Architecture:**

- **The opaque struct:** `Girihelix.Engine.PlanarMap` is the only module that
  builds or reads the `%PlanarMap{}` struct. It holds vertices and edges by
  integer handle, the two Taprats orders as handle lists, and each vertex's
  neighbour ring as a list starting at its head.
- **The algorithm helpers:** the geometric decisions live in submodules that
  work on plain lists and points, never on the struct. These are `Order`,
  `Ring`, `Split` and `Weld`.
- **The step sequences:** `weld/2` and `replicate/3` are step sequences, run
  through `Girihelix.Engine.Steps`.
- **The harness:**
  - **The Java half:** a Java driver interprets an operation script against
    Taprats and writes a dump.
  - **The Elixir half:** a test-support module interprets the same script
    against `PlanarMap` and compares the two dumps.

**Tech Stack:** Elixir 1.20.3, ExUnit, dialyxir; Java 21 (installed) for the
harness only. No new Hex dependencies.

**Spec:** `docs/superpowers/specs/2026-10-20-girihelix-planar-map-design.md`.
Read it in full before Task 1. The algorithms are specified exactly in the
local, git-ignored porting notes, `reference/porting-notes/geometry.md`:

- §3, `Vertex`: the neighbour ring, `pseudoAtan2`, ring insertion and removal,
  `getBeforeAndAfter`
- §4, `Edge`
- §5, `Map`: the orders, the comparators, splitting, rigid motions,
  `mergeMap`, `mergeVertices`, `mergeSimpleMany` and `verify`

Each task names the subsections it implements. The Java itself is in
`reference/1.1.12/src/geometry/`.

## Global Constraints

- **Faithful first.** Reproduce Taprats' behaviour, flaws included, and record
  each flaw. Never "fix" one in this plan.
- **Handles, not values.**
  - A vertex or an edge is a `non_neg_integer()` handle.
  - Handles are never reused within a map.
  - Callers never hold vertex or edge state.
- **Errors and bang twins.**
  - Every public function that takes a handle returns `{:ok, …}`, or
    `{:error, :unknown_vertex | :unknown_edge}`.
  - Each such function has a `name!` twin that raises `ArgumentError`, with
    the reason atom in the message.
  - Functions taking only points, transforms or maps return bare values.
- **Only `lib/girihelix/engine/planar_map.ex` may build, match or update
  `%PlanarMap{}`.** Submodules under `lib/girihelix/engine/planar_map/` take
  plain data: lists, `Point`s and floats.
- **Reason atoms, exactly:** `:unknown_vertex`, `:unknown_edge`, `:crosses`.
  The `verify/1` problems are tagged tuples, listed in Task 9.
- **Taprats tolerances, verbatim.**
  - The comparators use `Loose.zero/1`, which is `|d| < 1e-7`.
  - Point identity is a *square* window: `|dx| < 1e-7`, then `|dy| < 1e-7`.
  - Ring angles use `pseudoAtan2` on the **normalized** direction vector.
- **Stable sorting, the Elixir way:**
  `Enum.sort(list, fn a, b -> compare(a, b) != :gt end)`.
  - That is stable, because the function returns `true` for equal elements.
  - Do not port Java's sort unless the Task 6 probe proves it is needed.
- **Engine purity, the hard rules and dialyzer.**
  - Engine purity: the standard library only.
  - The hard rules in `AGENTS.md`: no `if` or `cond` in engine code; branch in
    function heads and guards.
  - `mix dialyzer` reports `Total errors: 0` before every commit.
- **No module over 800 lines.** `GIRI001` enforces this, and it fires.
- **A `Segment` from computed points goes through `Segment.new/2`.**
  `{:error, :coincident_points}` takes the same path as a `nil` crossing.
- **The harness stays local.** Everything under `reference/oracle/` is
  git-ignored. Never `git add -f` anything under `reference/`.
- **Git and Markdown.**
  - `git commit` is its own command, with no bare `-n` token.
  - Commits are signed through 1Password. If signing fails with a 1Password
    error, ask the user to unlock it, and never disable signing.
  - Markdown is linted with `markdownlint-cli2 --config ~/.markdownlint-cli2.jsonc`.
- **Never start or stop the dev server on :4000.**

## Rulings against the design

These were made while planning, and the spec is updated in Task 10:

1. **`replicate` takes three arguments:** `replicate(receiver, unit, transforms)`.
   The design's "`replicate/2`" counted only Taprats' parameters, not the
   receiver.
2. **`verify/1` is a test aid, not ported behaviour.** Every Taprats call to
   `verify()` is commented out except one debug `main` (porting notes §5.11). Its
   `NullPointerException` on a missing ring entry is not reproduced: the Elixir
   version reports a problem instead. Golden comparison of `verify` is made only
   where Taprats reports `true`.
3. **Three more flaws join the design's list of five.** All are reproduced and
   recorded:
   - **8 — `transform/2` reangles against partly-moved neighbours.** It visits
     vertices in order, moving each and then recomputing its ring angles against
     neighbours that may not have moved yet. Ring order is unaffected, but later
     insertions land where Taprats puts them, not where the true angles would
     (§5.7, §3.3).
   - **6 — flips leave rings reversed.** `scale/2` with a negative factor, or
     `transform/2` with a flipping transform, leaves every neighbour ring in its
     old rotational order (porting notes §3.3, §5.7).
   - **7 — `replicate/3` never splits.** It finds or creates vertices without
     splitting edges. Two unit vertices landing on one receiver vertex make a
     self-edge (§5.10).

## Review Focus

These are inputs the spec implies but no ordinary test exercises. Each has its
test in the owning task.

1. **A stale handle.** After `remove_vertex!/2`, every function given that
   vertex returns `{:error, :unknown_vertex}`, and its bang twin raises. Owner:
   Task 6.
2. **Welding a map to itself.** `weld(m, m)` reproduces Taprats: no crossings,
   every vertex unified, and every edge doubled. `verify/1` then reports parallel
   edges. It must not crash. Owners: Tasks 8 and 9.
3. **Empty maps.** None of these may crash, and each must match Taprats:
   - `weld/2` with either side empty
   - `replicate/3` with no transforms, or with an empty unit
   - `transform/2` of an empty map
   - removing the last vertex

   Owners: Tasks 6, 7 and 8.
4. **A self-edge through the unchecked insert.** `insert_edge!(m, v, v)` adds
   the edge twice to `v`'s ring at angle `0.5`, as Taprats does. `verify/1`
   reports `{:trivial_edge, e}`. Owners: Tasks 4 and 9.
5. **A flip.** After `scale(m, -1.0)`, every ring keeps its old order, matching
   Taprats (flaw 6). Owner: Task 6.

## The operation script and dump formats

Both halves of the harness depend on these, so they are fixed here.

**Script** (`reference/oracle/scenarios/<name>.ops`): one operation per line.
`#` starts a comment, and blank lines are ignored. A map is created empty the
first time its name is used.

```text
<map> vertex <x> <y>            # insert_vertex; result gets the next per-map index 0, 1, 2…
<map> edge <i> <j>              # insert_edge between the results of vertex ops i and j
<map> remove <i>                # remove_vertex on the result of vertex op i
<map> transform <T>
<map> scale <r>
<map> translate <x> <y>
<map> replicate <other> <T> ; <T> ; …
<map> weld <other>
dump <map>                      # exactly once, last line
```

`<T>` is one of:

- `m a b c d e f` — `Transform.new(a, b, c, d, e, f)`, the same layout on both
  sides
- `rot <radians>`
- `tr <x> <y>`
- `sc <r>`

Numbers are decimal literals. Java's `Double.parseDouble` and Elixir's
`Float.parse/1` round them identically.

**Dump** (`reference/oracle/fixtures/<name>.dump`), produced by both halves:

```text
vertices <n>
v <x> <y>                       # each vertex, in Taprats vertex order
edges <m>
e <i> <j>                       # each edge, in Taprats edge order: v1 and v2 as vertex-order indices
rings
r <i> <k1> <k2> …               # one line per vertex in order; edge-order indices from the ring head
verify <true|false|npe>
```

Java writes coordinates with `Double.toString`. The comparison is:

- **Exact:** counts, edges, rings and the `verify` word, except as ruling 2
  says.
- **To `1e-12` per component:** coordinates.

---

### Task 1: The reference harness, Java half (local, not committed)

**Files** (all under the git-ignored `reference/oracle/`):

- Create: `reference/oracle/build` (executable)
- Create: `reference/oracle/run` (executable)
- Create: `reference/oracle/src/csk/taprats/geometry/HarnessDriver.java`
- Create: `reference/oracle/scenarios/basic-edge.ops`

**Interfaces:**

- Consumes: Taprats 1.1.12 in `reference/1.1.12/src/`.
- Produces:
  - `reference/oracle/run` regenerates `reference/oracle/fixtures/<name>.dump`
    for every `scenarios/<name>.ops`, in the dump format above.
  - Later tasks add scenarios and rerun it.

- [ ] **Step 1: Write `build`**

  `build` compiles Taprats and the driver into `reference/oracle/classes/`:

  ```bash
  javac -encoding utf8 -nowarn -d "$ORACLE/classes" \
    $(find "$TAPRATS/src" -name '*.java' | grep -v /plugins/) \
    "$ORACLE/src/csk/taprats/geometry/HarnessDriver.java"
  ```

  It resolves `$ORACLE` and `$TAPRATS` from its own location, so it runs from
  any directory. Measured on 2026-10-20: Taprats compiles cleanly with Java 21,
  and needs no Batik.

- [ ] **Step 2: Write `HarnessDriver`**

  `HarnessDriver` lives in package `csk.taprats.geometry` and takes two
  arguments, `HarnessDriver <script.ops> <out.dump>`.

  - **Interpreting the script.** Ops follow the script format.
    - Keep one `Map` per name, and one `List<Vertex>` per name holding the
      results of that map's `vertex` ops.
    - `vertex` calls `insertVertex(new Point(x, y))`.
    - `edge` calls `insertEdge`.
    - `remove` calls `removeVertex`.
    - `transform` calls `transformMap`.
    - `scale` and `translate` call the methods of the same name.
    - `replicate` calls `mergeSimpleMany(other, transforms)`.
    - `weld` calls `mergeMap(other)`.
    - Build `rot`, `tr` and `sc` with `Transform.rotate`, `Transform.translate`
      and `Transform.scale`.
  - **Writing the dump.**
    - Number the vertices with an `IdentityHashMap<Vertex, Integer>` in
      `getVertices()` order, and the edges likewise in `getEdges()` order.
    - Ring lines walk `vertex.neighbours()`, which starts at the head.
    - Write each coordinate with `Double.toString`.
    - For the `verify` line, call `verify()` with `System.err` redirected to a
      throwaway stream. Write `true` or `false`, or `npe` if it throws
      `NullPointerException`.

- [ ] **Step 3: Write `run`**

  `run` calls `build` if `classes/` is missing, then runs every scenario:

  ```bash
  java -Djava.awt.headless=true -cp "$ORACLE/classes" csk.taprats.geometry.HarnessDriver \
    "$s" "$ORACLE/fixtures/$(basename "$s" .ops).dump"
  ```

  It prints one line per scenario.

- [ ] **Step 4: Write the first scenario,** `basic-edge.ops`:

  ```text
  A vertex 0.0 0.0
  A vertex 2.0 1.0
  A edge 0 1
  dump A
  ```

- [ ] **Step 5: Run it, and check the dump by hand**

  Run: `reference/oracle/run`

  Expected: `reference/oracle/fixtures/basic-edge.dump` contains exactly:

  ```text
  vertices 2
  v 0.0 0.0
  v 2.0 1.0
  edges 1
  e 0 1
  rings
  r 0 0
  r 1 0
  verify true
  ```

- [ ] **Step 6: Confirm nothing is tracked**

  Run: `git status --short reference/`

  Expected: no output. The whole harness is git-ignored. There is nothing to
  commit in this task.

### Task 2: The reference harness, Elixir half (parsing, comparison, opt-in tag)

**Files:**

- Create: `test/support/taprats_harness.ex`
- Create: `test/girihelix/taprats_harness_test.exs`
- Create: `test/girihelix/engine/planar_map_golden_test.exs`
- Modify: `test/test_helper.exs`

**Interfaces:**

- Consumes: the formats above.
- Produces, in `Girihelix.TapratsHarness`:
  - `@type dump :: %{vertices: [{float(), float()}], edges: [{non_neg_integer(), non_neg_integer()}], rings: [[non_neg_integer()]], verify: true | false | :npe | :unchecked}`
  - `@type op :: tuple()`, with one tuple per script line, for example
    `{:vertex, "A", 0.0, 0.0}`, `{:edge, "A", 0, 1}` and
    `{:replicate, "A", "B", [Transform.t()]}`. Transforms are built at parse
    time.
  - `parse_script(String.t()) :: [op]`
  - `parse_dump(String.t()) :: dump`
  - `compare(expected :: dump, actual :: dump) :: :ok | {:error, [String.t()]}`.
    It checks counts, edges and rings exactly, and coordinates to `1e-12`. It
    skips the `verify` word when `actual.verify == :unchecked`, or when
    `expected.verify != true`.
  - `fixtures_dir() :: String.t()`, which is `"reference/oracle/fixtures"`.
  - `available?() :: boolean()`
  - `load(name :: String.t()) :: {[op], dump}`, which reads the matching
    `scenarios/<name>.ops` and `fixtures/<name>.dump`.
  - `run_script/1` and `dump/1` are added in Task 4.

- [ ] **Step 1: Write the failing tests** in `taprats_harness_test.exs`. They use
  inline strings, not fixtures, so they run everywhere.

```elixir
test "parse_script/1 reads every operation and ignores comments" do
  ops =
    TapratsHarness.parse_script("""
    # a comment
    A vertex 0.0 -1.5
    A edge 0 1
    A replicate B rot 1.0 ; tr 2.0 0.0
    dump A
    """)

  assert [{:vertex, "A", 0.0, -1.5}, {:edge, "A", 0, 1}, {:replicate, "A", "B", [rot, tr]}, {:dump, "A"}] = ops
  assert rot == Transform.rotate(1.0)
  assert tr == Transform.translate(2.0, 0.0)
end

test "parse_dump/1 reads Java's float spelling" do
  dump =
    TapratsHarness.parse_dump("""
    vertices 1
    v -1.0 2.7755575615628914E-16
    edges 0
    rings
    r 0
    verify true
    """)

  assert dump == %{vertices: [{-1.0, 2.7755575615628914e-16}], edges: [], rings: [[]], verify: true}
end

test "compare/2 accepts coordinates within 1e-12 and nothing looser" do
  base = %{vertices: [{1.0, 0.0}], edges: [], rings: [[]], verify: true}

  assert TapratsHarness.compare(base, %{base | vertices: [{1.0 + 5.0e-13, 0.0}]}) == :ok
  assert {:error, [_]} = TapratsHarness.compare(base, %{base | vertices: [{1.0 + 5.0e-12, 0.0}]})
end

test "compare/2 is exact on structure" do
  base = %{vertices: [{0.0, 0.0}, {1.0, 0.0}], edges: [{0, 1}], rings: [[0], [0]], verify: true}

  assert {:error, _} = TapratsHarness.compare(base, %{base | edges: [{1, 0}]})
  assert {:error, _} = TapratsHarness.compare(base, %{base | rings: [[0], []]})
  assert TapratsHarness.compare(base, %{base | verify: :unchecked}) == :ok
end
```

- [ ] **Step 2: Run the tests to verify they fail**

  Run: `mix test test/girihelix/taprats_harness_test.exs`

  Expected: FAIL, with `TapratsHarness` undefined.

- [ ] **Step 3: Implement `test/support/taprats_harness.ex`**

  - **Parsing:** one line at a time. Split each line on whitespace, and split a
    `replicate` line's transforms on `;`. Parse numbers with `Float.parse/1`,
    accepting integer-looking literals like `2` as `2.0`.
  - **Errors:** a malformed line raises `ArgumentError` naming the line.
    Malformed harness input is a bug in a local test file, not caller-supplied
    data. Say so in the moduledoc.
  - **Moduledoc:** it must also say that the harness, its scenarios and its
    fixtures are local-only, and point at the spec.

- [ ] **Step 4: Opt the golden tests in only where fixtures exist**

  In `test/test_helper.exs`, before `ExUnit.start()`:

  ```elixir
  # Golden tests compare against fixtures produced by the local-only Taprats
  # reference harness (reference/oracle/). Without them, those tests are skipped.
  ExUnit.configure(exclude: Enum.reject([:taprats], fn _ -> File.dir?("reference/oracle/fixtures") end))
  ```

- [ ] **Step 5: Create the golden test module.** It starts with no scenarios.

  `planar_map_golden_test.exs` carries `@moduletag :taprats`, and an
  `@scenarios []` list that later tasks append to. For each name it generates:

  ```elixir
  test "matches Taprats: #{name}" do
    {ops, expected} = TapratsHarness.load(unquote(name))
    assert TapratsHarness.compare(expected, TapratsHarness.run_script(ops)) == :ok
  end
  ```

  With `@scenarios []` the loop generates nothing, so the module compiles
  before `run_script/1` exists.

- [ ] **Step 6: Run the tests to verify they pass**

  Run: `mix test test/girihelix/taprats_harness_test.exs test/girihelix/engine/planar_map_golden_test.exs`

  Expected: PASS, with 4 tests and the golden module contributing none.

- [ ] **Step 7: Gates**

  Run: `mix precommit.fast && mix dialyzer`

  Expected: both pass, with `Total errors: 0`.

- [ ] **Step 8: Commit**

  ```bash
  git add test/support/taprats_harness.ex test/girihelix/taprats_harness_test.exs test/girihelix/engine/planar_map_golden_test.exs test/test_helper.exs
  ```

  ```bash
  git commit -m "test: add the Taprats reference harness, Elixir half"
  ```

### Task 3: `Order` and `Ring`, the pure helpers

**Files:**

- Create: `lib/girihelix/engine/planar_map/order.ex`
- Create: `lib/girihelix/engine/planar_map/ring.ex`
- Create: `test/girihelix/engine/planar_map/order_test.exs`
- Create: `test/girihelix/engine/planar_map/ring_test.exs`

**Interfaces:**

- Consumes: `Point`, and `Loose.zero/1`, which is `|d| < 1e-7`.
- Produces, in `Girihelix.Engine.PlanarMap.Order`. These implement porting
  notes §5.1, §5.5 `getVertex_Simple` and §5.6 `insertEdge_Simple`:
  - `@type comparison :: :lt | :eq | :gt`
  - `compare_points(Point.t(), Point.t()) :: comparison` (`lexComparePoints`)
  - `compare_min_x(float(), float()) :: comparison` (`lexCompareEdges`)
  - `find_or_insert([{term(), Point.t()}], Point.t()) :: {:found, term()} | {:insert_at, non_neg_integer()}`
    walks the sorted vertices. It returns the first entry comparing `:eq`, or
    the index of the first comparing `:lt`, or the list's length.
  - `edge_insert_index([float()], float()) :: non_neg_integer()` returns the
    first index whose key the new key compares `:lt` against, or the list's
    length.
  - `sort([a], (a -> key), (key, key -> comparison)) :: [a]` is stable.
- Produces, in `Girihelix.Engine.PlanarMap.Ring`. A ring is
  `[{edge :: term(), angle :: float()}]`, starting at its head. These implement
  §3.1 and §3.3:
  - `pseudo_atan2(float(), float()) :: float()`, with Taprats' four branches
    exactly
  - `angle(from :: Point.t(), to :: Point.t()) :: float()`:
    `pseudo_atan2` of `Point.normalize(Point.subtract(to, from))`
  - `insert(ring, {edge, angle}) :: ring`
  - `remove(ring, edge) :: ring`
  - `swap(ring, old_edge, new_edge) :: ring`
  - `before_and_after(ring, edge) :: {edge, edge} | nil`
  - `edges(ring) :: [edge]`
  - `reangle(ring, (edge -> float())) :: ring` keeps the order and replaces
    every angle.

- [ ] **Step 1: Write the failing tests**

```elixir
# order_test.exs
test "compare_points/2 is lexicographic with a 1e-7 window per component" do
  assert Order.compare_points(Point.new(0.0, 5.0), Point.new(1.0, 0.0)) == :lt
  assert Order.compare_points(Point.new(0.0, 0.0), Point.new(5.0e-8, 5.0e-8)) == :eq
  assert Order.compare_points(Point.new(0.0, 0.0), Point.new(5.0e-8, 1.0)) == :lt
end

# Flaw 1, pinned: the window makes the comparator non-transitive.
test "compare_min_x/2 is not transitive" do
  assert Order.compare_min_x(0.0, 6.0e-8) == :eq
  assert Order.compare_min_x(6.0e-8, 1.2e-7) == :eq
  assert Order.compare_min_x(0.0, 1.2e-7) == :lt
end

test "find_or_insert/2 reuses a coincident vertex or names the slot" do
  sorted = [{:a, Point.new(0.0, 0.0)}, {:b, Point.new(1.0, 0.0)}]

  assert Order.find_or_insert(sorted, Point.new(1.0, 5.0e-8)) == {:found, :b}
  assert Order.find_or_insert(sorted, Point.new(0.5, 0.0)) == {:insert_at, 1}
  assert Order.find_or_insert(sorted, Point.new(2.0, 0.0)) == {:insert_at, 2}
end

test "edge_insert_index/2 goes after every key it does not compare below" do
  assert Order.edge_insert_index([0.0, 1.0, 1.0, 2.0], 1.0) == 3
  assert Order.edge_insert_index([0.0, 1.0], -1.0) == 0
end

test "sort/3 is stable on equal keys" do
  assert Order.sort([{:x, 1.0}, {:y, 0.0}, {:z, 1.0 + 1.0e-9}], &elem(&1, 1), &Order.compare_min_x/2) ==
           [{:y, 0.0}, {:x, 1.0}, {:z, 1.0 + 1.0e-9}]
end

# ring_test.exs
test "pseudo_atan2/2 is monotone in the counter-clockwise angle, on [0, 1)" do
  assert Ring.pseudo_atan2(1.0, 0.0) == 0.0
  assert Ring.pseudo_atan2(0.0, 1.0) == 0.25
  assert Ring.pseudo_atan2(-1.0, 0.0) == 0.5
  assert Ring.pseudo_atan2(0.0, -1.0) == 0.75
  assert Ring.pseudo_atan2(0.0, 0.0) == 0.5
end

test "insert/2 keeps the head and places by angle, wrapping past 1.0" do
  ring = [{:e0, 0.1}] |> Ring.insert({:e1, 0.6}) |> Ring.insert({:e2, 0.3}) |> Ring.insert({:e3, 0.9})
  assert Ring.edges(ring) == [:e0, :e2, :e1, :e3]
  assert ring |> Ring.insert({:e4, 0.05}) |> Ring.edges() == [:e0, :e2, :e1, :e3, :e4]
end

# Flaw 5, pinned: an equal angle goes straight after the first equal entry met.
test "insert/2 puts an equal angle after the first entry it equals" do
  assert [{:a, 0.25}, {:b, 0.5}] |> Ring.insert({:c, 0.25}) |> Ring.edges() == [:a, :c, :b]
end

test "remove/2 makes the removed edge's predecessor the head" do
  ring = [{:a, 0.1}, {:b, 0.2}, {:c, 0.3}]
  assert ring |> Ring.remove(:b) |> Ring.edges() == [:a, :c]
  assert ring |> Ring.remove(:c) |> Ring.edges() == [:b, :a]
  assert ring |> Ring.remove(:a) |> Ring.edges() == [:c, :b]
  assert Ring.remove(ring, :missing) == ring
end

test "before_and_after/2 matches Taprats on degree one and two" do
  assert Ring.before_and_after([{:a, 0.1}], :a) == {:a, :a}
  assert Ring.before_and_after([{:a, 0.1}, {:b, 0.6}], :a) == {:b, :b}
  assert Ring.before_and_after([{:a, 0.1}, {:b, 0.4}, {:c, 0.7}], :b) == {:a, :c}
  assert Ring.before_and_after([{:a, 0.1}], :missing) == nil
end

test "swap/3 renames an entry in place and keeps its angle" do
  assert Ring.swap([{:a, 0.1}, {:b, 0.4}], :b, :z) == [{:a, 0.1}, {:z, 0.4}]
end
```

- [ ] **Step 2: Run the tests to verify they fail**

  Run: `mix test test/girihelix/engine/planar_map/`

  Expected: FAIL, with `Order` and `Ring` undefined.

- [ ] **Step 3: Implement both modules**

  - **`Ring.insert/2`** walks consecutive pairs `(cur, next)` from the head,
    finishing with the pair (last, head). It inserts straight after `cur` at the
    first pair where:
    - `next > cur` and `cur <= a <= next`, or
    - `next <= cur` and (`cur <= a` or `a <= next`).

    Inserting after the last element appends to the list. An empty ring becomes
    `[{edge, a}]`. If no slot is found, raise `ArgumentError`: that is an
    invariant violation, unreachable for finite angles, and it is Taprats'
    `InternalError`.
  - **`Ring.remove/2`:**
    - Delete the edge.
    - Rotate the list so the deleted edge's cyclic predecessor is first.
    - Removing the only entry gives `[]`.
    - Return an absent edge's ring unchanged.
  - **`Order.sort/3`** follows the constraint's `Enum.sort` form.
  - **Hard rules:** branch with clauses and guards. For example, `pseudo_atan2`
    is four guarded clauses, and the comparisons are private clauses on the
    difference.
  - **Moduledocs** state these are plain-data helpers for `PlanarMap`, with no
    knowledge of the struct. Name the faithful flaws they carry: 1 and 5.

- [ ] **Step 4: Run the tests to verify they pass**

  Run: `mix test test/girihelix/engine/planar_map/`

  Expected: PASS.

- [ ] **Step 5: Gates**

  Run: `mix precommit.fast && mix dialyzer`

  Expected: both pass, with `Total errors: 0`.

- [ ] **Step 6: Commit**

  ```bash
  git add lib/girihelix/engine/planar_map test/girihelix/engine/planar_map
  ```

  ```bash
  git commit -m "feat: add the planar map's ordering and ring helpers"
  ```

### Task 4: `PlanarMap` core — the struct, vertex and edge insertion, and queries

**Files:**

- Create: `lib/girihelix/engine/planar_map.ex`
- Create: `test/girihelix/engine/planar_map_test.exs`
- Modify: `test/support/taprats_harness.ex` (adds `run_script/1`, `dump/1`)
- Modify: `test/girihelix/engine/planar_map_golden_test.exs` (adds scenarios)
- Create (local): `reference/oracle/scenarios/{coincident-vertices,hub-ring,duplicate-angle,self-edge}.ops`

**Interfaces:**

- Consumes: `Order` and `Ring` (Task 3), `Point`, `Transform`.
- Produces, in `Girihelix.Engine.PlanarMap`:
  - **Types:**
    - `@opaque t`, with fields `vertices: %{vertex() => %{pos: Point.t(), ring: [{edge(), float()}]}}`,
      `edges: %{edge() => {vertex(), vertex()}}`, `vertex_order: [vertex()]`,
      `edge_order: [edge()]` and `next: non_neg_integer()`. Vertices and edges
      draw handles from the one shared counter `next`.
    - `@type vertex :: non_neg_integer()`
    - `@type edge :: non_neg_integer()`
  - **Construction and insertion:**
    - `new() :: t()`
    - `insert_vertex(t(), Point.t()) :: {t(), vertex()}`. In this task it only
      finds or creates; Task 5 adds splitting.
    - `insert_edge(t(), vertex(), vertex()) :: {:ok, t()} | {:error, :unknown_vertex}`
    - `insert_edge!(t(), vertex(), vertex()) :: t()`
  - **Queries:**
    - `num_vertices(t()) :: non_neg_integer()`
    - `num_edges(t()) :: non_neg_integer()`
    - `vertices(t()) :: [vertex()]`, in Taprats order
    - `edges(t()) :: [edge()]`, in Taprats order
    - `position(t(), vertex()) :: {:ok, Point.t()} | {:error, :unknown_vertex}`,
      and `position!/2`
    - `endpoints(t(), edge()) :: {:ok, {vertex(), vertex()}} | {:error, :unknown_edge}`,
      and `endpoints!/2`
    - `ring(t(), vertex()) :: {:ok, [edge()]} | {:error, :unknown_vertex}`, and
      `ring!/2`. It starts from the head.
    - `neighbour(t(), vertex(), vertex()) :: {:ok, edge() | nil} | {:error, :unknown_vertex}`,
      and `neighbour!/3`. This returns the first edge in the ring, from the
      head, whose far end is the second vertex (§3.3 `findNeighbour`).
    - `before_and_after(t(), vertex(), edge()) :: {:ok, {edge(), edge()} | nil} | {:error, :unknown_vertex | :unknown_edge}`,
      and `before_and_after!/3`
  - **In `TapratsHarness`:**
    - `run_script([op]) :: dump` interprets `vertex` and `edge` ops now. Each
      later task adds its ops.
    - `dump(PlanarMap.t()) :: dump`, with `verify: :unchecked` until Task 9.

- [ ] **Step 1: Write the failing unit tests** in `planar_map_test.exs`:

```elixir
test "insert_vertex/2 reuses a vertex inside the 1e-7 square window" do
  {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(1.0, 1.0))
  {map, b} = PlanarMap.insert_vertex(map, Point.new(1.0 + 5.0e-8, 1.0 - 5.0e-8))

  assert a == b
  assert PlanarMap.num_vertices(map) == 1
end

test "vertices are kept in Taprats order, lexicographic by position" do
  {map, _} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(2.0, 0.0))
  {map, _} = PlanarMap.insert_vertex(map, Point.new(0.0, 5.0))
  {map, _} = PlanarMap.insert_vertex(map, Point.new(0.0, -1.0))

  assert Enum.map(PlanarMap.vertices(map), &PlanarMap.position!(map, &1)) ==
           [Point.new(0.0, -1.0), Point.new(0.0, 5.0), Point.new(2.0, 0.0)]
end

test "insert_edge/3 registers the edge in both rings and reports unknown handles" do
  {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
  {map, b} = PlanarMap.insert_vertex(map, Point.new(1.0, 0.0))
  map = PlanarMap.insert_edge!(map, a, b)
  [e] = PlanarMap.edges(map)

  assert PlanarMap.endpoints!(map, e) == {a, b}
  assert PlanarMap.ring!(map, a) == [e]
  assert PlanarMap.neighbour!(map, b, a) == e
  assert PlanarMap.neighbour!(map, a, a) == nil
  assert PlanarMap.insert_edge(map, a, 999) == {:error, :unknown_vertex}
  assert PlanarMap.endpoints(map, 999) == {:error, :unknown_edge}
  assert_raise ArgumentError, ~r/unknown_vertex/, fn -> PlanarMap.insert_edge!(map, 999, a) end
end

# Review Focus 4: the unchecked insert accepts a self-edge, as Taprats does.
test "insert_edge!/3 from a vertex to itself puts the edge in its ring twice" do
  {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(1.0, 1.0))
  map = PlanarMap.insert_edge!(map, a, a)
  [e] = PlanarMap.edges(map)

  assert PlanarMap.ring!(map, a) == [e, e]
end

test "before_and_after/3 reports the ring window, or nil for a stranger edge" do
  {map, hub} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
  {map, east} = PlanarMap.insert_vertex(map, Point.new(1.0, 0.0))
  {map, north} = PlanarMap.insert_vertex(map, Point.new(0.0, 1.0))
  map = map |> PlanarMap.insert_edge!(hub, east) |> PlanarMap.insert_edge!(hub, north)
  e_east = PlanarMap.neighbour!(map, hub, east)
  e_north = PlanarMap.neighbour!(map, hub, north)

  assert PlanarMap.before_and_after!(map, hub, e_east) == {e_north, e_north}
  assert PlanarMap.before_and_after!(map, east, e_north) == nil
end
```

- [ ] **Step 2: Write the golden scenarios, then regenerate the fixtures**

  Each new `.ops` file goes in `reference/oracle/scenarios/` and ends `dump A`:

  - **`coincident-vertices`:** vertices at `(0, 0)`, `(5e-8, 5e-8)`,
    `(9e-8, 0)`, `(2e-7, 0)` and `(1, 1)`, with edges from the first and fourth
    to the fifth.
  - **`hub-ring`:** a hub at the origin and six spokes at unit length. Insert
    the spokes and the edges in a scrambled angular order, with the first
    spoke's edge pointing west, so the head is not the smallest angle.
  - **`duplicate-angle`:** a hub at `(0, 0)`, vertices at `(1, 0)` and `(2, 0)`,
    and edges hub–`(1, 0)` then hub–`(2, 0)`.
  - **`self-edge`:** `A vertex 1.0 1.0`, `A edge 0 0`, and a second vertex with
    an edge to the first.

  Run: `reference/oracle/run`

  Expected: four new dumps under `reference/oracle/fixtures/`.

  Append `basic-edge`, `coincident-vertices`, `hub-ring`, `duplicate-angle` and
  `self-edge` to `@scenarios` in the golden test.

- [ ] **Step 3: Run the tests to verify they fail**

  Run: `mix test test/girihelix/engine/planar_map_test.exs test/girihelix/engine/planar_map_golden_test.exs`

  Expected: FAIL, with `PlanarMap` undefined.

- [ ] **Step 4: Implement `planar_map.ex`, and the harness's `run_script/1` and `dump/1`**

  - **`insert_vertex/2`** passes `vertex_order` zipped with positions to
    `Order.find_or_insert/2`. A new vertex takes `next`, has an empty ring, and
    is inserted at the returned index.
  - **`insert_edge/3`** follows §5.6:
    - Take a new handle.
    - Insert it into `edge_order` at `Order.edge_insert_index/2`, over the
      current edges' minimum x values.
    - Insert `{e, Ring.angle(p1, p2)}` into `v1`'s ring, then
      `{e, Ring.angle(p2, p1)}` into `v2`'s ring.
    - An edge's minimum x is `min(x1, x2)`, computed from current positions.
  - **Handle lookups** are private functions returning `{:ok, …}` or
    `{:error, …}`. Each bang twin matches the tuple and raises `ArgumentError`
    with the reason, as `Segment.new!/2` does.
  - **The moduledoc** states:
    - the handle model
    - the opaque invariant, with no-crossing as a caller precondition
    - that only this module touches the struct
    - the flaw list, linking the analysis document

- [ ] **Step 5: Run the tests to verify they pass**

  Run: `mix test test/girihelix/engine/planar_map_test.exs test/girihelix/engine/planar_map_golden_test.exs`

  Expected: PASS, with all five golden scenarios matching Taprats.

- [ ] **Step 6: Gates**

  Run: `mix precommit.fast && mix dialyzer`

  Expected: both pass, with `Total errors: 0`.

- [ ] **Step 7: Commit**

  ```bash
  git add lib/girihelix/engine/planar_map.ex test/girihelix/engine/planar_map_test.exs test/girihelix/engine/planar_map_golden_test.exs test/support/taprats_harness.ex
  ```

  ```bash
  git commit -m "feat: add PlanarMap with vertex and edge insertion"
  ```

### Task 5: Splitting an edge when a vertex lands on it

**Files:**

- Create: `lib/girihelix/engine/planar_map/split.ex`
- Create: `test/girihelix/engine/planar_map/split_test.exs`
- Modify: `lib/girihelix/engine/planar_map.ex`
- Modify: `test/girihelix/engine/planar_map_golden_test.exs`
- Create (local): `reference/oracle/scenarios/{split-on-edge,split-two-edges,split-repeat,split-at-endpoint,split-keeps-ring}.ops`

**Interfaces:**

- Consumes: `Order.compare_min_x/2`, `Ring`, `Point.dist_to_line/3`,
  `Point.dist/2`, `Loose.zero/1`.
- Produces:
  - In `Girihelix.Engine.PlanarMap.Split`, implementing §5.5
    `splitEdgesByVertex`:
    - `splittable?(point :: Point.t(), a :: Point.t(), b :: Point.t()) :: boolean()`
      is true when `Loose.zero(Point.dist_to_line(point, a, b))`, and neither
      `Loose.zero(Point.dist(point, a))` nor `Loose.zero(Point.dist(point, b))`.
    - `first_splittable([{edge, Point.t(), Point.t()}], Point.t()) :: edge | nil`
      walks the edges in Taprats edge order. It stops at the first whose
      `min(a.x, b.x)` compares `:gt` against `point.x`, and returns the first
      splittable edge.
  - `PlanarMap.insert_vertex/2` now splits at most one edge (flaw 2).

- [ ] **Step 1: Write the failing tests**

```elixir
# split_test.exs
test "splittable?/3 needs the point on the segment and clear of both ends" do
  a = Point.new(0.0, 0.0)
  b = Point.new(2.0, 0.0)

  assert Split.splittable?(Point.new(1.0, 0.0), a, b)
  assert Split.splittable?(Point.new(1.5e-7, 0.0), a, b)
  refute Split.splittable?(Point.new(1.0, 2.0e-7), a, b)
  refute Split.splittable?(Point.new(3.0, 0.0), a, b)
  refute Split.splittable?(Point.new(5.0e-8, 0.0), a, b)
end

test "first_splittable/2 stops at the first edge starting beyond the point" do
  later = {:later, Point.new(4.0, 0.0), Point.new(6.0, 0.0)}
  hidden = {:hidden, Point.new(0.0, 0.0), Point.new(2.0, 0.0)}

  assert Split.first_splittable([hidden, later], Point.new(1.0, 0.0)) == :hidden
  # The edge order is what licenses stopping early, so an edge after the cut-off is never seen.
  assert Split.first_splittable([later, hidden], Point.new(1.0, 0.0)) == nil
end

# planar_map_test.exs
test "insert_vertex/2 splits the edge it lands on into two" do
  {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
  {map, b} = PlanarMap.insert_vertex(map, Point.new(2.0, 0.0))
  map = PlanarMap.insert_edge!(map, a, b)
  {map, mid} = PlanarMap.insert_vertex(map, Point.new(1.0, 0.0))

  assert PlanarMap.num_edges(map) == 2
  assert PlanarMap.neighbour!(map, mid, a) != nil
  assert PlanarMap.neighbour!(map, mid, b) != nil
  assert PlanarMap.neighbour!(map, a, b) == nil
end
```

- [ ] **Step 2: Write the golden scenarios, then regenerate the fixtures**

  - **`split-on-edge`:** an edge from `(0, 0)` to `(2, 0)`, then a vertex at
    `(1, 0)`.
  - **`split-two-edges`:** edges `(0, 0)`–`(2, 2)` and `(0, 2)`–`(2, 0)`, which
    deliberately cross, then a vertex at `(1, 1)`. Only one edge splits.
  - **`split-repeat`:** `split-on-edge`, then `(1, 0)` inserted twice more.
  - **`split-at-endpoint`:** an edge, then its own endpoint inserted again.
  - **`split-keeps-ring`:** a vertex at `(2, 0)` with three edges, west, north
    and south, then a vertex inserted on the west edge. It shows the swapped ring
    entry keeping its position and angle.

  Run: `reference/oracle/run`. Append the five names to `@scenarios`.

- [ ] **Step 3: Run the tests to verify they fail**

  Run: `mix test test/girihelix/engine/planar_map/split_test.exs test/girihelix/engine/planar_map_test.exs test/girihelix/engine/planar_map_golden_test.exs`

  Expected: FAIL. `Split` is undefined, and the new golden scenarios differ.

- [ ] **Step 4: Implement**

  - **Write `Split`**, with clauses and guards, and no `if`.
  - **The split itself** is a private function in `PlanarMap`. It follows the
    order in §5.5 exactly. Given the splittable edge `e = {v1, v2}` and the new
    vertex `vert`:
    1. Take a new handle `ne` for `{vert, v2}`.
    2. In `v2`'s ring, swap to `ne` the **first entry whose far end is `v1`**.
       That is `neighbour/3`'s lookup, not a lookup by `e`; the angle is
       unchanged.
    3. Set `e`'s endpoints to `{v1, vert}`.
    4. Delete `e` from `edge_order`. Insert `ne` at its index, then `e` at its
       new index, both by `Order.edge_insert_index/2`.
    5. Into `vert`'s ring, insert `e` (angle toward `v1`), then `ne` (angle
       toward `v2`).
  - **`insert_vertex/2`:** after find-or-create, pass `edge_order` with its
    endpoint positions to `Split.first_splittable/2`, and split if it returns an
    edge.

- [ ] **Step 5: Run the tests to verify they pass**

  Run: `mix test test/girihelix/engine/`

  Expected: PASS, including every earlier golden scenario.

- [ ] **Step 6: Gates**

  Run: `mix precommit.fast && mix dialyzer`

  Expected: both pass, with `Total errors: 0`.

- [ ] **Step 7: Commit**

  ```bash
  git add lib/girihelix/engine/planar_map.ex lib/girihelix/engine/planar_map/split.ex test/girihelix/engine/planar_map/split_test.exs test/girihelix/engine/planar_map_test.exs test/girihelix/engine/planar_map_golden_test.exs
  ```

  ```bash
  git commit -m "feat: split the edge a new vertex lands on"
  ```

### Task 6: Removing vertices, rigid motions, and the sort probe

**Files:**

- Modify: `lib/girihelix/engine/planar_map.ex`
- Modify: `test/girihelix/engine/planar_map_test.exs`
- Modify: `test/support/taprats_harness.ex` (adds the `remove`, `transform`,
  `scale` and `translate` ops)
- Modify: `test/girihelix/engine/planar_map_golden_test.exs`
- Create (local): `reference/oracle/scenarios/{remove-hub,remove-moves-head,remove-last,transform-rotate,transform-then-insert,transform-empty,scale-translate,scale-negative,sort-probe}.ops`

**Interfaces:**

- Produces, in `PlanarMap`:
  - `remove_vertex(t(), vertex()) :: {:ok, t()} | {:error, :unknown_vertex}`,
    and `remove_vertex!/2`
  - `transform(t(), Transform.t()) :: t()`
  - `scale(t(), number()) :: t()`
  - `translate(t(), number(), number()) :: t()`

- [ ] **Step 1: Write the failing unit tests**

```elixir
# Review Focus 1: a removed vertex's handle is unknown everywhere.
test "a removed vertex's handle is unknown everywhere" do
  {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
  {map, b} = PlanarMap.insert_vertex(map, Point.new(1.0, 0.0))
  map = map |> PlanarMap.insert_edge!(a, b) |> PlanarMap.remove_vertex!(a)

  assert PlanarMap.position(map, a) == {:error, :unknown_vertex}
  assert PlanarMap.insert_edge(map, a, b) == {:error, :unknown_vertex}
  assert PlanarMap.remove_vertex(map, a) == {:error, :unknown_vertex}
  assert_raise ArgumentError, ~r/unknown_vertex/, fn -> PlanarMap.ring!(map, a) end
  assert PlanarMap.ring!(map, b) == []
  assert PlanarMap.num_edges(map) == 0
end

# Review Focus 5 (flaw 6): a flip is not detected, so rings keep their old order.
test "scale/2 by a negative factor moves points but keeps every ring's order" do
  {map, hub} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))

  map =
    Enum.reduce([{1.0, 0.0}, {0.0, 1.0}, {-1.0, -1.0}], map, fn {x, y}, map ->
      {map, v} = PlanarMap.insert_vertex(map, Point.new(x, y))
      PlanarMap.insert_edge!(map, hub, v)
    end)

  before = PlanarMap.ring!(map, hub)
  flipped = PlanarMap.scale(map, -1.0)

  assert PlanarMap.ring!(flipped, hub) == before
  assert PlanarMap.position!(flipped, hub) == Point.new(0.0, 0.0)
end
```

- [ ] **Step 2: Write the golden scenarios, then regenerate the fixtures**

  - **`remove-hub`:** a hub with four spokes, with the hub removed.
  - **`remove-moves-head`:** a vertex with three edges, where the vertex at the
    far end of the head edge is removed. The ring head moves to the predecessor.
  - **`remove-last`:** one vertex, removed (Review Focus 3).
  - **`transform-rotate`:** `hub-ring`'s map, then `transform rot 0.3`.
  - **`transform-then-insert`:** three vertices on a path, `transform rot 1.0`,
    then a new vertex and an edge to the middle vertex. It shows where the
    mixed-position angles of flaw 8 place it.
  - **`transform-empty`:** `A transform rot 1.0` on a map with no vertices, as
    the only op before the dump (Review Focus 3).
  - **`scale-translate`:** a small path, then `scale 2.5` and `translate -1.0 3.0`.
  - **`scale-negative`:** `hub-ring`'s map, then `scale -1.0` (Review Focus 5).
  - **`sort-probe`:** at least three edges whose minimum x values are about
    `0.0`, `6e-8` and `1.2e-7`, inserted in an order the non-transitive
    comparator accepts, then `transform m 1.0 0.0 0.0 0.0 1.0 0.0` (the identity)
    to force Taprats' re-sort. This is the design's early check that Java's sort
    and Elixir's stable sort agree on a non-transitive key.

  Run: `reference/oracle/run`. Append all nine names to `@scenarios`.

- [ ] **Step 3: Run the tests to verify they fail**

  Run: `mix test test/girihelix/engine/planar_map_test.exs test/girihelix/engine/planar_map_golden_test.exs`

  Expected: FAIL, with `remove_vertex!/2`, `transform/2` and `scale/2`
  undefined.

- [ ] **Step 4: Implement**

  - **`remove_vertex/2`** follows §5.2. For each edge in `v`'s ring, from the
    head:
    1. Remove the edge from the far vertex's ring with `Ring.remove/2`. A
       self-edge's far vertex is `v` itself.
    2. Remove it from `edge_order` and from `edges`.

    Then drop `v` from `vertex_order` and `vertices`. An edge listed twice, a
    self-edge, is removed once.
  - **`transform/2`** follows §5.7 `applyGeneralRigidMotion` and §3.3
    `applyRigidMotion`.
    - **Flaw 8:** walk `vertex_order`. For each vertex, replace its position
      with the transformed one, then reangle its ring against the far vertices'
      positions **as they stand at that moment**. Vertices later in the order
      are still untransformed.
    - Then stable-sort `vertex_order` by `Order.compare_points/2`, and
      `edge_order` by `Order.compare_min_x/2`, over each edge's minimum x.
    - Rings keep their order (flaw 6).
  - **`scale/2` and `translate/3`** follow §5.7 `applyTrivialRigidMotion`. They
    transform positions only: no reangling and no re-sort.

- [ ] **Step 5: Run the tests to verify they pass, and read the sort probe**

  Run: `mix test test/girihelix/engine/`

  Expected: PASS, including `sort-probe`.

  If `sort-probe` fails **only** in edge order, the two sorts disagree on a
  non-transitive key. The design's remedy is to port Java's sort into
  `Order.sort/3`.

  - **Stop and report to the user.** The port is a new task: binary insertion
    for fewer than 32 elements, and TimSort above that.
  - **Licensing:** OpenJDK is GPLv2 with the Classpath Exception, which cannot
    be copied into this GPLv3 project. So the port must be written from the
    algorithm's published description, not from OpenJDK's source.

- [ ] **Step 6: Gates**

  Run: `mix precommit.fast && mix dialyzer`

  Expected: both pass, with `Total errors: 0`.

- [ ] **Step 7: Commit**

  ```bash
  git add lib/girihelix/engine/planar_map.ex test/girihelix/engine/planar_map_test.exs test/girihelix/engine/planar_map_golden_test.exs test/support/taprats_harness.ex
  ```

  ```bash
  git commit -m "feat: remove vertices and apply rigid motions to a PlanarMap"
  ```

### Task 7: `replicate/3`, a step sequence

**Files:**

- Modify: `lib/girihelix/engine/planar_map.ex`
- Modify: `test/girihelix/engine/planar_map_test.exs`
- Modify: `test/support/taprats_harness.ex` (adds the `replicate` op)
- Modify: `test/girihelix/engine/planar_map_golden_test.exs`
- Create (local): `reference/oracle/scenarios/{replicate-ladder,replicate-coalesce,replicate-no-split,replicate-empty-unit,replicate-no-transforms}.ops`

**Interfaces:**

- Consumes: `Steps` (`step/4`, `run!/2`, `final/1`), `Order`, `Ring`.
- Produces, in `PlanarMap`. These implement §5.10 `mergeSimpleMany`:
  - `replicate_steps(unit :: t(), [Transform.t()]) :: [Steps.Step.t()]`. The
    state is the receiver map. There is one step per transform, `id: :copy` and
    labelled `"copy under transform <k>"`, then one final step `id: :sort_edges`.
  - `replicate(receiver :: t(), unit :: t(), [Transform.t()]) :: t()`, which is
    `replicate_steps(unit, transforms) |> Steps.run!(receiver) |> Steps.final()`.

- [ ] **Step 1: Write the failing unit tests**

```elixir
test "replicate/3 is the final frame of replicate_steps/2" do
  {unit, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
  {unit, b} = PlanarMap.insert_vertex(unit, Point.new(1.0, 0.0))
  unit = PlanarMap.insert_edge!(unit, a, b)
  transforms = Enum.map(0..5, &Transform.rotate(&1 * :math.pi() / 3.0))

  frames = unit |> PlanarMap.replicate_steps(transforms) |> Steps.run!(PlanarMap.new())

  assert length(frames) == 1 + 6 + 1
  assert Steps.final(frames) == PlanarMap.replicate(PlanarMap.new(), unit, transforms)
end

# Flaw 7: two unit vertices landing on one receiver vertex make a self-edge.
test "replicate/3 coalesces coincident copies, even into a self-edge" do
  {unit, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(-1.0, 0.0))
  {unit, b} = PlanarMap.insert_vertex(unit, Point.new(1.0, 0.0))
  unit = PlanarMap.insert_edge!(unit, a, b)

  map = PlanarMap.replicate(PlanarMap.new(), unit, [Transform.zero()])
  [v] = PlanarMap.vertices(map)
  [e] = PlanarMap.edges(map)

  assert PlanarMap.endpoints!(map, e) == {v, v}
end
```

- [ ] **Step 2: Write the golden scenarios, then regenerate the fixtures**

  - **`replicate-ladder`:** unit B is a spoke from `(0, 0)` to `(1, 0)`, with a
    branch to `(1.5, 0.3)`. Replicate it into empty A under
    `rot 0.0 ; rot 1.0471975511965976 ; … ; rot 5.235987755982989`, the six
    multiples of π/3 written as decimals.
  - **`replicate-coalesce`:** the self-edge case above, written as `m 0 0 0 0 0 0`.
  - **`replicate-no-split`:** A already holds the edge `(0, 0)`–`(2, 0)`. Unit
    B's vertex lands at `(1, 0)` under `tr 1.0 0.0`. Nothing splits (flaw 7).
  - **`replicate-empty-unit`:** B is empty (Review Focus 3).
  - **`replicate-no-transforms`:** `A replicate B` with no transforms. It still
    re-sorts A's edges (Review Focus 3).

  Run: `reference/oracle/run`. Append the five names to `@scenarios`.

- [ ] **Step 3: Run the tests to verify they fail**

  Run: `mix test test/girihelix/engine/planar_map_test.exs test/girihelix/engine/planar_map_golden_test.exs`

  Expected: FAIL, with `replicate_steps/2` undefined.

- [ ] **Step 4: Implement**

  - **Each `:copy` step**, for its transform `T`:
    1. Map every unit vertex, in unit vertex order, to the receiver vertex
       found or created at `T(position)`, by find-or-create **without
       splitting**.
    2. For every unit edge, in unit edge order:
       - make a new receiver edge between the two mapped vertices;
       - **append** it to `edge_order`, unsorted;
       - insert it into the first mapped vertex's ring, then the second's.
  - **The `:sort_edges` step** stable-sorts `edge_order` by minimum x.
  - The step closures may call `PlanarMap`'s private functions, because they
    are defined inside the module.

- [ ] **Step 5: Run the tests to verify they pass**

  Run: `mix test test/girihelix/engine/`

  Expected: PASS.

- [ ] **Step 6: Gates**

  Run: `mix precommit.fast && mix dialyzer`

  Expected: both pass, with `Total errors: 0`.

- [ ] **Step 7: Commit**

  ```bash
  git add lib/girihelix/engine/planar_map.ex test/girihelix/engine/planar_map_test.exs test/girihelix/engine/planar_map_golden_test.exs test/support/taprats_harness.ex
  ```

  ```bash
  git commit -m "feat: replicate a unit into a PlanarMap under a list of transforms"
  ```

### Task 8: `weld/2`, a step sequence

**Files:**

- Create: `lib/girihelix/engine/planar_map/weld.ex`
- Create: `test/girihelix/engine/planar_map/weld_test.exs`
- Modify: `lib/girihelix/engine/planar_map.ex`
- Modify: `test/girihelix/engine/planar_map_test.exs`
- Modify: `test/support/taprats_harness.ex` (adds the `weld` op)
- Modify: `test/girihelix/engine/planar_map_golden_test.exs`
- Create (local): `reference/oracle/scenarios/{weld-squares,weld-shared-edge,weld-cluster,weld-collinear,weld-self,weld-empty-receiver,weld-empty-other}.ops`

**Interfaces:**

- Consumes: `Segment.new/2`, `Intersect.get_true_intersection/2`,
  `Order.compare_min_x/2`, `Order.compare_points/2`, `Ring`, `Steps`.
- Produces, in `Girihelix.Engine.PlanarMap.Weld`, implementing §5.8 steps 1–3
  and §5.9:
  - `crossings(other :: [{Point.t(), Point.t()}], receiver :: [{Point.t(), Point.t()}]) :: [Point.t()]`.
    Both lists are edges in Taprats edge order. For each other edge, it walks
    the receiver edges until one's minimum x compares `:gt` against the other
    edge's **maximum** x. It keeps every non-nil `get_true_intersection`.
    - A pair where either `Segment.new/2` fails is skipped, the same as `nil`.
    - Repeats are kept, in order.
  - `merge_plan(mine :: [{v, Point.t()}], yours :: [{v, Point.t()}]) :: [{:mine, v} | {:same, v, v} | {:yours, v}]`.
    This is the two-pointer merge of §5.9 by `compare_points`: on `:eq` it
    emits `{:same, mine, yours}` and advances both lists.
- Produces, in `PlanarMap`:
  - `@type weld_state :: %{receiver: t(), other: t(), originals: [vertex()], crossings: [Point.t()], mapping: %{vertex() => vertex()}}`
  - `weld_start(receiver :: t(), other :: t()) :: weld_state`
  - `weld_steps() :: [Steps.Step.t()]`. There are four steps, with ids
    `:find_crossings`, `:force_vertices`, `:unify_vertices` and `:copy_edges`.
  - `weld_result(weld_state) :: {t(), %{vertex() => vertex()}}`. The mapping is
    restricted to `originals`, which are the other map's vertices before step 2.
  - `weld(receiver :: t(), other :: t()) :: {t(), %{vertex() => vertex()}}`

- [ ] **Step 1: Write the failing tests**

```elixir
# weld_test.exs
test "merge_plan/2 walks both orders once, the receiver winning ties" do
  mine = [{:m0, Point.new(0.0, 0.0)}, {:m1, Point.new(2.0, 0.0)}]
  yours = [{:y0, Point.new(1.0, 0.0)}, {:y1, Point.new(2.0, 5.0e-8)}, {:y2, Point.new(3.0, 0.0)}]

  assert Weld.merge_plan(mine, yours) == [{:mine, :m0}, {:yours, :y0}, {:same, :m1, :y1}, {:yours, :y2}]
end

test "crossings/2 finds the crossing and ignores a shared endpoint" do
  receiver = [{Point.new(0.0, 0.0), Point.new(2.0, 2.0)}]

  assert Weld.crossings([{Point.new(0.0, 2.0), Point.new(2.0, 0.0)}], receiver) == [Point.new(1.0, 1.0)]
  assert Weld.crossings([{Point.new(0.0, 0.0), Point.new(-1.0, 3.0)}], receiver) == []
end

# planar_map_test.exs
test "weld/2 is the final frame of its steps, with the mapping over the other map's vertices" do
  {receiver, r1} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
  {receiver, r2} = PlanarMap.insert_vertex(receiver, Point.new(2.0, 2.0))
  receiver = PlanarMap.insert_edge!(receiver, r1, r2)
  {other, o1} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 2.0))
  {other, o2} = PlanarMap.insert_vertex(other, Point.new(2.0, 0.0))
  other = PlanarMap.insert_edge!(other, o1, o2)

  {welded, mapping} = PlanarMap.weld(receiver, other)

  frames = Steps.run!(PlanarMap.weld_steps(), PlanarMap.weld_start(receiver, other))
  assert PlanarMap.weld_result(Steps.final(frames)) == {welded, mapping}
  assert Map.keys(mapping) |> Enum.sort() == Enum.sort([o1, o2])
  assert PlanarMap.num_vertices(welded) == 5
  assert PlanarMap.num_edges(welded) == 4
end

# Review Focus 2: welding a map to itself doubles every edge, as Taprats does.
test "weld/2 of a map with itself unifies every vertex and doubles every edge" do
  {map, a} = PlanarMap.insert_vertex(PlanarMap.new(), Point.new(0.0, 0.0))
  {map, b} = PlanarMap.insert_vertex(map, Point.new(1.0, 0.0))
  map = PlanarMap.insert_edge!(map, a, b)

  {welded, mapping} = PlanarMap.weld(map, map)

  assert mapping == %{a => a, b => b}
  assert PlanarMap.num_edges(welded) == 2
end
```

- [ ] **Step 2: Write the golden scenarios, then regenerate the fixtures**

  - **`weld-squares`:** unit squares at `(0, 0)` and `(0.5, 0.5)`. They cross
    twice.
  - **`weld-shared-edge`:** two squares sharing one side. The vertices unify,
    and the shared side becomes two parallel edges (flaw 4).
  - **`weld-cluster`:** other-map vertices lying within `1e-7` of receiver
    vertices that are themselves less than `2e-7` apart. Some unify and some
    become new vertices (flaw 3).
  - **`weld-collinear`:** edges `(0, 0)`–`(2, 0)` and `(1, 0)`–`(3, 0)`.
    Nothing is split (flaw 4).
  - **`weld-self`:** `A weld A` (Review Focus 2).
  - **`weld-empty-receiver`** and **`weld-empty-other`** (Review Focus 3).

  Run: `reference/oracle/run`. Append the seven names to `@scenarios`.

- [ ] **Step 3: Run the tests to verify they fail**

  Run: `mix test test/girihelix/engine/planar_map/weld_test.exs test/girihelix/engine/planar_map_test.exs test/girihelix/engine/planar_map_golden_test.exs`

  Expected: FAIL, with `Weld` and `weld/2` undefined.

- [ ] **Step 4: Implement**

  - **`:find_crossings`** stores
    `Weld.crossings(other_edges, receiver_edges)` in the state.
  - **`:force_vertices`** threads `insert_vertex/2` through each crossing: on
    the receiver first, then on the other map. It discards the handles.
  - **`:unify_vertices`** applies `Weld.merge_plan/2` to the two vertex orders:
    - `{:mine, v}` keeps `v`;
    - `{:same, m, y}` maps `y` to `m`;
    - `{:yours, y}` makes a new receiver vertex at `y`'s position, with an empty
      ring, and maps `y` to it.

    The resulting order is the new `vertex_order`.
  - **`:copy_edges`**, for each other-map edge in its edge order: append a
    receiver edge between the mapped endpoints, insert it into the first
    endpoint's ring and then the second's, and finally stable-sort `edge_order`
    by minimum x.
  - **`weld_start/2`** records `originals` as the other map's `vertices/1`.

- [ ] **Step 5: Run the tests to verify they pass**

  Run: `mix test test/girihelix/engine/`

  Expected: PASS.

- [ ] **Step 6: Gates**

  Run: `mix precommit.fast && mix dialyzer`

  Expected: both pass, with `Total errors: 0`. If `planar_map.ex` passes 800
  lines, `GIRI001` fails. Move the step definitions' private helpers behind a
  narrower interface before committing; never raise the limit.

- [ ] **Step 7: Commit**

  ```bash
  git add lib/girihelix/engine/planar_map.ex lib/girihelix/engine/planar_map/weld.ex test/girihelix/engine/planar_map/weld_test.exs test/girihelix/engine/planar_map_test.exs test/girihelix/engine/planar_map_golden_test.exs test/support/taprats_harness.ex
  ```

  ```bash
  git commit -m "feat: weld two PlanarMaps, splitting edges at their crossings"
  ```

### Task 9: `verify/1` and the checked edge insert

**Files:**

- Create: `lib/girihelix/engine/planar_map/verify.ex`
- Create: `lib/girihelix/engine/planar_map/check.ex`
- Create: `test/girihelix/engine/planar_map/verify_test.exs`
- Modify: `lib/girihelix/engine/planar_map.ex`
- Modify: `test/support/taprats_harness.ex` (`dump/1` now reports `verify`)

**Interfaces:**

- Consumes: `PlanarMap`'s public queries only. Neither module touches the
  struct.
- Produces:
  - **`PlanarMap.verify(t()) :: :ok | {:error, [problem]}`**. It delegates to
    `PlanarMap.Verify.problems/1` and implements Taprats' five checks from
    §5.11, without its `NullPointerException` (ruling 2). Each problem is one of:
    - `{:trivial_edge, edge}`
    - `{:missing_endpoint, edge}`
    - `{:not_in_ring, edge}`
    - `{:parallel_edge, edge}`
    - `{:edges_unsorted, index}`, for consecutive edges whose minimum x values
      satisfy `a > b + 1.0e-7`
    - `{:duplicate_vertices, index}` or `{:vertices_unsorted, index}`, for
      consecutive vertices comparing `:eq` or `:gt`
  - **`PlanarMap.insert_edge_checked(t(), vertex(), vertex()) :: {:ok, t()} | {:error, :unknown_vertex | :crosses}`**,
    and `insert_edge_checked!/3`.
    - It returns `{:error, :crosses}` when `PlanarMap.Check.crosses?/3` holds,
      and otherwise behaves as `insert_edge/3`.
    - `crosses?` is true whenever the new segment meets the map anywhere other
      than at its own two endpoint vertices: the cases listed in the design.
  - **`TapratsHarness.dump/1`** reports `verify: true` or `false` from
    `PlanarMap.verify/1`.

- [ ] **Step 1: Write the failing tests**

```elixir
defp path(points) do
  {handles, map} =
    Enum.map_reduce(points, PlanarMap.new(), fn {x, y}, map ->
      {map, v} = PlanarMap.insert_vertex(map, Point.new(x, y))
      {v, map}
    end)

  {map, handles}
end

test "verify/1 accepts a well-formed map" do
  {map, [a, b, c]} = path([{0.0, 0.0}, {1.0, 0.0}, {1.0, 1.0}])
  map = map |> PlanarMap.insert_edge!(a, b) |> PlanarMap.insert_edge!(b, c)

  assert PlanarMap.verify(map) == :ok
end

# Review Focus 4.
test "verify/1 reports a self-edge as trivial" do
  {map, [a]} = path([{0.0, 0.0}])
  map = PlanarMap.insert_edge!(map, a, a)
  [e] = PlanarMap.edges(map)

  assert {:error, problems} = PlanarMap.verify(map)
  assert {:trivial_edge, e} in problems
end

# Review Focus 2.
test "verify/1 reports the parallel edges a self-weld makes" do
  {map, [a, b]} = path([{0.0, 0.0}, {1.0, 0.0}])
  map = PlanarMap.insert_edge!(map, a, b)
  {welded, _} = PlanarMap.weld(map, map)

  assert {:error, problems} = PlanarMap.verify(welded)
  assert Enum.any?(problems, &match?({:parallel_edge, _}, &1))
end

test "insert_edge_checked/3 refuses every way of meeting the map except at shared endpoints" do
  {map, [a, b, c, d, m]} = path([{0.0, 0.0}, {2.0, 0.0}, {1.0, -1.0}, {1.0, 1.0}, {3.0, 0.0}])
  map = PlanarMap.insert_edge!(map, a, b)
  {map, far} = PlanarMap.insert_vertex(map, Point.new(4.0, 1.0))

  assert PlanarMap.insert_edge_checked(map, c, d) == {:error, :crosses}
  assert PlanarMap.insert_edge_checked(map, a, m) == {:error, :crosses}
  assert PlanarMap.insert_edge_checked(map, a, b) == {:error, :crosses}
  assert PlanarMap.insert_edge_checked(map, a, a) == {:error, :crosses}
  assert {:ok, _} = PlanarMap.insert_edge_checked(map, b, far)
  assert PlanarMap.insert_edge_checked(map, a, 999) == {:error, :unknown_vertex}
end
```

  In the last test:

- `c`–`d` is a proper crossing.
- `a`–`m` passes through `b`, and overlaps `a`–`b`.
- `a`–`b` duplicates an existing edge.
- `a`–`a` is a self-edge.
- `b`–`far` meets the map only at `b`, so it is accepted.

  Add one test each for a T-junction, where a new endpoint lies inside an
  existing edge, and for an edge passing through a vertex with no overlap.

- [ ] **Step 2: Run the tests to verify they fail**

  Run: `mix test test/girihelix/engine/planar_map/verify_test.exs`

  Expected: FAIL, with `verify/1` and `insert_edge_checked/3` undefined.

- [ ] **Step 3: Implement both modules**

  - **`Verify`** walks the public queries. It checks the trivial, membership
    and ring conditions for both endpoint directions, as Taprats does twice.
  - **`Check`** tests, for each existing edge:
    - Shared endpoints are excluded.
    - Does `Intersect.get_intersection/2` find a crossing? A pair whose
      `Segment.new/2` fails is not a crossing.
    - Is either segment collinear with and overlapping the other? Use
      `Point.dist_to_line/3` with `Loose.zero/1` on the endpoints.

    It then tests every other vertex for lying on the new segment, and each new
    endpoint for lying inside an existing edge.

- [ ] **Step 4: Run every test, golden included**

  Run: `mix test test/girihelix/`

  Expected: PASS. Every golden scenario whose Taprats `verify` was `true` now
  also compares the `verify` word.

- [ ] **Step 5: Gates**

  Run: `mix precommit.fast && mix dialyzer`

  Expected: both pass, with `Total errors: 0`.

- [ ] **Step 6: Commit**

  ```bash
  git add lib/girihelix/engine/planar_map.ex lib/girihelix/engine/planar_map/verify.ex lib/girihelix/engine/planar_map/check.ex test/girihelix/engine/planar_map/verify_test.exs test/support/taprats_harness.ex
  ```

  ```bash
  git commit -m "feat: verify a PlanarMap, and insert an edge with a crossing check"
  ```

### Task 10: Homogenisation pass

**Files:**

- Modify: everything under `lib/girihelix/engine/planar_map*`, and
  `lib/girihelix/engine/steps.ex`
- Modify: `docs/algorithm-analysis.md`
- Modify: `docs/superpowers/specs/2026-10-20-girihelix-planar-map-design.md`
- Modify: `docs/superpowers/specs/2026-10-16-girihelix-workbench-design.md`
- Modify: `docs/backlog.md`

**Interfaces:** none. Code behaviour must not change.

- [ ] **Step 1: Record the eight faithful flaws in the analysis document**

  Add them under `### Map: the planar map`. Rename that heading to `PlanarMap`,
  and replace the method table's names with the Elixir ones. Each flaw gets
  three things:
  - what Taprats does;
  - the decision to keep it;
  - the test or golden scenario that pins it.

- [ ] **Step 2: Strip source narration, with the wide grep**

  Run: `grep -rniE "java|taprats|ported|reference tree|source's|mergeMap|mergeSimple|insertEdge|getVertex" lib/girihelix/engine`

  - Restate each hit as a decision in the caller's terms, as the engine types
    pass did.
  - Citations of a porting-notes section, such as "§5.5", are pointers for
    maintainers. They may stay in code comments, but not in docs.
  - `steps.ex`'s moduledoc names `Map.merge_map`. Change it to
    `PlanarMap.weld/2`.

- [ ] **Step 3: Bring the documents up to date**

  - **The spec:** set Status to implemented, and add the three rulings at the
    top of this plan.
  - **The workbench spec:** add a sentence under its plan-series table, saying
    Plan 1's remainder became Plans 1b and 1c.
  - **The backlog:** close the `Map` → `PlanarMap` item, naming the commits.

- [ ] **Step 4: Lint, and run the full gate**

  ```bash
  markdownlint-cli2 --config ~/.markdownlint-cli2.jsonc docs/algorithm-analysis.md docs/backlog.md docs/superpowers/specs/2026-10-20-girihelix-planar-map-design.md docs/superpowers/specs/2026-10-16-girihelix-workbench-design.md
  ```

  Expected: `0 error(s)`.

  ```bash
  mix precommit
  ```

  Expected: passes. Dialyzer reports `Total errors: 0`, and the golden scenarios
  run, because the fixtures exist locally.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/girihelix/engine docs/algorithm-analysis.md docs/backlog.md docs/superpowers/specs
  ```

  ```bash
  git commit -m "docs: record the planar map's faithful flaws and homogenise the docs"
  ```

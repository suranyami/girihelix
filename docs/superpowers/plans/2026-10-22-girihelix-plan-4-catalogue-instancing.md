# Catalogue and instancing implementation plan (Plan 4)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Load Taprats' `.tiling` catalogue into engine values, construct a tiling plus figures into a planar map, verify it against real Taprats, and expose catalogue, tiling and instancing exhibits.

**Architecture:** New engine modules under `lib/girihelix/engine/tilings/`: `Feature`, `PlacedFeature`, `Tiling`, `Parser`, `Catalogue`, and `Construct` (a `start/steps/result` sequence over `FillRegion`, `PlanarMap.replicate` and `PlanarMap.weld`). The 60 Taprats `.tiling` files are vendored into `priv/tilings/` with an index. Constructed maps are compared to Taprats canonically, because Java's hash iteration order is unspecified. Three workbench exhibits in `:tilings` use a shared `Exhibits.Tilings` helper.

**Tech Stack:** Elixir 1.20, ExUnit, the existing `PlanarMap`/`FillRegion`/figures engine, the local Java Taprats harness, Phoenix LiveView exhibits. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-22-girihelix-catalogue-instancing-design.md`. Read it first; it fixes every interface this plan uses. The authoritative source behaviour is the local, git-ignored `reference/porting-notes/prototype-and-tilings.md` and the Java in `reference/1.1.12/src/`.

## Global Constraints

- **Engine purity.** `lib/girihelix/engine/**` imports the standard library only. No Ash, Ecto, Phoenix or `GirihelixWeb`.
- **Hard rules.** No `if` or `cond`; branch in function heads and guards. Failing public functions return `{:error, reason}` with a `name!` twin; a geometric degeneracy may raise inside a figure builder and is captured by `Steps`.
- **Faithful first.** Preserve Taprats' four-pass construction: FillRegion translations, simple merge per feature, simple merge per translation, then one slow weld. Use `Figure.map/1`, never `Figure.unit/1`. Keep `1.0e-7` coalescing and FillRegion's 1,000-row cap.
- **Steps.** `Construct` exposes `start/3`, `steps/3`, `result/1`; the plain `construct/3` is the steps run. Step ids are `:place`, `:bind`, `:units`, `:weld`.
- **The harness stays local.** Nothing under `reference/` is committed. The catalogue files copied into `priv/` are committed with provenance.
- **Catalogue.** Exactly the 60 `reference/1.1.12/tilings/*.tiling` files; names from file bodies, not filenames. Two descriptions are sanitised to valid UTF-8.
- **Goldens.** Canonical comparison (sorted positions, not index-wise), coordinates to `1.0e-12`.
- **Gates.** `mix dialyzer` reports `Total errors: 0` before every commit. No module over 800 lines. `mix format --check-formatted` passes.
- **Git.** Run `git commit` as its own command. Commits are signed; on a 1Password error stop and ask.

## Review Focus

1. **A triangle regular feature in `star` mode.** Tilings such as `3-8-12` contain regular triangles; `Star.build!/3` is used so `Figure.map/1` raises at the closure and the run is a failure frame, not a LiveView 500. Owner: Task 10.
2. **No bindings and no regular features.** `figure: :none`, and six tilings with only polygons, must still draw the translation vectors, unit cell and placed-feature outlines, with `verify` reported as `n/a`. Owner: Task 10.
3. **The unit-cell boundary.** A corner at `-1.0e-16` floors to a spurious row on `4.5`; `Construct.default_region/1` must use the expanded bounding box, not the parallelogram. Owner: Task 5.
4. **A non-UTF-8 description.** `Mughal.tiling` and `pbn_7.tiling` must load with a valid description (U+FFFD replacements) and unchanged name and geometry. Owner: Task 4.
5. **A degenerate lattice or an oversized region.** Parallel generators return `:degenerate_basis`; more than 1,000 rows return `:too_many_units`; the exhibit draws the failure frames rather than crashing. Owner: Tasks 6 and 10.

---

### Task 1: `Feature` and `PlacedFeature`

**Files:**

- Create: `lib/girihelix/engine/tilings/feature.ex`
- Create: `lib/girihelix/engine/tilings/placed_feature.ex`
- Test: `test/girihelix/engine/tilings/feature_test.exs`

**Interfaces:**

- Produces:
  - `Girihelix.Engine.Tilings.Feature`
    - `@enforce_keys [:id, :regular, :points]`
    - `defstruct [:id, :regular, :points]`
    - `@type t :: %__MODULE__{id: integer(), regular: pos_integer() | nil, points: [Point.t()]}`
    - `new(regular: pos_integer() | nil, points: [Point.t()]) :: t()` with a provisional id of `-1`
    - `points(t()) :: [Point.t()]` — stored points, or the generated regular polygon
    - `equal?(t(), t()) :: boolean()` — tolerant structural equality
    - `assign_ids([t()]) :: [t()]` — de-duplicates by `equal?/2` and assigns `0..k-1`
  - `Girihelix.Engine.Tilings.PlacedFeature`
    - `@enforce_keys [:feature_id, :transform]`
    - `defstruct [:feature_id, :transform]`
    - `@type t :: %__MODULE__{feature_id: integer(), transform: Transform.t()}`
    - `new(integer(), Transform.t()) :: t()`

- [ ] **Step 1: Write the failing tests**

```elixir
test "a regular feature generates Taprats' polygon" do
  n = 6
  feature = Feature.new(regular: n, points: [])
  r = 1.0 / :math.cos(:math.pi() / n)

  expected =
    Enum.map(0..(n - 1), fn i ->
      Point.scale(RadialFigure.arc((2 * i + 1) / (2 * n)), r)
    end)

  assert length(Feature.points(feature)) == n

  for {actual, want} <- Enum.zip(Feature.points(feature), expected) do
    assert Loose.equals(actual, want)
  end
end

test "equal?/2 is tolerant on points and includes the regular flag" do
  a = Feature.new(regular: 4, points: [])
  b = Feature.new(regular: 4, points: [])
  c = Feature.new(regular: nil, points: Feature.points(a))
  off = Feature.new(regular: nil, points: Enum.map(Feature.points(a), &Point.add(&1, Point.new(1.0e-8, 0.0))))

  assert Feature.equal?(a, b)
  refute Feature.equal?(a, c)
  assert Feature.equal?(c, off)
end

test "assign_ids/1 shares one id across tolerant duplicates" do
  a = Feature.new(regular: 4, points: [])
  b = Feature.new(regular: 4, points: [])
  c = Feature.new(regular: 3, points: [])

  assert [%{id: 0}, %{id: 0}, %{id: 1}] = Feature.assign_ids([a, b, c])
end

test "a placed feature compares its transform exactly" do
  t = Transform.translate(1.0, 2.0)
  assert PlacedFeature.new(0, t) == PlacedFeature.new(0, t)
  refute PlacedFeature.new(0, t) == PlacedFeature.new(1, t)
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix/engine/tilings/feature_test.exs`
Expected: FAIL, the modules are undefined.

- [ ] **Step 3: Implement the two structs**

`Feature.points/1` returns `feature.points` when `regular` is `nil`; otherwise generates `Point.scale(RadialFigure.arc((2i+1)/(2n)), 1.0 / :math.cos(:math.pi() / n))` for `i` in `0..(n-1)`.
`Feature.equal?/2` requires equal `regular` flags and equal point lists under `Loose.equals/2`, in order.
`Feature.assign_ids/1` folds the list, comparing each feature with the already-assigned representatives using `equal?/2`, appending a new id when none matches; return features in input order with stable ids.
`PlacedFeature` is a plain struct; equality is the default structural equality (exact six-double transform).

- [ ] **Step 4: Run the tests to see them pass**

Run: `mix test test/girihelix/engine/tilings/feature_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/girihelix/engine/tilings/feature.ex lib/girihelix/engine/tilings/placed_feature.ex test/girihelix/engine/tilings/feature_test.exs
git commit -m "feat: add the tiling feature values"
```

---

### Task 2: `Tiling`

**Files:**

- Create: `lib/girihelix/engine/tilings/tiling.ex`
- Test: `test/girihelix/engine/tilings/tiling_test.exs`

**Interfaces:**

- Produces `Girihelix.Engine.Tilings.Tiling`:
  - `@enforce_keys [:name, :t1, :t2, :features, :placements]`
  - `defstruct [:name, :description, :author, :t1, :t2, :features, :placements]`
  - `@type t :: %__MODULE__{name: String.t(), description: String.t() | nil, author: String.t() | nil, t1: Point.t(), t2: Point.t(), features: [Feature.t()], placements: [PlacedFeature.t()]}`
  - `new(keyword()) :: t()`
  - `unit_cell(t()) :: [Point.t()]` — `[origin, t1, t1 + t2, t2]`
  - `placements_for(t(), integer()) :: [Transform.t()]` — transforms whose feature id matches, in stored order

- [ ] **Step 1: Write the failing tests**

```elixir
test "the unit cell is the parallelogram of the two generators" do
  tiling = Tiling.new(name: "t", t1: Point.new(2.0, 0.0), t2: Point.new(0.0, 3.0), features: [], placements: [])

  assert Tiling.unit_cell(tiling) == [
           Point.new(0.0, 0.0),
           Point.new(2.0, 0.0),
           Point.new(2.0, 3.0),
           Point.new(0.0, 3.0)
         ]
end

test "placements_for/2 filters by feature id and keeps order" do
  a = Transform.translate(1.0, 0.0)
  b = Transform.rotate(0.5)
  tiling = Tiling.new(name: "t", t1: Point.new(1.0, 0.0), t2: Point.new(0.0, 1.0), features: [],
    placements: [PlacedFeature.new(0, a), PlacedFeature.new(1, b), PlacedFeature.new(0, b)])

  assert Tiling.placements_for(tiling, 0) == [a, b]
  assert Tiling.placements_for(tiling, 2) == []
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix/engine/tilings/tiling_test.exs`
Expected: FAIL, `Tiling` is undefined.

- [ ] **Step 3: Implement `Tiling`**

`new/1` builds the struct from the keyword list. `unit_cell/1` returns the four points with `Point.add/2`. `placements_for/2` filters on `feature_id` and maps to `transform`.

- [ ] **Step 4: Run the tests to see them pass**

Run: `mix test test/girihelix/engine/tilings/tiling_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/girihelix/engine/tilings/tiling.ex test/girihelix/engine/tilings/tiling_test.exs
git commit -m "feat: add the tiling value"
```

---

### Task 3: The `.tiling` parser

**Files:**

- Create: `lib/girihelix/engine/tilings/parser.ex`
- Test: `test/girihelix/engine/tilings/parser_test.exs`
- Test fixture: use the reference file path in tests; the vendored copy arrives in Task 4.

**Interfaces:**

- Produces `Girihelix.Engine.Tilings.Parser`:
  - `@type reason :: :not_a_tiling | {:bad_keyword, String.t()} | :truncated | :invalid_number`
  - `parse(String.t()) :: {:ok, Tiling.t()} | {:error, reason()}`
  - `parse_file(Path.t()) :: {:ok, Tiling.t()} | {:error, reason() | File.posix()}`
- Parsing assigns feature ids with `Feature.assign_ids/1`; placements are built with the assigned id.

- [ ] **Step 1: Write the failing tests**

```elixir
@four_five "reference/1.1.12/tilings/4.5.tiling"
@six_five "reference/1.1.12/tilings/6.5.tiling"

test "parses 4.5 with its two generators, three features and seven placements" do
  assert {:ok, tiling} = Parser.parse_file(@four_five)

  assert tiling.name == "4.5"
  assert length(tiling.features) == 3
  assert length(tiling.placements) == 7
  assert Loose.equals(tiling.t1, Point.new(4.5201470213401995, 4.520147021340199))
  assert Loose.equals(tiling.t2, Point.new(-1.1213252548714083e-14, 9.040294042680392))
  assert Enum.any?(tiling.features, &(&1.regular == 4))
end

test "parses 6.5 with two features and seven placements" do
  assert {:ok, tiling} = Parser.parse_file(@six_five)
  assert tiling.name == "6.5"
  assert length(tiling.features) == 2
  assert length(tiling.placements) == 7
  assert Enum.any?(tiling.features, &(&1.regular == 6))
end

test "rejects a file whose first token is not tiling" do
  assert Parser.parse("polygon 4 1\n") == {:error, :not_a_tiling}
end

test "rejects an unknown feature keyword instead of desynchronising" do
  assert {:error, {:bad_keyword, "regularr"}} =
           Parser.parse(~s(tiling "x" 1\n0.0 1.0\n1.0 0.0\nregularr 4 1\n0.0 1.0\n1.0 0.0\n))
end

test "a missing description and author are allowed" do
  text = ~s(tiling "x" 0\n0.0 1.0\n1.0 0.0\n)
  assert {:ok, %{name: "x", description: nil, author: nil}} = Parser.parse(text)
end

test "sanitises a non-UTF-8 description" do
  text =
    ~s(tiling "x" 0\n0.0 1.0\n1.0 0.0\n"bad ) <>
      <<0x92>> <>
      ~s("\n"author"\n)

  assert {:ok, tiling} = Parser.parse(text)
  assert String.valid?(tiling.description)
  assert tiling.description =~ "bad"
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix/engine/tilings/parser_test.exs`
Expected: FAIL, `Parser` is undefined.

- [ ] **Step 3: Implement the tokenizer and parser**

Tokenize with a regex that strips `#`, `%`, `//` and `/* ... */` comments, treats quoted strings as one token, and accepts numbers in `E` notation. Parse the header, the two generators, then each feature (`regular <n> <placements>` or `polygon <points> <placements>`), then the quoted description and author (optional at EOF). `String.to_float/1` and `Integer.parse/1` failures map to `:invalid_number`; a short token stream maps to `:truncated`. Sanitise description/author with a helper that replaces invalid UTF-8 sequences with U+FFFD.

- [ ] **Step 4: Run the tests to see them pass**

Run: `mix test test/girihelix/engine/tilings/parser_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/girihelix/engine/tilings/parser.ex test/girihelix/engine/tilings/parser_test.exs
git commit -m "feat: parse the tiling file format"
```

---

### Task 4: Vendor the catalogue and add the loader

**Files:**

- Create: `priv/tilings/*.tiling` (the 60 files), `priv/tilings/index.json`, `priv/tilings/README.md`
- Create: `lib/girihelix/engine/tilings/catalogue.ex`
- Test: `test/girihelix/engine/tilings/catalogue_test.exs`

**Interfaces:**

- Produces `Girihelix.Engine.Tilings.Catalogue`:
  - `names() :: [String.t()]` — the index, in name order
  - `name_options() :: [atom()]` — atoms for the workbench enum, built at compile time from the index
  - `load(String.t()) :: {:ok, Tiling.t()} | {:error, :unknown_tiling | term()}`
  - `load!(String.t()) :: Tiling.t()` — raises `ArgumentError` for an unknown or unparsable tiling
  - `all() :: [{String.t(), {:ok, Tiling.t()} | {:error, term()}}]`

- [ ] **Step 1: Copy the catalogue and generate the index**

```bash
mkdir -p priv/tilings
cp reference/1.1.12/tilings/*.tiling priv/tilings/
python3 - <<'PY'
import json, pathlib, re
root = pathlib.Path("priv/tilings")
entries = []
for path in sorted(root.glob("*.tiling")):
    first = path.read_text(encoding="latin-1").splitlines()[0]
    name = re.match(r'tiling\s+"(.*)"\s+\d+', first).group(1)
    entries.append({"name": name, "file": path.name})
entries.sort(key=lambda e: e["name"])
(root / "index.json").write_text(json.dumps(entries, indent=2) + "\n")
PY
```

Write `priv/tilings/README.md` recording the source (`Taprats 1.1.12`, `reference/1.1.12/tilings/`), the GPLv3 provenance, and that `Mughal.tiling` and `pbn_7.tiling` carry non-UTF-8 descriptions that the loader sanitises.

- [ ] **Step 2: Write the failing tests**

```elixir
test "the index lists all 60 tilings with unique names" do
  names = Catalogue.names()
  assert length(names) == 60
  assert names == Enum.uniq(names)
  assert "4.5" in names
  assert "6.5" in names
end

test "load/1 parses a known tiling" do
  assert {:ok, %{name: "4.5"} = tiling} = Catalogue.load("4.5")
  assert length(tiling.features) == 3
end

test "all 60 files load, including the legacy-encoded descriptions" do
  results = Catalogue.all()
  assert length(results) == 60
  assert Enum.all?(results, fn {_name, result} -> match?({:ok, _}, result) end)

  assert {:ok, mughal} = Catalogue.load("Mughal")
  assert String.valid?(mughal.description)
end

test "an unknown name is an error" do
  assert Catalogue.load("nope") == {:error, :unknown_tiling}
end
```

- [ ] **Step 3: Run them to see them fail**

Run: `mix test test/girihelix/engine/tilings/catalogue_test.exs`
Expected: FAIL, `Catalogue` is undefined.

- [ ] **Step 4: Implement `Catalogue`**

Read `priv/tilings/index.json` with `Jason.decode!/1` at compile time into `@entries` and `@names`, with `@external_resource "priv/tilings/index.json"`. `name_options/0` maps names with `String.to_atom/1` (trusted local catalogue data, 60 atoms). `load/1` finds the file in the index, reads and parses it. `all/0` loads every name, returning `{name, result}` so the exhibit can show parse failures.

- [ ] **Step 5: Run the tests to see them pass**

Run: `mix test test/girihelix/engine/tilings/catalogue_test.exs`
Expected: PASS. If a file fails to parse, fix the parser or record the file; do not exclude it silently.

- [ ] **Step 6: Commit**

```bash
git add priv/tilings lib/girihelix/engine/tilings/catalogue.ex test/girihelix/engine/tilings/catalogue_test.exs
git commit -m "feat: ship and load the tiling catalogue"
```

---

### Task 5: `Construct` region, placement and binding

**Files:**

- Create: `lib/girihelix/engine/tilings/construct.ex`
- Test: `test/girihelix/engine/tilings/construct_test.exs`

**Interfaces:**

- Produces `Girihelix.Engine.Tilings.Construct`:
  - `@type binder :: (Feature.t() -> Figure.t() | nil)`
  - `@type state :: map()` with `:tiling, :binder, :region, :translations, :bindings, :feature_maps, :map, :failure`
  - `default_region(Tiling.t()) :: [Point.t()]`
  - `start(Tiling.t(), binder(), [Point.t()]) :: state()`
  - `steps(Tiling.t(), binder(), [Point.t()]) :: [Steps.Step.t()]`
  - `result(state()) :: {:ok, PlanarMap.t()} | {:error, reason()}` (implemented in Task 6; Task 5 may return `{:ok, nil}` for an unwelded state)

- [ ] **Step 1: Write the failing tests**

```elixir
test "default_region is the expanded bounding box, not the unit parallelogram" do
  tiling = Tiling.new(name: "t", t1: Point.new(2.0, 0.0), t2: Point.new(0.0, 2.0), features: [], placements: [])
  region = Construct.default_region(tiling)
  assert length(region) == 4

  margin = 0.01 * 2.0
  assert Loose.equals(Enum.at(region, 0), Point.new(-margin, -margin))
  assert Loose.equals(Enum.at(region, 2), Point.new(2.0 + margin, 2.0 + margin))
end

test "the :place step enumerates the cell translations" do
  tiling = Catalogue.load!("4.5")
  steps = Construct.steps(tiling, fn _ -> nil end, Construct.default_region(tiling))
  assert Enum.map(steps, & &1.id) == [:place, :bind, :units, :weld]

  state = steps |> Steps.run!(Construct.start(tiling, fn _ -> nil end, Construct.default_region(tiling))) |> Steps.final()
  assert length(state.translations) > 0
  assert Enum.all?(state.translations, &match?(%Transform{}, &1))
end

test "the :bind step keeps only non-nil bindings" do
  tiling = Catalogue.load!("4.5")
  binder = fn feature -> if feature.regular, do: Rosette.new!(feature.regular, 0.0, 3) end
  state = Construct.steps(tiling, binder, Construct.default_region(tiling)) |> Steps.run!(Construct.start(tiling, binder, Construct.default_region(tiling))) |> Steps.final()

  assert [{feature, %Rosette{}}] = state.bindings
  assert feature.regular == 4
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix/engine/tilings/construct_test.exs`
Expected: FAIL, `Construct` is undefined.

- [ ] **Step 3: Implement `default_region/1`, `start/3`, `steps/3` and the first two steps**

`default_region/1` takes the bounding box of `Tiling.unit_cell/1`, expands each side by `0.01 * max(Point.mag(t1), Point.mag(t2))`, and returns the four corners. `:place` calls `FillRegion.fill/3` and stores `Transform.translate(m * t1.x + n * t2.x, m * t1.y + n * t2.y)` for each `{m, n}`; a `{:error, reason}` becomes `failure: reason`. `:bind` maps every feature through the binder and keeps the non-nil results. Implement `:units` and `:weld` as identity steps for now.

- [ ] **Step 4: Run the tests to see them pass**

Run: `mix test test/girihelix/engine/tilings/construct_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/girihelix/engine/tilings/construct.ex test/girihelix/engine/tilings/construct_test.exs
git commit -m "feat: place and bind a tiling"
```

---

### Task 6: The unit merges, the weld and `construct`

**Files:**

- Modify: `lib/girihelix/engine/tilings/construct.ex`
- Modify: `test/girihelix/engine/tilings/construct_test.exs`

**Interfaces:**

- Produces:
  - `construct(Tiling.t(), binder(), [Point.t()]) :: {:ok, PlanarMap.t()} | {:error, reason()}`
  - `construct!(Tiling.t(), binder(), [Point.t()]) :: PlanarMap.t()`
  - `reason :: :degenerate_basis | :too_many_units | :inconsistent_order | {:figure_failed, Exception.t()}`

- [ ] **Step 1: Write the failing tests**

```elixir
test "construct merges one feature per placement and the periodic copies, then welds" do
  tiling = Catalogue.load!("4.5")
  binder = fn feature -> if feature.regular, do: Rosette.new!(feature.regular, 0.0, 3) end

  assert {:ok, map} = Construct.construct(tiling, binder, Construct.default_region(tiling))
  assert PlanarMap.verify(map) == :ok
  assert PlanarMap.num_vertices(map) > 0
  assert PlanarMap.num_edges(map) > 0
end

test "the stepped and plain paths agree" do
  tiling = Catalogue.load!("4.5")
  binder = fn feature -> if feature.regular, do: Rosette.new!(feature.regular, 0.0, 3) end

  stepped =
    tiling
    |> Construct.steps(binder, Construct.default_region(tiling))
    |> Steps.run!(Construct.start(tiling, binder, Construct.default_region(tiling)))
    |> Steps.final()
    |> Construct.result()

  assert stepped == Construct.construct(tiling, binder, Construct.default_region(tiling))
end

test "a degenerate lattice is a tuple error" do
  tiling = Tiling.new(name: "bad", t1: Point.new(1.0, 0.0), t2: Point.new(2.0, 0.0), features: [], placements: [])
  assert Construct.construct(tiling, fn _ -> nil end, Construct.default_region(tiling)) == {:error, :degenerate_basis}
end

test "a region taller than the row cap is too_many_units" do
  tiling = Tiling.new(name: "tall", t1: Point.new(1.0, 0.0), t2: Point.new(0.0, 1001.0), features: [], placements: [])
  assert Construct.construct(tiling, fn _ -> nil end, Construct.default_region(tiling)) == {:error, :too_many_units}
end

test "a raising binder is figure_failed, and the stepped path retains a failure frame" do
  tiling = Catalogue.load!("4.5")
  binder = fn _ -> raise ArgumentError, "star: degenerate_crossing" end

  assert {:error, {:figure_failed, %ArgumentError{}}} =
           Construct.construct(tiling, binder, Construct.default_region(tiling))

  assert {:error, %Steps.Failure{frames: frames}} =
           Steps.run(Construct.steps(tiling, binder, Construct.default_region(tiling)), Construct.start(tiling, binder, Construct.default_region(tiling)))

  assert frames != []
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix/engine/tilings/construct_test.exs`
Expected: FAIL, `construct/3` is undefined.

- [ ] **Step 3: Implement the remaining steps and the entry points**

`:units` maps each `{feature, figure}` to `PlanarMap.replicate(PlanarMap.new(), Figure.map(figure), Tiling.placements_for(tiling, feature.id))` and then `PlanarMap.replicate(PlanarMap.new(), unit, translations)`; record `:inconsistent_order` on an error. `:weld` folds `PlanarMap.weld/2` over the feature maps, recording `:inconsistent_order`. `result/1` returns the map with `{:ok, map}`, or the recorded `failure`. `construct/3` runs the steps with `Steps.run`; a recorded failure returns its atom, a `%Steps.Failure{exception: exception}` returns `{:error, {:figure_failed, exception}}`. `construct!/3` raises `ArgumentError` with the reason (re-raising the wrapped exception for `:figure_failed`).

- [ ] **Step 4: Run the tests to see them pass**

Run: `mix test test/girihelix/engine/tilings/construct_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/girihelix/engine/tilings/construct.ex test/girihelix/engine/tilings/construct_test.exs
git commit -m "feat: construct a tiling plus figures"
```

---

### Task 7: Harness construct operation and goldens

**Files:**

- Modify (local only): `reference/oracle/src/csk/taprats/geometry/HarnessDriver.java`
- Create (local only): `reference/oracle/scenarios/construct-*.ops`
- Modify: `test/support/taprats_harness.ex`
- Modify: `test/girihelix/taprats_harness_test.exs`
- Create: `test/girihelix/engine/tilings_golden_test.exs`

**Interfaces:**

- Produces `TapratsHarness`:
  - `@type op :: ... | {:construct, :map, String.t()}`
  - a `%{construct: canonical_map()}` dump shape
  - `canonical(PlanarMap.t()) :: canonical_map()` — sorted positions, edge position pairs and ring cycles
  - `compare/2` clause for the construct shape
- The Java `construct` op parses `construct map <tiling-name>`, reads `reference/1.1.12/tilings/<name>.tiling`, binds `Rosette(n, 0.0, 3)` to every regular feature, constructs the default region, and writes `construct ok` plus the map dump.

- [ ] **Step 1: Write the failing parser/harness test**

```elixir
test "parse_script/1 reads a construct op" do
  assert TapratsHarness.parse_script("construct map 4.5\n") == [{:construct, :map, "4.5"}]
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `mix test test/girihelix/taprats_harness_test.exs`
Expected: FAIL, `construct` is an unknown op.

- [ ] **Step 3: Add the Java operation and the Elixir canonical comparison**

In `HarnessDriver.java`, add a terminal `construct` branch that reads the tiling file, builds `new Prototype(tiling)`, calls `addElement` with `new DesignElement(feature, new Rosette(n, 0.0, 3))` for each regular feature, and constructs the region `Construct.default_region` (same formula: bounding box of the unit cell expanded by 1% of the larger generator). Extract the map dump as before. Create three scenarios: `construct-4.5`, `construct-6.5`, and `construct-mixed` (a file with both regular and polygon features, e.g. `4.5` already has both; use `4.5`, `6.5`, and `3-8-4-6`). Build and run the harness.

Implement `TapratsHarness.canonical/1`: vertices as `{x, y}` rounded to 12 decimals and sorted; edges as sorted pairs of endpoint positions; rings as sorted cycles normalised to their smallest position. `compare/2` for `%{construct: expected}` compares the canonical forms and reports the first differing component. Add the golden test module with `@moduletag :taprats` over the three scenarios.

- [ ] **Step 4: Run the goldens to see them pass**

Run: `mix test test/girihelix/engine/tilings_golden_test.exs`
Expected: PASS, or SKIP when the fixtures are absent.

- [ ] **Step 5: Commit**

```bash
git add test/support/taprats_harness.ex test/girihelix/taprats_harness_test.exs test/girihelix/engine/tilings_golden_test.exs
git commit -m "test: pin constructed tilings against Taprats"
```

---

### Task 8: The shared tiling helpers and the `catalogue` exhibit

**Files:**

- Create: `lib/girihelix_web/workbench/exhibits/tilings.ex`
- Create: `lib/girihelix_web/workbench/exhibits/catalogue.ex`
- Modify: `lib/girihelix_web/workbench/registry.ex`
- Test: `test/girihelix_web/workbench/exhibits/catalogue_test.exs`
- Modify: `test/girihelix_web/workbench/registry_test.exs` (category list)

**Interfaces:**

- Produces:
  - `GirihelixWeb.Workbench.Exhibits.Tilings`
    - `outline_ops(Tiling.t()) :: [Op.t()]` — one `{:polygon, points, :stroke, []}` per placement, plus a `{:label, ...}` with the name
    - `cell_ops([Transform.t()]) :: [Op.t()]` — the unit-cell guide and a small marker at each cell origin
    - `translation_ops(Tiling.t()) :: [Op.t()]` — guides for `t1` and `t2`
    - `rows(Tiling.t()) :: [{String.t(), String.t()}]` — name, t1, t2, features, placements
  - `GirihelixWeb.Workbench.Exhibits.Catalogue` implementing `Exhibit`, `slug/0 == "catalogue"`, `category/0 == :tilings`, no parameters, `draw/2` returning `{:panel, rows}`.

- [ ] **Step 1: Write the failing catalogue exhibit test**

```elixir
test "the catalogue exhibit lists every tiling and its counts" do
  params = Param.values(Catalogue.params(), :default)
  frames = Catalogue.steps(params) |> Steps.run!(Catalogue.initial(params))

  assert Catalogue.slug() == "catalogue"
  assert Catalogue.category() == :tilings

  assert {:panel, rows} = Catalogue.draw(List.last(frames), params)
  assert {"4.5", "3 features, 7 placements"} in rows
  assert length(rows) >= 60
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `mix test test/girihelix_web/workbench/exhibits/catalogue_test.exs`
Expected: FAIL, the modules are undefined.

- [ ] **Step 3: Implement the helper and the exhibit**

`Catalogue.initial/1` is the empty catalogue load state; `steps/1` is a single `:load` step that maps `Tilings.Catalogue.all/0` to rows. `draw/2` returns `{:panel, rows}`. Register `Catalogue` after the figures exhibits and update `registry_test.exs`'s grouped categories to `[:geometry, :figures, :tilings]`.

- [ ] **Step 4: Run the tests to see them pass**

Run: `mix test test/girihelix_web/workbench/exhibits/catalogue_test.exs test/girihelix_web/workbench/registry_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/girihelix_web/workbench/exhibits/tilings.ex lib/girihelix_web/workbench/exhibits/catalogue.ex lib/girihelix_web/workbench/registry.ex test/girihelix_web/workbench/exhibits/catalogue_test.exs test/girihelix_web/workbench/registry_test.exs
git commit -m "feat: add the tiling catalogue exhibit"
```

---

### Task 9: The `tiling` exhibit

**Files:**

- Create: `lib/girihelix_web/workbench/exhibits/tiling.ex`
- Modify: `lib/girihelix_web/workbench/registry.ex`
- Test: `test/girihelix_web/workbench/exhibits/tiling_test.exs`

**Interfaces:**

- `GirihelixWeb.Workbench.Exhibits.Tiling`, `slug/0 == "tiling"`, `category/0 == :tilings`.
- The exhibit module and the engine struct are both named `Tiling`; inside the exhibit alias the engine struct as `EngineTiling` (or `TilingModel`) to avoid the clash.
- Params: `tiling` enum over `Catalogue.name_options/0`, default `:"4.5"`.
- `initial/1` = `Construct.start(tiling, fn _ -> nil end, region)`; `steps/1` = `Construct.steps(...) |> Enum.take(1)` (the `:place` step).
- `draw/2` returns `{:both, ops, rows}`, where ops are `translation_ops ++ cell_ops ++ outline_ops` and rows are `Tilings.rows/1`.

- [ ] **Step 1: Write the failing test**

```elixir
test "the tiling exhibit draws vectors, outlines and cells" do
  params = Param.values(Tiling.params(), :default)
  frames = Tiling.steps(params) |> Steps.run!(Tiling.initial(params))

  assert Enum.map(Tiling.steps(params), & &1.id) == [:place]
  assert {:both, ops, rows} = Tiling.draw(List.last(frames), params)
  assert Enum.any?(ops, &match?({:polygon, _, _, _}, &1))
  assert Enum.any?(ops, &match?({:guide, _, _, _}, &1))
  assert {"4.5", _} = List.keyfind(rows, "name", 0)
end

test "frame zero draws the tiling's static guides" do
  params = Param.values(Tiling.params(), :default)
  first = Tiling.steps(params) |> Steps.run!(Tiling.initial(params)) |> hd()
  assert {:both, [_ | _], [_ | _]} = Tiling.draw(first, params)
end
```

- [ ] **Step 2: Run it to see it fail**

Run: `mix test test/girihelix_web/workbench/exhibits/tiling_test.exs`
Expected: FAIL, `Tiling` is undefined.

- [ ] **Step 3: Implement the exhibit and register it**

Use `Catalogue.load!/1` in `initial/1` (the catalogue is trusted local data) and `Construct.default_region/1`. The static ops draw the unit cell, the two vectors and every placed outline; the `:place` frame adds the cell markers. Register after `Catalogue`.

- [ ] **Step 4: Run the tests to see them pass**

Run: `mix test test/girihelix_web/workbench/exhibits/tiling_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/girihelix_web/workbench/exhibits/tiling.ex lib/girihelix_web/workbench/registry.ex test/girihelix_web/workbench/exhibits/tiling_test.exs
git commit -m "feat: add the tiling exhibit"
```

---

### Task 10: The `instancing` exhibit

**Files:**

- Create: `lib/girihelix_web/workbench/exhibits/instancing.ex`
- Modify: `lib/girihelix_web/workbench/registry.ex`
- Test: `test/girihelix_web/workbench/exhibits/instancing_test.exs`

**Interfaces:**

- `GirihelixWeb.Workbench.Exhibits.Instancing`, `slug/0 == "instancing"`, `category/0 == :tilings`.
- Params: `tiling` enum over `Catalogue.name_options/0` default `:"4.5"`; `figure` enum `[:rosette, :star, :none]` default `:rosette`.
- Binder: `:rosette` → `Rosette.new!(sides, 0.0, 3)`; `:star` → `Star.build!(sides, 3.0, 2)`; `:none` → `nil`.
- `initial/1` and `steps/1` use `Construct.start/3` and `Construct.steps/3`; `draw/2` draws `Tilings.translation_ops ++ Tilings.outline_ops` always, then the current `state.map` (if present), and returns rows including `verify` (`"n/a"` when the map is nil).

- [ ] **Step 1: Write the failing tests**

```elixir
test "the instancing exhibit constructs and reports verify" do
  params = Param.values(Instancing.params(), :default)
  last = Instancing.steps(params) |> Steps.run!(Instancing.initial(params)) |> List.last()

  assert Enum.map(Instancing.steps(params), & &1.id) == [:place, :bind, :units, :weld]
  assert {:both, ops, rows} = Instancing.draw(last, params)
  assert ops != []
  assert {"verify", "ok"} = List.keyfind(rows, "verify", 0)
end

test "an unbound run still draws the tiling guides" do
  params = %{Param.values(Instancing.params(), :default) | figure: :none}
  last = Instancing.steps(params) |> Steps.run!(Instancing.initial(params)) |> List.last()

  assert {:both, [_ | _], rows} = Instancing.draw(last, params)
  assert {"verify", "n/a"} = List.keyfind(rows, "verify", 0)
end

test "a triangle tiling in star mode is a failure frame, not a crash" do
  params = %{Param.values(Instancing.params(), :default) | tiling: :"3-8-12", figure: :star}

  assert {:error, %Steps.Failure{frames: frames}} =
           Steps.run(Instancing.steps(params), Instancing.initial(params))

  assert frames != []

  for frame <- frames do
    assert {:both, [_ | _], [_ | _]} = Instancing.draw(frame, params)
  end
end
```

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/girihelix_web/workbench/exhibits/instancing_test.exs`
Expected: FAIL, `Instancing` is undefined.

- [ ] **Step 3: Implement the exhibit and register it**

Build the binder from `params.figure` and `feature.regular`; `Star.build!/3` is deliberately the unchecked constructor so the failure occurs in `Figure.map` inside the `:units` step. Draw the static tiling guides before the constructed map so frame zero and unbound runs are non-empty. Register after `Tiling`.

- [ ] **Step 4: Run the tests and the registry property test**

Run: `mix test test/girihelix_web/workbench/`
Expected: PASS, including every exhibit at defaults and extremes.

- [ ] **Step 5: Commit**

```bash
git add lib/girihelix_web/workbench/exhibits/instancing.ex lib/girihelix_web/workbench/registry.ex test/girihelix_web/workbench/exhibits/instancing_test.exs
git commit -m "feat: add the instancing exhibit"
```

---

### Task 11: Homogenisation and gates

**Files:**

- Modify: `docs/superpowers/specs/2026-10-22-girihelix-catalogue-instancing-design.md` (status)
- Modify: `docs/superpowers/specs/2026-10-16-girihelix-workbench-design.md` (Plan 4 row)
- Modify: `docs/backlog.md` if the work discovers anything
- The new engine and exhibit modules (doc/comment notes only)

- [ ] **Step 1: Record the implementation decisions**

Change the design's status to "implemented 2026-10-22 (Plan 4)". Mark the workbench plan series row 4 done and update the status line to "Plans 2, 3 and 4 implemented".

- [ ] **Step 2: Record the flaws at one named function each**

Add a one-line note and a named test for: the unit-cell boundary floor (`Construct.default_region/1`), the two legacy-encoded descriptions (`Parser`/`Catalogue`), the unbound-feature skip (`Construct`), and the canonical-order divergence (`TapratsHarness.canonical/1`). Do not fix any of them.

- [ ] **Step 3: Strip source narration and lint**

Run the project's narration grep over `lib/girihelix/engine/tilings` and `lib/girihelix_web/workbench/exhibits`; restate hits as decisions. Run `markdownlint-cli2 --config ~/.markdownlint-cli2.jsonc` on the changed docs.

- [ ] **Step 4: Run the full gate**

Run: `mix precommit`
Expected: dialyzer `Total errors: 0`, all tests pass, coverage does not fall.

- [ ] **Step 5: Commit**

```bash
git add docs lib/girihelix/engine/tilings lib/girihelix_web/workbench
git commit -m "docs: record the Plan 4 catalogue decisions"
```

## Task order and dependencies

1. Task 1 — no dependency.
2. Task 2 — needs Task 1.
3. Task 3 — needs Tasks 1 and 2.
4. Task 4 — needs Task 3.
5. Task 5 — needs Task 4.
6. Task 6 — needs Task 5.
7. Task 7 — needs Tasks 4 and 6.
8. Task 8 — needs Task 4.
9. Task 9 — needs Tasks 5 and 8.
10. Task 10 — needs Tasks 6 and 8.
11. Task 11 — needs everything.

Tasks 8, 9 and 10 share `registry.ex` and the workbench test tree; serialise them. Task 7 modifies the golden test file and the harness; it can run in parallel with Tasks 8–10 once Task 6 is done.

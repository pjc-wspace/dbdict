---
created: 2026-07-25T12:42:43+12:00
title: julia codegen and duckdb driver insights
tags: [julia, duckdb, rust, pattern, gotcha, adversarial-review]
source: "/state save"
---

## planning-stage sourcing for external-tool facts

- The goal deliberately pushes two things to the *planning* stage rather
  than asserting them now: the DuckDB-type → Julia-type mapping table, and
  whether a local Julia toolchain exists for round-trip tests. Both are
  external-tool facts that need sourcing from DuckDB.jl docs, not memory —
  nested types (structs/arrays/enums) are exactly where Julia DB drivers
  tend to have gaps.
- The round-trip success criterion mirrors dbdict's own validation
  philosophy: the dict round-trips through an in-memory DuckDB for type
  fidelity, so generated Julia code proving itself by round-tripping real
  data through a real DuckDB file is the same idea one level up.

## mapping entries are conversion pairs, not type names

- Because the driver layer is fixed, every mapping entry is really a
  *conversion pair* (to-Julia on read, to-DuckDB on write), not just a
  type name. An entry that names a non-driver-native type also implies a
  Julia package dependency (`using CategoricalArrays`), so the mapping
  format needs a slot for that — this is the detail that makes "just a
  type name in a config file" insufficient.
- The identity mapping (accept whatever DuckDB.jl produces) is always
  valid and round-trip-safe by construction. Overrides are purely additive
  risk — each one needs its inverse to actually round-trip, which is
  testable per-entry.

## typedefs vs per-column overrides (superseded by companion files)

- The reason per-column overrides must exist at all: type-keyed mappings
  can't distinguish two columns that share a DuckDB type — `DECIMAL(18,4)`
  as money vs. as a coordinate. Typedefs *look* like the fix because they
  carry that semantic distinction, but using them would couple the schema
  layer to one generator. Column-level override gets the same
  expressiveness without the coupling.
- One consequence for the core crate: the `Column` struct (`model.rs:160`)
  would grow an optional, generator-namespaced field that core itself
  never interprets — it just parses, span-tracks, and passes it through.
  Core stays generator-agnostic; only `dbdict-julia` reads the `julia:`
  block.

## companion files invert the language dependency

- The companion file inverts the dependency I had wrong earlier: instead
  of the dict knowing about languages, each language file knows about the
  dict. That means companion files are *validatable against* the dict — an
  entry naming a typedef or column that doesn't exist is a span-aware
  diagnostic, same machinery as everything else. Typos in mapping files
  get caught, which matters for a hand-edited format.
- Typedef-keyed struct mappings quietly require typedef *provenance* to
  survive into the generator — the model already supports this since
  `Column.col_type` holds the raw string (`money`, not `DECIMAL(18,4)`),
  with expansion happening later. Worth confirming in planning that
  nothing on the generator path pre-expands it.

## closed-world type-name resolution

- This gives the companion file a clean closed-world resolution rule:
  every type name used as a mapping value must resolve to one of (a) a
  builtin the generator knows (Base/stdlib — `Float64`, `String`), (b) a
  `typedecl` entry, or (c) a struct generated from a dict typedef
  (`Address`). Anything else is a span-aware diagnostic — "unknown type
  `FixedDecmal`, did you mean the typedecl `FixedDecimal`?" The same
  three-way resolution works untouched for Python (`builtins` / `import` /
  generated dataclass) and Rust.
- Note what does *not* need a typedecl: generated struct types.
  `address: Address` needs no declaration because the generator itself
  defines `Address` — the decl section is only for types whose definition
  lives in an external package. Keeping that boundary crisp stops the
  section from becoming a dumping ground.

## type-keyed column scope reaches inside nested types

- Keying by *type* even at column scope (rather than "column → julia
  type" directly) looks redundant — a column has one type — but it's
  quietly the right call for nested types: a column of `LIST(DECIMAL(18,4))`
  with a column-scoped `decimal: Float64` entry remaps the *element* type
  inside the list. A flat "column → type" override could never reach
  inside a LIST or STRUCT. Your sketch gets recursive remapping for free.
- The scope chain (column > table > global > built-in defaults) is the
  same shadowing model the dict already uses for typedefs (table-scoped
  typedefs shadow global ones, `model.rs:132`), so the two files feel like
  one system.

## file extensions are a bet on who consumes them

- A bare custom extension is a bet that your files are mostly consumed by
  *your own tool*, which can afford to know them; a double extension is a
  bet that generic tooling matters more. For a practical single-maintainer
  tool where `dbdict` itself does the validating, the bare extension is
  defensible — the `.gitattributes` line and two editor associations are
  one-time costs.

## flatten-and-reassemble moves struct assembly to the working layer

- The reason this works when direct struct writing doesn't: DuckDB.jl's
  binding layer is missing struct *value conversion*, but DuckDB itself
  constructs structs natively in SQL. Flattening moves the struct assembly
  from the broken layer (Julia→C bindings) to the working one (SQL engine)
  — and StructArray's struct-of-arrays layout means the flattened form
  already exists; no per-row work in Julia at all.
- One boundary found: a field that is itself a LIST can't be registered
  (same binding gap), so structs containing lists stay on the literal-SQL
  path. The writer strategy in the plan is now three tiers: appender →
  flatten+reassemble → literals.

## canonicalize-before-parse keeps the type parser small

- The pipeline that exists: raw dict string → scratch-DuckDB instantiation
  → canonical spelling (`DESCRIBE`'s output, machine-regular: "ENUM('buy',
  'sell') always has the space after the comma") → `parse_type` → typed
  tree. Canonicalizing *before* parsing is what keeps the parser small —
  it never sees user spelling variance (`decimal(18,4)`, `NUMERIC`, odd
  whitespace), because the engine normalizes all of that first. That's
  also exactly the normalization the companion-file keyspace needs:
  canonicalize mapping keys through the same path and `DECIMAL(18,4)` vs
  `decimal(18, 4)` match for free.
- The one real problem: `types.rs` lives in `dbdict-dummy-data-duckdb` — a
  *generator* crate — and the architecture rule says generators never
  depend on each other. So `dbdict-julia` can't reach it where it is today.

## golden tests verify stability, not correctness

- The general trap here: golden-file tests verify the *stability* of
  output, not its *correctness*. They're the right tool for "did my
  refactor change emission unexpectedly" and the wrong tool for "does the
  emission work" — a generator test suite needs one of each, and the live
  test is deliberately tiny because the golden tests carry the breadth.

## supported-type list as falsifiable contract and fixture

- This converts a marketing sentence into a falsifiable contract *and* a
  regression fixture: the supported list in goal.md and the round-trip
  harness's type matrix become the same list, so "is the goal met" is
  answerable by running the tests. The diagnostic side matters as much as
  the supported side — a user with an INTERVAL column gets told at
  generation time, not via a MethodError deep in generated code at
  runtime.

## a config file earns its existence through contingency

- The general rule this instance teaches: a config file earns its
  existence when its contents are *contingent* — things a user might
  legitimately want different. The driver-native mapping isn't contingent,
  it's discovered fact; encoding facts as config invites someone to
  "configure" them wrong. The companion file stays; the defaults file was
  config-shaped code and dies.

## asymmetric conversion contracts halve the user's burden

- The load-bearing move here is *asymmetry*: reads need a named conversion
  point (constructor), writes don't (structural serialization).
  Recognizing that write-side can be duck-typed — fitting, for DuckDB —
  halves the contract surface a user must implement for a custom type.

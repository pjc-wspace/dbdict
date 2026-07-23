# implementation: julia read/write codegen

> workflow notes (from memory/goal):
> - /code-review at every phase boundary (standing mandate)
> - context budget: don't start a phase at ≥25% context — /ws pause, fresh
>   session, /state load instead
> - phases 5–6 are expected to be *revised* after the phase 1 spike lands;
>   impl.md is a living document

## phases

### phase 1: spike — verify DuckDB.jl capabilities (no production code)

goal constraint: "planning-stage verifications (do not assume)". everything
downstream of emission design depends on these answers, so they come first
and produce a findings note, not code.

- [ ] scratch Julia project env (in session dir `spike/`, not the repo root):
      add DuckDB, DataFrames, StructArrays, FixedPointDecimals
- [ ] read path: build an in-memory DuckDB table exercising DECIMAL, ENUM,
      STRUCT, LIST, ARRAY, MAP, UUID, TIMESTAMP, HUGEINT, BLOB; query via
      DBInterface; record the *actual* Julia column types (confirms the
      result.jl-derived table from the goal discussion)
- [ ] write path: for the same type matrix, try (a) appender API,
      (b) `register_data_frame` + `INSERT INTO ... SELECT`, (c) plain
      prepared INSERT; record which paths handle which types
- [ ] StructArrays: NamedTuple vector → StructArray; does it work as a
      DataFrame column; does it survive the write path
- [ ] DuckDB version check: bundled Rust duckdb is 1.5.4, DuckDB.jl pins
      DuckDB_jll 1.5.3 — confirm a .duckdb file written by one opens in the
      other (storage-format compatibility)
- [ ] findings → `.claude-work/notes/{stamp}-duckdb-jl-capability-spike.md`
- **verify:** findings note answers all four goal-listed verifications;
  phases 5–6 reviewed against it and adjusted

> decision deferred to this spike: which write path the generated writer
> uses; whether the StructArrays container option ships this session

### phase 2: file naming & discovery

self-contained, no dependency on the spike; lands the convention early so
later phases emit/consume the new names.

- [ ] `crates/dbdict-cli/src/main.rs` (`resolve` logic around :245): directory
      discovery becomes: glob `*.dbdict.yaml` — one match → use it; several →
      error listing them, require explicit path; none → fall back to
      `dbdict.yaml`, then legacy `data-dict.yaml`
- [ ] extension helpers (stem extraction for companion pairing:
      `sales.dbdict.yaml` → stem `sales`, companion `sales.dbdict-jlmap.yaml`)
      — placed in core so generators reuse them, CLI stays thin
- [ ] update CLI help text + root CLAUDE.md / README mentions of `dbdict.yaml`
- [ ] tests: one-match, multi-match, fallback, explicit-path cases (extend
      existing discovery tests at `main.rs:721-778`)
- **verify:** `cargo test --workspace` green; manual: `dbdict validate` in a
  dir with one/two/zero `*.dbdict.yaml` files behaves per the rule

### phase 3: companion-file model in core

the language-generic half of the companion design. lives in `crates/dbdict`
(new module, e.g. `src/companion.rs`); generators consume the model, core
never interprets language-specific type names.

- [ ] model types (all `Spanned`, mirroring `model.rs` style):
      `TypeDeclaration { name, using: Option }`,
      `TypeMappings { global, tables { mappings, columns } }` — keys are one
      keyspace (typedef name or DuckDB type, distinguished at resolution)
- [ ] parse via the existing source-mapped YAML infra (same diagnostics
      engine; new problem codes for companion-file errors)
- [ ] cross-validation against the dict: mapping keys naming unknown
      typedefs/tables/columns → span-aware diagnostics
- [ ] precedence resolution: (column, typedef-provenance, duckdb type) →
      resolved mapping value, specificity: column > table > global scope;
      within a scope typedef name > exact parameterized type > base type;
      recursive descent into LIST/STRUCT element types
- [ ] confirm typedef provenance survives to the generator path
      (`Column.col_type` holds the raw string — verify nothing pre-expands
      it before generators see it)
- **verify:** core unit tests: parse, each diagnostic, precedence table
  (incl. nested element remap); `cargo test --workspace` green

### phase 4: dbdict-julia crate skeleton + built-in defaults

- [ ] new crate `crates/dbdict-julia` mirroring `dbdict-ddl` (lib.rs, dep on
      `dbdict` core only; workspace member)
- [ ] built-in defaults as a data file in companion-file format, compiled in
      via `include_str!`, parsed through the phase-3 parser — the
      DuckDB.jl-native table as confirmed by the phase-1 spike
- [ ] closed-world type-name check: julia builtin list + `type_declarations`
      + generated struct names; unknown name → diagnostic with
      did-you-mean
- [ ] end-to-end resolution: dict + optional companion + defaults → concrete
      per-table/per-column Julia type plan (pure data, no emission yet)
- **verify:** unit tests: defaults-only resolution, companion overrides at
  each scope, closed-world rejections; `cargo test --workspace` green

### phase 5: emission — primitives + CLI subcommand

- [ ] emit reader (`read_{table}(con) -> DataFrame`) and writer
      (`write_{table}(con, df)`) per table, primitive types only; write path
      per the spike decision
- [ ] emitted style: plain Julia, training-wheels comments (maintainer is a
      julia novice) — same philosophy as the Rust side
- [ ] CLI subcommand `dbdict gen julia [dict]` — `gen` is the namespace for
      target-language codegen (open set: julia, python, rust …); `ddl` stays
      flat because DuckDB is its only possible target. mirrors `run_ddl`
      (`main.rs:355`) and the shared front half (`main.rs:302`); companion
      file discovered by stem pairing, optional
- [ ] golden-file tests mirroring `dbdict-ddl/tests/generate.rs`
- **verify:** `cargo test --workspace` green; manual: `julia` runs an emitted
  file against a real .duckdb without error

### phase 6: emission — nested types & conversions

shaped by phase-1 findings; expect revision.

- [ ] generated named Julia structs from struct typedefs (`address` →
      `struct Address`), NamedTuple↔struct conversion in reader/writer
- [ ] LIST/ARRAY recursion with remapped element types
- [ ] `type_declarations` → emitted `using` lines (only for entries with
      `using:`; user-declared types assumed in scope)
- [ ] one or two proven conversion-pair overrides as worked examples
      (e.g. DECIMAL → Float64) — nothing shipped unverified
- [ ] StructArrays container opt-in for struct columns, *if* the spike
      verified it; otherwise record as follow-up
- **verify:** golden tests extended to the nested matrix;
  `cargo test --workspace` green

### phase 7: round-trip integration test + docs

- [ ] round-trip harness: test fixture dict covering the full type matrix →
      emit Julia → run `julia` (1.12.6 via juliaup, confirmed on PATH)
      writing a DataFrame through the generated writer and reading it back →
      compare values and types
- [ ] harness lives as a Rust integration test in `dbdict-julia/tests/`,
      skipping with a clear message when `julia` is absent (keeps
      `cargo test --workspace` green on julia-less machines)
- [ ] docs: companion-file format reference (sections, precedence, worked
      example) + README/CLAUDE.md updates
- **verify:** round-trip test passes locally; full workspace suite green;
  clippy 0 warnings; fmt clean

> session close criterion: all goal success criteria checked off against
> goal.md, then /ws close

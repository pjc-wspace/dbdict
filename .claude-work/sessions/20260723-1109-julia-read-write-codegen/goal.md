# julia read/write codegen

> ## ⚠ SUPERSEDED — historical record, 2026-08-04
>
> **Everything below this banner is the July 2026 intent, kept verbatim and
> uncorrected. Do not use it as the starting point for future codegen work.**
> The 0.3.0 re-baseline removed most of its premises, and the maintainer's
> assessment is that the goals themselves were wrong — not merely stale. It is
> preserved rather than rewritten so that what was tried, and why it was
> dropped, stays legible.
>
> **What 0.3.0 V1 removes** (canonical scope:
> [`docs/vision-direction-0.3.0.md`](../../../docs/vision-direction-0.3.0.md)):
>
> - **the per-language companion mapping file** — `DBNAME.dbdict-jlmap.yaml`,
>   `type_declarations:`, scoped `type_mappings:`, the specificity ordering and
>   the closed-world rule. This is the document's central design and §7 deletes
>   it outright: the type mapping follows from the (target database, driver)
>   pair, so naming the driver is sufficient and no mapping file is needed
> - **the built-in defaults table** — `DECIMAL→FixedDecimal`, `ENUM→String`,
>   `STRUCT→NamedTuple`, `LIST→Vector`. All four of those types are out of V1
> - **struct typedefs → generated named Julia structs** — no compound types in
>   V1, and §11 records that their return will be a (target × language)
>   pairing rather than dbdict type entries
> - **"all dict-expressible types supported on every path"** — V1 is ten
>   scalars
> - **DuckDB.jl as *the* driver, and a dedicated CLI subcommand** — targets are
>   now `duckdb`/`ducklake`/`sqlite`/`hdf5`, drivers are named per language in
>   a `languages:` section, and generation is `dbdict gen <NAME>`
>
> **What survives** is the deliverable shape, not the design: a bulk/row ×
> read/write API surface, a round-trip test against a real database, the
> plain-Julia-for-a-novice constraint, and the rule that a generator crate
> consumes the resolved model only.
>
> **This session's durable output is not this file.** It is the phase 1
> capability spike (`spike/`), the driver reference it gated
> (`research/duckdb-driver-jl/reference.md`), and the 15-finding adversarial
> review ledger (`review-decisions.md`). Note also `__on-hold__.md`, which
> recorded *before* 0.3.0 that this file was already stale against
> `review-decisions.md`.

## problem

dbdict describes tables in DuckDB-native types, but the only model consumers
so far are Rust-side (validation, DDL, dummy data). The project's stated
direction is language codegen; Julia is the first target. A Julia user should
be able to read and write dict-described DuckDB tables with correct types
without hand-writing boilerplate or re-deriving the schema.

Julia is not the only future target (Python next, probably Rust), so the
type-mapping design must be language-general: the dict stays a pure database
description, and each target language gets its own companion mapping file.

## success criteria

- new generator crate `crates/dbdict-julia` that consumes `load_and_lower`
  and emits Julia source files — never touches YAML parsing beyond the
  companion file, the CLI, or other generator crates (per the architecture
  rule in CLAUDE.md)
- **file naming convention**: dict files are `DBNAME.dbdict.yaml`; companion
  mapping files are `DBNAME.dbdict-jlmap.yaml` (future: `-pymap`, `-rsmap`).
  The trailing `.yaml` keeps automatic YAML treatment in editors and tooling;
  the shared `DBNAME` stem pairs dict and companions deterministically.
  Directory discovery becomes a glob: one `*.dbdict.yaml` match → use it;
  several → require an explicit path argument. `dbdict.yaml` and legacy
  `data-dict.yaml` remain as fallbacks so existing files keep working
- **companion mapping file** (`DBNAME.dbdict-jlmap.yaml`, next to the dict)
  with:
  - `type_declarations:` — target-language types used in mappings: name plus
    optional `using:` (third-party package); no `using:` means a user-defined
    type assumed in scope. Closed-world rule: every type name used in a
    mapping must resolve to a known builtin, a `type_declarations` entry, or
    a struct generated from a dict typedef — anything else is a diagnostic
  - `type_mappings:` — scoped sections `global:` / `tables:` /
    `columns:` (column > table > global > built-in defaults). Keys are
    DuckDB types **or** dict typedef names in one keyspace; specificity
    order within a scope: typedef name > exact parameterized type > base
    type. Type-keyed entries apply recursively inside nested types
    (LIST/STRUCT elements)
  - companion entries are validated against the dict (unknown typedef or
    column names get span-aware diagnostics, same engine as the dict)
- **built-in defaults** compiled into the crate as a data file in the same
  format — the DuckDB.jl-native mapping (DECIMAL→FixedDecimal, ENUM→String,
  STRUCT→NamedTuple, LIST→Vector, …) sourced from DuckDB.jl's result
  conversion code; companion files state only deviations
- generated Julia code uses DuckDB.jl + DataFrames.jl: for each table in the
  dict, a bulk/row × read/write API surface:
  - **bulk read** — whole table → typed DataFrame
  - **bulk write** — replace and append from a DataFrame (columnar write
    strategy; StructArray-backed struct columns exploited when present)
  - **row read** — fetch by primary key
  - **row write** — insert; update and delete by primary key
  - row read/update/delete are emitted only for tables declaring
    `constraints: [primary_key]`, with a clear diagnostic explaining the
    omission otherwise; all dict-expressible types supported on every path
    (fixed-size ARRAY excepted — diagnostic until DuckDB.jl ships support)
- struct typedefs can map to *generated named Julia structs* (typedef
  `address` → generated `Address` + NamedTuple↔struct conversion)
- a CLI subcommand exposing the generator (shape mirrors the existing DDL
  subcommand)
- generated code round-trips: write a DataFrame through generated writer,
  read it back through generated reader, values and types survive — verified
  by an automated test that runs the generated Julia against a real DuckDB
  file
- `cargo test --workspace` stays green; new crate has its own tests for
  emission (golden-file style, mirroring how dbdict-ddl tests if applicable)

## scope

- in: `crates/dbdict-julia` generator crate; companion-file model
  (`type_declarations` + scoped `type_mappings`) with the generic parts
  designed for reuse by future language generators; Julia emission for
  read/write; DuckDB.jl/DataFrames.jl target; CLI subcommand; tests;
  `DBNAME.dbdict.yaml` naming convention and glob-based discovery (with
  legacy-name fallbacks)
- out: validation logic in generated Julia (enums/uniqueness/constraints stay
  in Rust — possible later session); Python codegen (the companion-file
  *format* is designed for it, but no Python emission); parquet/CSV targets;
  anything vscode/LSP related (dropped from project goals for now); publishing
  a Julia package (emitted source only, not a registered package)

## constraints

- maintainer is a Julia novice — generated code and its docs should be plain,
  idiomatic-but-simple Julia with comments; same training-wheels philosophy
  as the Rust side
- generator crate architecture rule: consume the resolved model from
  `dbdict` core only; the dict (`dbdict.yaml`) must not grow any
  language-specific keys — all Julia concerns live in the companion file
- the driver layer is fixed: DuckDB.jl decides what query results arrive as
  (verified from its result.jl source); mappings beyond driver-native types
  are conversion pairs (to-Julia on read, inverse on write), and each shipped
  override must pass the round-trip test — start with driver-native defaults
  plus one or two proven override pairs, not a big untested catalog
- planning-stage verifications (do not assume): DuckDB.jl writer-path support
  for nested types (appender vs register_data_frame vs INSERT); StructArrays
  as DataFrame columns and on the write path (container choice: DataFrame
  default, StructArrays opt-in for struct columns); whether typedef
  provenance survives the generator path un-expanded (needed for
  typedef-keyed mappings); how strict rich-schema validation is about the
  companion file's own errors
- round-trip testing needs a local Julia toolchain; availability/version to
  confirm during planning (may gate CI-style automation vs manual verify)

# dbdict

A **dataspec** tool: one YAML file describes a dataset's tables and columns, and
drives generation in both directions — DDL and client code out of the spec, a
draft spec back out of a database that already exists. Forked from tidyverse
`data-dict`; not tracking upstream.

**Read `docs/vision-direction-0.3.0.md` before doing design work on this repo.**
It is the canonical statement of what dbdict is and what 0.3.0's V1 covers, and
nothing in this file restates it — sections are referenced by number instead.

## Where the project is

0.3.0 is a re-baseline, documents first. Two consequences that matter on almost
every task here:

- **`crates/` still implements the 0.2.0 type system.** DuckDB-native types
  behind `typedef:`, one DuckDB database per dict. Where code and documents
  disagree — `decimal(p,s)` and `timestamptz` are the known case — that is a
  recorded debt (direction doc §11), not a bug to fix on sight. Check the
  direction document before "correcting" either side.
- **`cross-backend portability` is now a goal, not a non-goal.** This inverts
  the 0.2.0 stance, which said the fork was "not aiming for cross-backend
  portability. DuckDB-first". V1 targets are `duckdb`, `ducklake`, `sqlite` and
  `hdf5`; `postgres` is V2. The 0.2.0 documents are archived verbatim under
  `docs/v0.2.0/`.

The legacy upstream path (`data-dict.yaml`, coarse semantic types + parquet)
still validates and is kept working.

## Architecture

Workspace of library crates + a thin CLI. The core (`dbdict`) is a pure library
exposing the parsed/resolved dictionary model; the CLI and the generators are
separate crates that consume that model — they never touch YAML or each other.

- `crates/dbdict` — core: model, source-mapped YAML parse, typedef resolution,
  validation engine, diagnostics. No DuckDB dependency
- `crates/dbdict-duckdb` — DuckDB backend (native bundled `duckdb` crate)
- `crates/dbdict-ddl` — DDL generator over the lowered model
- `crates/dbdict-dummy-data` — backend-neutral dummy-data generation
- `crates/dbdict-dummy-data-duckdb` — its DuckDB half. Note: the `dummy`
  feature is not shipping in 0.3.0 (direction doc §11)
- `crates/dbdict-parquet` — parquet backend (legacy path)
- `crates/dbdict-cli` — thin CLI (binary: `dbdict`)

Per the direction document, each storage target gets its own module/crate, and
codegen is an add-in selected by target language.

## Coding conventions

- **The maintainer is learning Rust.** Write "training-wheels" comments: thorough
  but concise, explaining the *why* and any Rust idiom or gotcha in play
- lowercase comments; no trailing period on end-of-line comments
- **no fancy/clever Rust** — keep it explicit and readable (avoid dense iterator
  chains, macro tricks, and lifetime gymnastics when a plain version is clearer)
- optimize for readability and maintenance / feature-addition cost over execution
  speed
- follow `rustfmt` defaults

## Build / test

- `cargo build --workspace` / `cargo test --workspace`
- DuckDB is bundled (native, v1.5.4 — `duckdb` crate `1.10504.0`, see
  `Cargo.lock`), so the current test suite runs entirely in-process: no runtime
  `duckdb` on PATH is needed by the library, the CLI, or the tests. The first
  build compiles the bundled DuckDB (multi-minute); later builds are cached.
- **That guarantee is per target from 0.3.0 onward, not global.** It holds for
  `duckdb`, `sqlite` and `hdf5`; for `ducklake` it depends on which catalog
  database is in use; for `postgres` (V2) it fails outright, so those tests will
  need a live server. The evidence per target is the capability matrix in
  direction doc §10 — do not promise in-process behaviour for a new backend
  without checking that row first.

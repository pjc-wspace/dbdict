# dbdict

> **Status — 0.3.0 re-baseline in progress.** The positioning below is the
> settled design; the code has not caught up to it yet. What builds and runs
> today is described below, under **what runs today**.
> [`docs/vision-direction-0.3.0.md`](docs/vision-direction-0.3.0.md) is the
> canonical statement of scope — where it and this README differ, it wins.

`dbdict` describes a dataset in one YAML file — a **dataspec** — and uses that
file to produce the things normally hand-written around a dataset: the DDL that
creates the store, the client code that reads and writes it, and the checks that
say the store and the spec still agree. Two ways in, both first-class: author
the spec up front, or draft it from a database that already holds data.

> This repository is a fork of
> [tidyverse/data-dict](https://github.com/tidyverse/data-dict) (MIT). It does
> not track upstream. The fork's original stance — DuckDB-first, portability
> across backends explicitly not a goal — is **reversed** as of 0.3.0: several
> storage targets, and a type vocabulary that belongs to none of them, are what
> the design now turns on. The reasoning is in
> [§3 of the direction document](docs/vision-direction-0.3.0.md).

## What V1 of 0.3.0 covers

Deliberately small. The full argument for each line is in the direction
document; this is the shape of it.

* **Ten scalar types** — `bool`, `int8`, `int16`, `int32`, `int64`, `float32`,
  `float64`, `string`, `date`, `timestamp` — defined by bit layout (numerics) or
  by a pinned RFC profile (temporals), and mapped per target rather than
  borrowed from any one of them.
  ([§5](docs/vision-direction-0.3.0.md))
* **Four storage targets** — `duckdb`, `ducklake`, `sqlite`, `hdf5`. What each
  can and cannot do is a matrix, not a footnote.
  ([§10](docs/vision-direction-0.3.0.md))
* **Named language targets** — a `languages:` section names a driver per
  language; the type mapping follows from the (target, driver) pair rather than
  from a file anyone maintains.
  ([§7](docs/vision-direction-0.3.0.md))
* **Tables only.**

Out of V1, and named as such rather than left to be discovered
([§11](docs/vision-direction-0.3.0.md)):

* no compound types — no `STRUCT`, `LIST`, `ARRAY`, `MAP`, `UNION`, `ENUM`
* no `decimal(p,s)` — V2 at the earliest; `timestamptz` is gone for good
* no `postgres` — V2; it is the one target that cannot run in-process
* no views — V2
* the `dummy` command will not survive the internal changes 0.3.0 needs, and
  will not ship in it

## What runs today

The code in `crates/` is the **0.2.0** tool: one `dbdict.yaml` per DuckDB
database, columns typed in DuckDB's own type system behind a `typedef:` alias
layer, no other target. Tag `v0.2.0` (`ab468fa`) is the last commit before the
direction changed, and the documents as they stood there are kept verbatim in
[`docs/v0.2.0/`](docs/v0.2.0/) with an
[archive note](docs/v0.2.0/README-archive-note.md) saying what in them was
already wrong.

```yaml
$version: "0.2.0"
typedef:
  money: DECIMAL(18, 4)
  address: STRUCT(city VARCHAR, postcode INTEGER)
source:
  duckdb:
    file: warehouse.duckdb
tables:
  - name: trades
    columns:
      - name: qty
        type: BIGINT
      - name: price
        type: money
```

Validation round-trips the dictionary through a scratch in-memory DuckDB and
compares `DESCRIBE` output against the real database, so type checking is exact
— struct fields, enum values, decimal precision, array sizes — with source-span
diagnostics pointing back into the YAML. The legacy upstream format
(`data-dict.yaml`, `$version: "0.1.0"`: coarse semantic types validated against
per-table Parquet files) still validates too, so existing files keep working.

**The 0.2.0 type system outlives the 0.2.0 documents.** `decimal(p,s)` and
`timestamptz` are out of the V1 vocabulary above but are still implemented in
`crates/` — a debt recorded on purpose rather than left silent, and named with
its extent in [§11](docs/vision-direction-0.3.0.md).

## The CLI

This is the **0.2.0** command surface — what the binary does now. V1 of 0.3.0
reshapes it around `validate` / `draft` / `ddl` / `gen` / `resolve`
([§9](docs/vision-direction-0.3.0.md)); until then the commands below are what
exists.

```
Usage: dbdict <COMMAND>

Commands:
  validate-spec  Validate a dbdict.yaml file or directory against the spec [default: .]
  validate-meta  Validate a dataset's column names and types against a data dictionary
  validate-data  Validate a dataset's values against a data dictionary
  resolve        Print each typedef's canonical DuckDB expansion [default: .]
  ddl            Print executable DuckDB DDL generated from a data dictionary [default: .]
  dummy          Generate a DuckDB database of dummy data from a data dictionary [default: .]
  spec           Print the dbdict.yaml specification
  types parquet  Print column types for a parquet file
  types duckdb   Print every table's column types from a DuckDB database
  skill read     Skill for reading and understanding a data dictionary
  skill write    Skill for creating or updating a data dictionary
  help           Print this message or the help of the given subcommand(s)
```

* `validate-spec` checks that a file is structurally valid and internally
  consistent. Pass a file, or a directory containing a `dbdict.yaml` (falls back
  to the legacy `data-dict.yaml` name; defaults to the current directory).
* `validate-meta` compares a dictionary against its database's column names and
  types; `validate-data` also checks values — nulls in `required` columns (D01),
  duplicated `primary_key` values (D02), duplicated values in `unique` columns
  (D03), orphaned `foreign_key` values (D04), and relationship `cardinality`
  violations (D05). The data is located through the dictionary's `source`, so
  only the dictionary is passed.
* `resolve` expands every `typedef:` alias to its canonical DuckDB spelling —
  useful while authoring, and for seeing exactly what validation compares. (A
  legacy dictionary has no typedefs, so it resolves to nothing.)
* `ddl` generates an executable DuckDB script from a rich dictionary —
  `CREATE TYPE` per typedef in dependency order, then `CREATE TABLE` per table —
  proven runnable against a scratch in-memory DuckDB before it is printed.
  Constraints are deliberately *not* emitted as `PRIMARY KEY` / `NOT NULL` /
  `UNIQUE` clauses: generated schemas exist mostly to be bulk-loaded, and the
  [DuckDB performance guide](https://duckdb.org/docs/current/guides/performance/schema.html)
  advises "For best bulk load performance, avoid primary key constraints".
  Load the data, then run `validate-data` — the constraints are checked by
  query, after the fact.
* `dummy` writes a DuckDB database of type- and constraint-correct dummy data to
  a required `--out` file (never the dictionary's own `source`, and never over
  an existing file without `--force`). Every generated database passes
  `validate-data`. Values are correct rather than realistic — no names,
  addresses, or distributions. See `dbdict dummy --help` for row counts, seeding
  and null fraction. **Not shipping in 0.3.0** (see above).
* `types duckdb` / `types parquet` print the column types of a data source.
* `skill read` / `skill write` print embedded agent skills for working with data
  dictionaries, and `spec` prints the full specification.

DuckDB is bundled into the binary (native, in-process): nothing needs to be
installed on `PATH`, and the dictionary's database is always opened read-only.
That guarantee is target-specific from 0.3.0 onward — it holds for `sqlite` and
`hdf5`, is catalog-dependent for `ducklake`, and fails for `postgres`
([§10](docs/vision-direction-0.3.0.md)).

### Install

Build and install from source with [Cargo](https://rustup.rs):

```bash
cargo install --git https://github.com/pjc-crates/dbdict dbdict-cli
```

Or clone the repo and build locally:

```bash
git clone https://github.com/pjc-crates/dbdict.git
cd dbdict
cargo build --workspace --release
# binary is at target/release/dbdict
```

The first build compiles the bundled DuckDB (C++), which takes several minutes;
subsequent builds are cached.

## Development

A Rust workspace of library crates plus a thin CLI. The core is a pure library
exposing the parsed, resolved dictionary model; the CLI and the generators are
separate crates that consume that model:

* [`crates/dbdict/`](crates/dbdict/) — core: model, source-mapped YAML parsing,
  validation engine, diagnostics. Free of any DuckDB dependency.
* [`crates/dbdict-duckdb/`](crates/dbdict-duckdb/) — DuckDB backend (native
  bundled `duckdb` crate): scratch instantiation, schema reading, typedef
  expansion.
* [`crates/dbdict-ddl/`](crates/dbdict-ddl/) — DDL generator, consuming the
  lowered model.
* [`crates/dbdict-dummy-data/`](crates/dbdict-dummy-data/) — backend-neutral
  dummy-data generation.
* [`crates/dbdict-dummy-data-duckdb/`](crates/dbdict-dummy-data-duckdb/) — its
  DuckDB half.
* [`crates/dbdict-parquet/`](crates/dbdict-parquet/) — Parquet backend for the
  legacy format.
* [`crates/dbdict-cli/`](crates/dbdict-cli/) — thin CLI wrapper (binary:
  `dbdict`).

```bash
cargo build --workspace
cargo test --workspace
```

Project instructions for coding agents are in [`CLAUDE.md`](CLAUDE.md).

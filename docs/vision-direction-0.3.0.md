# dbdict — direction, 0.3.0

**Status:** the canonical statement of what dbdict is and what V1 of 0.3.0
covers. Supersedes the positioning in the archived
[`docs/v0.2.0/README.md`](v0.2.0/README.md) and
[`docs/v0.2.0/CLAUDE.md`](v0.2.0/CLAUDE.md).

Every external claim below carries a link to official documentation, or is
marked `Inferred:` with its reasoning visible. Claims marked `[measured]` were
probed on this machine; the probe output lives in `.claude-work/notes/`.

---

## 1. positioning

dbdict is a **swiss-army tool for working with data in an OR/MS + AI research
role — not production.** It optimises for time-to-first-useful-result on
someone else's database, and prefers breadth of small sharp commands over depth
of guarantees.

That sentence is load-bearing, because it is what makes the rest of the design
affordable. It removes migrations, schema evolution, access control,
multi-user concerns, CI gating and a scale story from scope.

It also makes **inferred constraints acceptable.** A validator is sound —
`count_nulls > 0` *disproves* `required`. An inferrer is not — `count_nulls
== 0` does not *prove* it. In research work a well-labelled hypothesis is
useful; in production it would be disqualifying. dbdict ships hypotheses, and
labels them as such (see §9, `draft`).

---

## 2. the two entry points

dbdict is a loop, and both ways in are first-class.

```
  ┌── BROWNFIELD: existing db ──inspect + profile──┐
  │                                                ▼
  │                                          DATASPEC  ◀── validate vs real db
  │                                                │
  └── GREENFIELD: author it (e.g. sim output) ─────┤
                                                    │
                        ┌───────────────────────────┴───────────────────────┐
                        ▼                                                   ▼
                DDL / constructing code                       client code jl/py/rs
```

**Green-field** is the discrete-event-simulation case: the output schema is
known in advance, and both a typed store and typed writers should come from it.

**Brown-field** is documenting a database that already has data. The reverse
direction is mostly a *rewiring of existing code* rather than new machinery —
`crates/dbdict-duckdb/src/native.rs` already exposes `read_schema`,
`count_nulls`, `count_duplicate_keys`, `count_duplicate_values`,
`count_orphaned_values` and `count_overmatched_rows`. Wired as validators
today; pointed at a database with no spec, the same queries *propose*
`required`, `primary_key`, `unique`, `foreign_key` and `cardinality`.

The document in the middle is the **dataspec**: `NAME.dbdict.yaml`, where
`NAME` is chosen per dataspec (e.g. `warehouse.dbdict.yaml`). "Dataspec" is the
name of the concept only — the `dbdict` binary and the `dbdict*` crates keep
their names.

---

## 3. the two-axis model

| axis | contents |
|---|---|
| **1 — target database**, named by `source:` | **V1:** `duckdb` · `ducklake` · `sqlite` · `hdf5` — **V2:** `postgres` |
| **2 — driver per (target × language)**, named in `languages:` | DuckDB → DuckDB.jl · QuackIO.jl · duckdb-py · duckdb-rs · HDF5 → JLD2.jl · HDF5.jl · h5py · hdf5-rs · **Quack** = DuckDB remote-access mode |

### why multiple targets — this is not "DuckDB-first with an escape hatch"

DuckDB turned out not to be as fully developed as needed **specifically in
combination with Julia**, which is a key target language. That is a finding
from this project's own work, not a preference: the driver study surfaced
DuckDB.jl appender silent failures, the benchmark sessions surfaced harness
confounds, and `research/duckdb-examples/duckdb_vs_jld2/` exists because an
alternative was being sought.

So multi-backend is **insurance, not aspiration** — and it is also why the
dbdict type vocabulary (§5) exists at all. A tool welded to one backend is only
as good as that backend's weakest driver.

### marginal cost is not uniform — three tiers, not two

- **`duckdb` ≈ `ducklake`** — native types, `COMMENT ON`, SQL constraint
  queries.
- **`sqlite`** — three encoding conventions, no `COMMENT ON` statement, integer
  widths unenforced. Still cheaper than HDF5: it keeps DDL, SQL constraint
  queries, and verbatim declared types via `PRAGMA table_info`.
- **`hdf5`** — the same three conventions *plus* no DDL, no comment statement,
  and no query engine for the D01–D05 checks.

SQLite is **affinity-typed, not declared-typed**, which is why it sits in the
middle tier rather than alongside DuckDB. Per [SQLite
datatypes](https://www.sqlite.org/datatype3.html): *"SQLite uses a more general
dynamic type system. In SQLite, the datatype of a value is associated with the
value itself, not with its container"*, and a column's type affinity is *"the
recommended type for data stored in that column. The important idea here is that
the type is recommended, not required."* It therefore needs the same encoding
conventions as HDF5.

### the roles that look like targets but are not

- **DuckLake is "parquet dir + SQL catalog".**
  [ducklake.select](https://ducklake.select/): *"DuckLake is an integrated data
  lake and catalog format"*, *"a lakehouse format built on SQL"*, delivering its
  features *"by using Parquet files and a SQL database"*, where *"The catalog is
  served by an ACID-compliant SQL database."* Per [Choosing a Catalog
  Database](https://ducklake.select/docs/stable/duckdb/usage/choosing_a_catalog_database),
  it *"can use PostgreSQL, SQLite or DuckDB as the catalog database."*
  **Postgres and SQLite therefore appear in two distinct roles** — as DuckLake
  *catalog* backends, and as dbdict targets in their own right. Do not conflate
  them.
- **Quack is not storage.** [duckdb.org/quack](https://duckdb.org/quack/): *"a
  Remote Procedure Call (RPC) protocol for DuckDB that enables DuckDB instances
  to talk to each other, effectively turning DuckDB into a client-server
  database management system."* Beta in
  [v1.5.3](https://duckdb.org/2026/05/20/announcing-duckdb-153); *"breaking
  changes are expected"*; stable targeted for v2.0, September 2026. It is an
  access mode on axis 2.
- **QuackIO.jl is a driver.**
  [QuackIO.jl](https://github.com/JuliaAPlavin/QuackIO.jl): *"provides a native
  Julia interface to DuckDB read/write functions."*
- **JLD2 is a driver for HDF5, not a target.**
  [JLD2.jl](https://github.com/JuliaIO/JLD2.jl): *"JLD2 files adhere to the
  HDF5 format specification making it compatible with HDF5 tooling and H5
  libraries in other languages."* — and JLD2 is *"in pure Julia"*. **HDF5 is
  the target; JLD2 is one Julia driver for it.**

> **JLD2 caveat.** *Project constraint, maintainer-stated:* JLD2 is a
> **superset** of HDF5, so it is not always compatible. Format conformance and
> semantic portability are different guarantees — bytes can satisfy the HDF5
> specification while their meaning is recoverable only from Julia. The
> specific mechanism is **compound values** (§11). Since compounds are out of
> V1, V1 emission stays inside the portable subset by construction. Recorded so
> it is not rediscovered the first time compounds are attempted.
>
> `Inferred:` — the sourced quote establishes format conformance only, not
> semantic portability for arbitrary Julia values. Open probe:
> `jld2-h5-crosscheck`.

### why Postgres is V2

Postgres alone **breaks the in-process guarantee** — it requires a running
server process, so validation and tests against it cannot be in-process. It
also has no 1-byte integer, so `int8` widens to `smallint` and round-trip
identity fails for that one type. It could not be probed on the machine where
this design was settled. This is a capability row (§10), not a footnote.

---

## 4. invariants

- the dataspec **names drivers, never type mappings** — mappings are determined
  by the (target database, driver) pair and compiled into Rust source
- adding a **driver** never touches `source:`
- the dataspec is **SQL-free** — this is *why* views are deferred to V2
- **one dataspec = one store**; **one dataspec = many named language targets**
- each backend is its own module/crate
- **type mappings live in Rust source, not in user files.** They can be
  *emitted* as YAML from either perspective — keyed by dbdict type, or keyed by
  the target database's types. Authoring wants "what does *my* type become over
  there"; reading someone else's database wants the inverse. Same table, two
  presentations, neither a file anyone maintains by hand.

---

## 5. the dbdict type vocabulary

Multi-target × multi-language means the dataspec cannot be typed in any one
system's types. 0.2.0's types were DuckDB-spelled, which privileged DuckDB and
did not map cleanly.

> The repo has already tried both ends of this axis. Legacy 0.1.0 used nine
> coarse *semantic* types — portable, but unable to drive codegen. The fork
> replaced them with DuckDB-native types — precise, but bound to one target.
> The dbdict vocabulary is the missing third option, and it works because 0.1.0
> conflated two orthogonal things: *physical storage* and *semantic role*.
> Split them and both problems go away.

### the ten types

Numeric and boolean types are defined by **bit layout**; temporal types by a
**pinned RFC profile**. Both are exact and mechanically checkable.

| dbdict type | definition | canonical width | DuckDB | SQLite (affinity) | HDF5 |
|---|---|---|---|---|---|
| `bool` | `0` = false, `1` = true | 8 bits | `BOOLEAN` | `INTEGER` 0/1 | encoded, `_dbdict_logical` |
| `int8` | two's complement, signed | 8 bits | `TINYINT` | `INTEGER` (width unenforced) | `H5T_STD_I8LE` |
| `int16` | two's complement, signed | 16 bits | `SMALLINT` | `INTEGER` (width unenforced) | `H5T_STD_I16LE` |
| `int32` | two's complement, signed | 32 bits | `INTEGER` | `INTEGER` (width unenforced) | `H5T_STD_I32LE` |
| `int64` | two's complement, signed | 64 bits | `BIGINT` | `INTEGER` | `H5T_STD_I64LE` |
| `float32` | IEEE 754 binary32 | 32 bits | `FLOAT` | **absent** — REAL is 8-byte only | `H5T_IEEE_F32LE` |
| `float64` | IEEE 754 binary64 | 64 bits | `DOUBLE` | `REAL` | `H5T_IEEE_F64LE` |
| `string` | UTF-8, unbounded | *variable* | `VARCHAR` | `TEXT` | variable- or fixed-length |
| `date` | **RFC 3339 `full-date`** — `YYYY-MM-DD`, no time, no zone | 10 bytes | `DATE` | ISO text | fixed `S10`, `_dbdict_logical` |
| `timestamp` | **RFC 3339 `date-time`**, µs, optional **RFC 9557** `[Zone]` suffix | 27–61 bytes | `TIMESTAMP` | ISO text | fixed `S27`/`S61`, `_dbdict_logical` |

DuckDB names cited from the [DuckDB data types
overview](https://duckdb.org/docs/current/sql/data_types/overview).

### canonical ≠ physical

The RFC form is the **canonical** definition — what a value *is*, what the spec
is written in, what `draft` emits. **Physical storage is each target's native
type where one exists**; the lexical form is the storage only where no native
type exists — **SQLite** and **HDF5**.

This dissolved what had looked like a deadlock. What must be shared across
targets is the **value space**, not the bytes. Imposing one encoding would have
broken every stock SQLite driver, since Python's `sqlite3` and Rust's
`rusqlite` (with chrono) both already write ISO text; writing `int64`
microseconds into a column declared `TIMESTAMP` would break both. ISO text also
keeps SQLite's own date and time functions working — they store dates and times
as *"**TEXT** as ISO8601 strings"*
([SQLite datatypes](https://www.sqlite.org/datatype3.html)) — and µs precision
survives exactly, since 6 fractional digits *is* microseconds.

The canonical form is in fact **strictly more expressive than some physical
layers**. Measured on DuckDB: one stored `TIMESTAMPTZ` value renders as `+00`,
`+12` or `-04` purely by session setting — the input zone is gone. Postgres is
explicit about the same behaviour ([PostgreSQL date/time
types](https://www.postgresql.org/docs/current/datatype-datetime.html), §8.5.1.3):
*"In either case, the value is stored internally as UTC, and the originally
stated or assumed time zone is not retained."* That overflow needs a declared
home, which is what `timezone:` / `timezone_from:` are for.

### the cost of lexical storage on HDF5 — measured, not assumed

Storing temporals as fixed-width ASCII costs 27–61 bytes/row against 8 for an
`int64` microsecond encoding — 3.4–7.6× *before compression*. The claim that
compression closes that gap was carried as `Inferred:` and has now been
**measured** ([full matrix and
method](../.claude-work/notes/20260802-1146-hdf5-temporal-compression.md)):

| | sorted | shuffled |
|---|---|---|
| `timestamp` lexical, best filter | **4.52** bytes/row | **7.43** bytes/row |
| `timestamp` zoned, best filter | **4.63** bytes/row | **7.51** bytes/row |
| vs 8.0 raw `int64` | clears it | clears it, by 6–7% |
| vs *compressed* `int64` | 1.14–1.17× | 1.25–1.27× |
| read time vs `int64` | — | **6.6× (S27), 15.8× (S61)** |

Three things follow, and the direction is deliberately stated in these terms
rather than as "compression closes the gap":

1. **The gap does close** on the stated test — lexical temporals land under the
   8 bytes/row raw integer size in every case. *Canonical ≠ physical* is
   affordable.
2. **"Well under" is true of sorted data only.** Unsorted columns clear the
   threshold by 6–7%, not comfortably. The compression argument rests on
   consecutive values sharing long prefixes, which is a property of sorted
   data.
3. **Size was never the real cost — read time is.** Against a compressed
   integer column, lexical costs 1.14–1.27× the disk but 6.6–15.8× the read.
   0.14 s for a million-row column is not a crisis, and dbdict's V1 workloads
   are not read-throughput-bound, but the ratio does not improve with scale.
   This is the cost being accepted, and it is accepted knowingly.

HDF5 temporal columns must therefore be **fixed-size**: variable-length HDF5
strings get neither chunking nor filters, so a variable-length temporal column
would be uncompressible — the finding is recorded with its citation in
[the type-system decisions note,
§7](../.claude-work/notes/20260731-1552-dbdict-type-system-decisions.md). This is
also what promotes `max_bytes:` from a validation nicety to a performance lever.

### strings

`string` takes **no length on any target** — all five targets have an unbounded
variable-length string type. Length limits are optional *constraints*:
`max_chars:` (Unicode characters) or `max_bytes:` (UTF-8 bytes), named
separately because Postgres counts characters and HDF5 counts bytes. On HDF5,
`max_bytes:` doubles as the switch that makes a column fixed-width and
therefore compressible.

### what was removed, and why

- **`decimal(p,s)` → V2+.** Little used in practice, and every available
  encoding was unattractive: SQLite stores it as lossy `REAL`, and the
  `decimal.c` extension is not in the amalgamation and loads per-connection.
- **`timestamptz` → removed permanently.** Zone information now rides *inside*
  the `timestamp` value as an RFC 9557 `[Zone]` suffix, or alongside it via a
  `timezone:` / `timezone_from:` attribute on targets whose native type
  discards it.
- **`datestamp` was never introduced.** Two independent reasons. **No compliant
  spelling exists** — RFC 3339 attaches `time-offset` only to a *time*, and RFC
  9557 extends only `date-time`, so neither `2026-07-31+12:00` nor
  `2026-07-31[Pacific/Auckland]` is standard. And a zoned date is
  **provenance, not a distinct value**: same digits, different provenance zone,
  same day. Provenance is a column attribute.

---

## 6. `attrdef:` — declared, expandable attributes

Column, table and view attributes must be expandable (`description:`,
`source:`, `scale:`, `label:`, and others — flexible and optional). In 0.2.0
every schema object is `closed: true`, so unknown keys are rejected.

The resolution is an **`attrdef:` section** that declares which attributes are
legal for each object kind, exactly as `typedef:` declares type aliases. The
schema stays closed; **the closure is authored by the document.**

`attrdef.meta:` defines the meta-attributes an attribute declaration may carry,
and these come in two kinds:

- **structural** — `type:` (required) and `mandatory:` (bool, default `false`).
  dbdict *acts* on these: `type` emits a struct field and validates values;
  `mandatory` fails the spec when an object omits the attribute. This set is
  **closed and dbdict-owned**, because each member needs a code path.
- **documentary** — `description:`, `notes:`, and anything you define. dbdict
  *passes these through* to emitted comments and the metadata table. This set is
  **open and yours**.

```yaml
attrdef:
  meta:                              # defines the meta-attribute vocabulary
    type:        { type: string }    # structural (reserved)
    mandatory:   { type: bool }      # structural (reserved)
    description: { type: string }    # documentary
    notes:       { type: string }    # documentary
    example:     { type: string }    # documentary — yours, passthrough
  column:
    description: { type: string,  description: "free-text column doc" }
    units:       { type: string,  description: "unit of measure" }
    scale:       { type: int32,   description: "display decimal places" }
    role:        { type: string,  description: "semantic role" }
  table:
    description: { type: string }
    owner:       { type: string }
  view:                              # scoped now; views land in V2
    description: { type: string }
```

| level | describes | vocabulary | extensible |
|---|---|---|---|
| column / table / view attributes | your data | `attrdef.column:` etc. | **yes** |
| structural meta-attributes | how dbdict *executes* an attribute | reserved: `type`, `mandatory` | **no** |
| documentary meta-attributes | the attribute itself, for readers | `attrdef.meta:` | **yes** |
| ⊥ | — | *leaf values have no attributes* | recursion ends |

**Why the recursion terminates**, and it is not because the vocabulary is
closed: documentary meta-attributes are **leaf values with no internal
structure**. A string has no attributes. You go one level up and stop, however
many names live at that level.

Two deliberate choices worth stating:

- **`default:` is not a meta-attribute.** A defaulted attribute is
  indistinguishable from an authored one, which destroys the "is this actually
  documented?" signal the whole attribute layer exists to give.
- **The name is `mandatory:`, not `required:`**, to avoid colliding with the
  column-level `constraints: [required]` — which means NOT NULL and is an
  entirely different idea. Two unrelated "required"s in one file is a
  readability trap.

Attribute types are drawn from **the same ten dbdict types**, so the attribute
layer reuses the type layer rather than inventing a parallel one. This is not
decoration: the hard-coded-struct codegen mode needs a type per attribute to
emit a struct field, and without it every attribute would arrive as a string in
every language (`scale: 4` → `"4"`).

---

## 7. `languages:` — named language targets

The mapping from dbdict types to a language's types is **fully determined by
the (target database, driver) pair**. DuckDB.jl decides what a `BIGINT` arrives
as in Julia; that is not a design choice dbdict gets to make. The consequence is
that **no language-specific mapping file is needed for V1** — naming the driver
is sufficient.

Because one database may be read from several languages, the dataspec carries a
`languages:` section. Each entry gets a **NAME**, and code is generated against
the NAME:

```yaml
source:
  duckdb: { file: warehouse.duckdb }

languages:
  jl:                      # NAME
    language: julia
    driver: DuckDB.jl
  py:                      # NAME
    language: python
    driver: duckdb
```

```
dbdict gen jl     # julia client, via DuckDB.jl
dbdict gen py     # python client, same dataspec, same store
```

**Why NAMEs rather than keying on language.** Two entries can share a language
and differ in driver (`DuckDB.jl` vs `QuackIO.jl`) or in codegen options
(comments-only vs live-read). Keying on `julia:` would forbid that; a NAME does
not. It also gives the CLI a stable handle that survives switching drivers.

> This **replaces** the earlier "the dataspec is language-free" invariant. The
> spec is not language-free — it names language targets. It stays free of *type
> mappings*, which is the property that actually mattered.

---

## 8. metadata propagation

Generated artifacts carry the dataspec's attributes, not just its structure.

### into a SQL store — both surfaces, table canonical

- a **`_dbdict_*` metadata table** holds the full open attribute set —
  queryable with plain SQL, handles arbitrary attributes, supports
  round-tripping
- **`COMMENT ON`** mirrors `description:` so standard tooling shows something
  sensible. [DuckDB COMMENT
  ON](https://duckdb.org/docs/current/sql/statements/comment_on): *"allows
  adding metadata to catalog entries (tables, columns, etc.). It follows the
  PostgreSQL syntax."* Applies to `TABLE`, `COLUMN`, `VIEW`, `INDEX`,
  `SEQUENCE`, `TYPE`, `MACRO`; read back via `duckdb_tables()` /
  `duckdb_columns()`. Limits: *"not possible to comment on schemas or
  databases"*, *"not possible to comment on things that have a dependency."*
  Postgres has it too ([PostgreSQL
  COMMENT](https://www.postgresql.org/docs/current/sql-comment.html)): *"COMMENT
  stores, replaces, or removes the comment on a database object."* DuckLake
  stores comments in `ducklake_tag` / `ducklake_column_tag`.

**SQLite has no `COMMENT ON` statement.** SQLite's `comment` documentation is
comment *syntax* (`--`, `/* */`), *"treated as whitespace by the parser"* ([SQL
Comment Syntax](https://www.sqlite.org/lang_comment.html)). DDL comments
nevertheless **survive verbatim** in `sqlite_schema.sql` [measured], so they can
carry documentation — but retrieval means parsing DDL text, not querying a
column. **On SQLite the `_dbdict_*` side table is the primary metadata surface,
not a supplement.**

> Both surfaces are needed. `COMMENT ON` holds **one string per object** and the
> attribute set is open, so it cannot be the only carrier. And a store whose
> documentation is invisible to `duckdb_columns()` is not documented.

### into an HDF5 store

Native attributes, which are key–value and therefore take the open set 1:1.
[HDF5 attributes user
guide](https://support.hdfgroup.org/documentation/hdf5/latest/_h5_a__u_g.html):
*"An HDF5 attribute is a small metadata object describing the nature and/or
intended usage of a primary data object"*, attachable to *"a dataset, group, or
committed datatype."* Caveats from the same page: *"Attributes are assumed to be
very small as data objects go"*, and *"there is no compression or chunking, and
attributes are not extendable"*.

The `_dbdict_logical` attribute also carries the encoding conventions: a
10-byte string column that is a `date` is otherwise indistinguishable from one
that is a `string`.

### into generated source — three modes, comments-only by default

1. a documentation comment block *(default)*
2. a hard-coded typed data struct *(opt-in)*
3. live read from the dataspec YAML at runtime *(opt-in)*

> Modes 1 and 2 are *snapshots* — self-contained, no runtime dependency, stale
> if the dataspec changes without regeneration. Mode 3 is never stale but makes
> the dataspec a runtime dependency that must ship alongside the code. Different
> deployment stories, not variants of one feature.

### the round-trip property

Because a database generated by dbdict carries its own dataspec, pointing the
brown-field path back at it should **recover** the spec rather than infer it
from statistics:

> `spec → DDL → db → draft → spec` **should be identity.**

Where it is not, per target:

| target | round-trip |
|---|---|
| `duckdb` | identity [measured] |
| `ducklake` | `Inferred:` identity — open probe `ducklake-roundtrip` |
| `sqlite` | **schema identity, value fidelity lost** — declared types recover via `PRAGMA table_info` [measured], but integer widths are unenforced and `float32` is unavailable |
| `hdf5` | identity **only via** `_dbdict_logical` attributes; without them `date` and `timestamp` are indistinguishable from `string` |
| `postgres` (V2) | **not identity** — `int8` returns as `int16` |

---

## 9. the V1 command surface

| command | what it does |
|---|---|
| `dbdict validate` | check an existing database against `NAME.dbdict.yaml` |
| `dbdict draft <db>` | **brown-field entry point** — emit a starting dataspec from an existing store |
| `dbdict ddl` | generate `CREATE TABLE` / constructing code for the target in `source:` |
| `dbdict gen <NAME>` | generate client code for a named `languages:` entry |
| `dbdict resolve` | emit the type mapping, keyed either by dbdict type or by target type |

Backends are add-ins selected by target database; codegen is an add-in selected
by target language. Each backend is its own module/crate.

### `draft` in detail

`dbdict draft <db>` emits:

- **schema** — table and column names, types mapped into dbdict types
- **profiled constraints** — `required`, `primary_key`, `unique`,
  `foreign_key`, `cardinality`, proposed by running the D01–D05 queries in
  inference mode
- **`description:` stubs** — empty, on every table and column, so the file is
  immediately ready for the human/AI authoring pass
- **evidence** — row count, null count and distinct count written as a YAML
  comment beside each proposal

> The evidence comments are not a nicety. Inference here is unsound by
> construction: `count_nulls == 0` does not *prove* `required` — it may just be
> a small table. Every proposed constraint is a hypothesis from absence of
> counter-evidence, and printing the counts is what lets a reader tell "no nulls
> in 8,412 rows" from "no nulls in 12 rows". The **not production** positioning
> (§1) is what makes shipping hypotheses acceptable; the evidence is what makes
> them judgeable.

---

## 10. capability matrix

`[measured]` = probed on this machine. `[cited]` = from the linked
documentation. `Inferred:` = reasoned, not verified.

### type coverage

| target | native types | needs work |
|---|---|---|
| `duckdb`, `ducklake` | 10 | — |
| `hdf5` | 7 | 3 encodings (`bool`, `date`, `timestamp`) |
| `sqlite` | 3 (`int64`, `float64`, `string`) | 3 encodings · 3 unenforced integer widths · `float32` absent |
| `postgres` *(V2)* | 9 | `int8` — no 1-byte integer, widens to `smallint` |

Only **three** types are native on every V1 target. A small fixed set costs a
decision *twice* — one storage encoding per target *and* one library type per
language — and that is still the whole hard part of V1. It is **3 rows on two
targets**.

### capability rows

| capability | duckdb | ducklake | sqlite | hdf5 | postgres *(V2)* |
|---|---|---|---|---|---|
| **schema generation (DDL)** | yes — `CREATE TABLE` [measured] | yes — DuckDB SQL; **no PK/FK/UNIQUE/CHECK** [cited] | yes — `CREATE TABLE` [measured] | **no DDL** — datasets created via the library API; `Inferred:` from HDF5 being a C library API with no SQL surface | yes [cited] |
| **type oracle** | `duckdb_columns()` / `DESCRIBE` [measured] | `Inferred:` same — probe `ducklake-describe` | `PRAGMA table_info` — declared type verbatim [measured] | `H5Tget_class`/`H5Tget_size` + `_dbdict_logical`; `Inferred:` | `information_schema.columns` — open probe `pg-type-oracle` |
| **metadata surface** | `COMMENT ON` [measured] | `COMMENT ON` → `ducklake_tag` [cited] | **no `COMMENT ON`**; DDL comments survive in `sqlite_schema.sql` [measured] | native attributes, open set 1:1 [cited] | `COMMENT ON` [cited] |
| **`_dbdict_*` side table** | yes | yes | yes — **primary** surface | n/a — attributes serve this role | yes |
| **D01–D05 constraint checks** | yes — SQL [cited] | yes — SQL [cited] | yes — SQL | **no** — no query engine; computed in-process over datasets | yes — SQL |
| **in-process guarantee** | **holds** — *"completely embedded within a host process"* [cited] | **conditional** — holds with a DuckDB or SQLite catalog, **breaks** with a Postgres catalog [cited] | **holds** — *"an in-process library"* [cited] | **holds** — `Inferred:` linked C library, no server | **BREAKS** — requires a running server [cited] |
| **compression filters** | n/a | n/a | n/a | gzip + shuffle on all types; **szip rejects fixed-width strings** [measured + cited] | n/a |
| **round-trip** | identity [measured] | `Inferred:` identity | schema identity, value fidelity lost | identity via `_dbdict_logical` | not identity (`int8`) |

> **The in-process row is a test-suite fact, not a feature-list entry.** 0.2.0's
> `CLAUDE.md` promised *"everything runs in-process; no runtime `duckdb` on PATH
> is needed by the library, the CLI, or the tests"*. That promise survives for
> `duckdb`, `sqlite` and `hdf5`, is **conditional** for `ducklake`, and **fails**
> for `postgres` — which means Postgres tests need a live server. The guarantee
> is now stated per target rather than globally.

> **On the szip row:** `h5py.h5z.filter_avail()` reports szip **present** on the
> probe machine, yet `H5Dcreate` rejects every fixed-width string column —
> *"SZIP compression can only be used with atomic datatypes that are integer,
> float, or char"*, and the conflict *"can only be detected when the property
> list is used"* ([HDF5 — Compressed
> Datasets](https://support.hdfgroup.org/documentation/hdf5/latest/_l_b_com_dset.html)).
> Availability and applicability are different questions. Consequence: the
> integer encodings have a filter option the lexical ones do not.

### open probes

| probe | question | status |
|---|---|---|
| `pg-type-oracle` | exact `information_schema.columns` output for the mappable types | deferred with Postgres to V2 |
| `ducklake-describe` / `ducklake-roundtrip` | does DuckLake's `DESCRIBE` match DuckDB's, and survive a snapshot? | needs the `ducklake` extension |
| `sqlitejl-temporal` | what does SQLite.jl write for `Date`/`DateTime`? Docs say non-native values serialize to `BLOB` | needs SQLite.jl; Julia is present |
| `sqlite-comment-durability` | do DDL comments survive `VACUUM` / `ALTER TABLE`? | the comment *is* the metadata carrier on SQLite |
| `jld2-h5-crosscheck` | JLD2 ↔ HDF5 semantic portability | needs JLD2; h5py is now reachable |

> `sqlite-comment-durability` is the one that could still change a decision. If
> comments do not survive `ALTER TABLE`, SQLite's documentation story rests
> entirely on the `_dbdict_*` side table, and the DDL-comment mirror should be
> dropped rather than shipped as a half-guarantee.

---

## 11. what is explicitly not in V1

### not in the type system

Every compound. The [DuckDB data types
overview](https://duckdb.org/docs/current/sql/data_types/overview) names them as
*"ARRAY, LIST, MAP, STRUCT and UNION"*, plus `VARIANT` (*"a semi-structured type
where each value is self-contained with its own type information"*), all of
which *"can be arbitrarily nested to any depth"*. Also out: `ENUM`, `TIME`,
`INTERVAL`, `UUID`, `BLOB`, `BIT`, `JSON`, all unsigned integers, `HUGEINT`,
`UHUGEINT`, `BIGNUM`.

**Compounds are deferred, and the mechanism for their return is out of scope
for 0.3.0.** When they do return it will be as a **(target × language)
pairing**, not as dbdict type entries. Two independent reasons, and the second
is the harder one:

1. **No neutral spelling exists.** A neutral vocabulary works for scalars
   because width and precision are universal concepts. For `STRUCT` ↔
   `NamedTuple` ↔ `dataclass` ↔ `struct`, field ordering, optionality and
   nesting all diverge, so the mapping has to be pinned per (db, language)
   pair. This is an argument about **design difficulty**.
2. **On this stack there is currently nowhere for them to work.**
   *Maintainer-stated:* compound types are not really practical for Julia at the
   moment, and certainly not with DuckDB. They are fine through JLD2 — but using
   them **breaks JLD2 ↔ HDF5 compatibility**, which is exactly the property that
   made HDF5 worth having as a target. Each available path fails differently:
   one is not ready, the other costs the portability the target was chosen for.
   This is an argument about **availability**, and it is why the deferral is not
   merely tidy scoping.

### not in scope, by feature

- **`postgres`** — V2. See §3.
- **`decimal(p,s)`** — V2+. See §5.
- **`timestamptz`** — removed permanently, not deferred.
- **views** — V2. This is *why* the dataspec is SQL-free.
- **`dummy`** — the dummy-data generator exists today
  (`crates/dbdict-dummy-data`, `crates/dbdict-dummy-data-duckdb`, and the CLI
  `dummy` command) but **will not survive the internal changes 0.3.0 requires
  and will not ship in 0.3.0.** Revisit later.
- **migrations, schema evolution, access control, multi-user concerns, CI
  gating, a scale story** — all removed by the positioning in §1.

### a known divergence between this document and the code

**`decimal` and `timestamptz` are out of the V1 type system described here, but
are still implemented in `crates/`.** As at commit `3337de5`,
`grep -rniE '\b(decimal|timestamptz)\b' crates/ --include=*.rs` returns **121
hits across 19 files** — source as well as tests, including
`dbdict/src/rich.rs`, `dbdict/src/lower.rs`, `dbdict-duckdb/src/native.rs`,
`dbdict-dummy-data-duckdb/src/types.rs` and `dbdict-parquet/src/metadata.rs`.
`schema-0.2.yaml` also documents a free-form DuckDB type expression using
`DECIMAL(18, 4)` as its example.

This is a **recorded debt, not an oversight.** The 0.3.0 re-baseline was scoped
as documents-only, so the code still implements the type system the documents
have stopped describing. Reconciling them is a roadmap item — see
[`roadmap-0.3.0.md`](roadmap-0.3.0.md).

---

## versioning

The dbdict type vocabulary is a **breaking format change**, which is why the
next version is `0.3.0`. That decision is recorded here; acting on it — editing
`schema-0.2.yaml` / writing `schema-0.3.yaml`, and the 0.2.0 migration story —
is downstream work.

The pre-shift state is preserved at tag **`v0.2.0`** (`ab468fa`) and archived
under [`docs/v0.2.0/`](v0.2.0/).

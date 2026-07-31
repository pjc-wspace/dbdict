# revisit app objectives and goals for v0.3.0

## problem

Two problems, and only the first one looks like a documentation bug.

**(a) The repo's documents describe a repo that does not exist.**

- `README.md` links `site/spec.md` and `site/validation.md`, and states the
  website is *"a Quarto project in `site/`, published to GitHub Pages on every
  push to `main`"*. There is no `site/` — it was parked in `todos/legacy-site/`.
- `README.md`'s crate list omits `dbdict-dummy-data` and
  `dbdict-dummy-data-duckdb`.
- `CLAUDE.md` states *"not aiming for cross-backend portability. DuckDB-first."*

**(b) The direction shifted, and nothing in the repo records it.**

dbdict was built as a **data dictionary** — a *description* of an existing
database, checked against it. The direction is now a **dataspec**: a source of
truth that *drives* generation, and that works in both directions.

Evidence the shift already happened without being written down:

- four consecutive sessions (25–31 Jul) produced **zero crate changes** — all
  effort went into measuring the substrate (driver study, benchmarks, dedup,
  benchmark reconciliation)
- three untracked research dirs, all probing the backend premise:
  `research/parquet2-as-alternative-backend/`, `research/duckdb-examples/`
  (DuckDB vs JLD2 round-trip and compression), `research/quackio-driver-jl/`
- the held session `20260723-1109-julia-read-write-codegen` has a detailed
  `goal.md` whose premises have since moved

> The two problems are not independent. The README is not stale *by neglect* —
> it is stale because the project's centre of gravity moved and the move was
> never articulated. Repairing the text without recording the direction would
> put it back on the same trajectory.

## success criteria

1. A canonical direction document exists at
   `docs/vision-direction-0.3.0.md`, covering: positioning, the two entry
   points, the two-axis model, the invariants, the dbdict type
   vocabulary, the `attrdef:` design, the `languages:` design, the
   metadata-propagation story, and the V1 command surface (including the
   brown-field `draft` command).
2. The **pre-shift** state is preserved: current `README.md` and `CLAUDE.md`
   (plus any existing direction/vision content) are archived under
   `docs/v0.2.0/`, and a git tag `v0.2.0` is created at the last commit before
   the direction change (`ab468fa` at time of writing).
3. The V1 type set is written down using both its dbdict-type spellings and
   its DuckDB equivalents, with a citation for the DuckDB names, a **stated bit
   layout per type**, and a rationale for what is in and out.
4. A per-target capability matrix exists covering **all five targets**
   (`duckdb`, `ducklake`, `postgres`, `sqlite`, `hdf5`), in which every cell is
   either resolved with a citation, or marked `unknown — needs probe X` with
   the probe named. No blank cells.
5. ~~The **four HDF5 encoding conventions** (`date`, `timestamp`,
   `timestamptz`, `decimal(p,s)`)~~ — **REVISED IN PHASE 2: three encoding
   conventions** (`bool`, `date`, `timestamp`), shared by **both** SQLite and
   HDF5 rather than HDF5 alone. `decimal(p,s)` moved to V2+ and `timestamptz`
   was removed, so two of the original four no longer exist. Each is decided
   and written down, or recorded as open with the specific probe that would
   settle it.
6. The **in-process guarantee** is restated honestly per target. CLAUDE.md
   currently promises *"everything runs in-process; no runtime `duckdb` on
   PATH is needed by the library, the CLI, or the tests"* — Postgres breaks
   it. This is its own row in the matrix, because it changes how the test
   suite works, not just what is supported.
7. `README.md` is repositioned — not merely repaired. Every remaining factual
   claim is true of the repo *and* of V1's scope.
8. `CLAUDE.md` is updated. Its cross-backend stance is **inverted**, not
   tweaked, and it points at the direction document rather than restating it.
   No claim lives in two files.
9. The held codegen session's `goal.md` is rewritten (not amended) so it
   contains no premise contradicting V1 scope.
10. An ordered roadmap exists, into which the six pending follow-ups from the
    closed benchmark session are folded — or from which they are explicitly
    dropped with a reason.
11. The three untracked research dirs are dispositioned (committed, ignored,
    or relocated) and `git status` is clean.

## scope

- **in:** decisions and documents only. The direction document; the archive of
  the 0.2.0 state and the `v0.2.0` tag; the V1 type set; the capability
  matrix; the roadmap; `README.md` and `CLAUDE.md` rewritten; the held codegen
  `goal.md` rewritten; disposition of the untracked dirs; triage of the six
  benchmark follow-ups.

- **out:** any crate code. Any schema change — `schema-0.3.yaml` is *not*
  written this session, and `source:` stays closed at `{duckdb}`. The
  `$version` bump itself. Any target implementation. Any generator work.
  Resuming the codegen session. Views. Compound types. The rename of files,
  binary or crates. **Any work on `dummy`** (see below).

> The session decides and records; a downstream session implements. This was
> a deliberate call: a re-baseline that also writes code tends to have its
> conclusions bent by whatever turned out to be easy to build.

## constraints

- the maintainer is a Julia novice and an early Rust learner — the direction
  document is written for that reader, and Julia is the first codegen target
- the "sourcing & evidence" rule applies with full force: this session's
  entire output is documentation, and documentation amplifies errors. Every
  claim about an external tool must be quoted and cited, or marked `Inferred:`
- the generator-crate architecture rule stands: generators consume the
  resolved model from `dbdict` core only
- context budget — start any phase below 25% context; the previous session
  closed at 27% and had to defer its follow-ups

---

## decisions taken in brainstorming

These are settled inputs. The session's job is to write them up, not to
re-litigate them.

### positioning

A **swiss-army tool for working with data in an OR/MS + AI research role —
not production.** Optimise for time-to-first-useful-result on someone else's
database; breadth of small sharp commands over depth of guarantees.

> This is what makes the rest of the design affordable. It removes migrations,
> schema evolution, access control, multi-user concerns, CI gating and a scale
> story from scope. It also makes inferred constraints acceptable — a
> validator is sound (`count_nulls > 0` *disproves* `required`) but an
> inferrer is not (`count_nulls == 0` does not *prove* it). In research work a
> well-labelled hypothesis is useful; in production it would be disqualifying.

### the tool is a loop with two entry points

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

Both entry points are first-class. Green-field is the DES/simulation case:
the output schema is known, and both a typed store and typed writers should
come from it. Brown-field is documenting a database that already has data.

> The reverse direction is mostly a **rewiring of existing code**, not new
> machinery. `crates/dbdict-duckdb/src/native.rs` already exposes
> `read_schema`, `count_nulls`, `count_duplicate_keys`,
> `count_duplicate_values`, `count_orphaned_values` and
> `count_overmatched_rows`. Wired as validators today; pointed at a database
> with no spec, the same queries propose `required`, `primary_key`, `unique`,
> `foreign_key` and `cardinality`.

**Primary functions of dbdict:**

- **backend databases** — checking an existing database schema against
  `NAME.dbdict.yaml`. Each backend gets its **own module/crate** providing the
  translation layer.
- **`DDL` generation** and **`client code gen`** — both are target "add-ins",
  selected by target database and target code language.
- **type mappings live in Rust source**, not in user files. They can be
  *emitted* as YAML from either perspective — (1) keys are dbdict types,
  (2) keys are the target database's types.

> Emitting the mapping in both directions is the `resolve` command
> generalised: authoring wants "what does *my* type become over there", and
> reading someone else's database wants the inverse. Same table, two
> presentations, neither of them a file the user has to maintain.

**`dummy` is out of scope for v0.3.0.** It exists today
(`crates/dbdict-dummy-data`, `crates/dbdict-dummy-data-duckdb`, and the CLI
`dummy` command), but it will not survive the internal changes 0.3.0 requires
and will not ship in 0.3.0. **No work on it during this vision.** Revisit
later.

### the two-axis model

| axis | contents |
|---|---|
| **1 — target database**, named by `source:` | **V1:** `duckdb` · `ducklake` · `sqlite` · `hdf5` — **V2:** ~~`postgres`~~ |
| **2 — driver per (target × language)**, named in `languages:` | DuckDB → DuckDB.jl · QuackIO.jl · duckdb-py · duckdb-rs 〜 HDF5 → JLD2.jl · HDF5.jl · h5py · hdf5-rs 〜 **Quack** = DuckDB remote access mode |

**Why five targets — and why this is *not* "DuckDB-first with an escape
hatch":**

> DuckDB turned out not to be as fully developed as needed, *specifically in
> combination with Julia*, which is a key target language. That is a finding
> from this project's own work, not a preference: the driver study surfaced
> DuckDB.jl appender silent failures (captured in
> `.claude-work/insights/20260726-1128-duckdb-jl-appender-silent-failures-and-confounded-probes.md`),
> the benchmark sessions surfaced harness confounds, and
> `research/duckdb-examples/duckdb_vs_jld2/` exists because an alternative was
> being sought.
>
> So multi-backend is **insurance, not aspiration** — and it is also why the
> dbdict type vocabulary exists. A tool welded to one backend is only as good
> as that backend's weakest driver.

> **Marginal cost is not uniform. ~~Expect `duckdb → ducklake → postgres →
> sqlite` ≈ flat, then a step up to `hdf5`.~~** — **CORRECTED IN PHASE 2, and
> the original prediction was wrong.** SQLite is *affinity*-typed, not
> declared-typed: it has five storage classes, no boolean, no date/time and no
> decimal, one undifferentiated INTEGER width and an 8-byte-only REAL. It
> therefore needs **the same encoding conventions as HDF5**, and is not a
> near-free SQL target at all. The real shape is three tiers:
>
> - `duckdb ≈ ducklake` — native types, `COMMENT ON`, SQL constraint queries.
>   (`postgres` sat here too, and was **deferred to V2** — it breaks the
>   in-process guarantee and has no 1-byte integer, so `int8` widens to
>   `smallint` and round-trip identity breaks for that one type.)
> - **`sqlite`** — three encoding conventions, no `COMMENT ON` statement,
>   widths unenforced. Still cheaper than HDF5: it keeps DDL, SQL constraint
>   queries, and verbatim declared types via `PRAGMA table_info`.
> - **`hdf5`** — the same three conventions *plus* no DDL, no comment
>   statement, and no query engine for D01–D05.
>
> The convention count fell from four to **three** (`bool`, `date`,
> `timestamp`) once `decimal` moved to V2+ and `timestamptz` was removed.
>
> Full evidence, with citations and probe output, in
> `.claude-work/notes/20260731-1253-capability-matrix.md`.

> **Postgres breaks the in-process guarantee.** DuckDB is bundled and SQLite
> is embeddable, so both keep everything in-process. Postgres needs a running
> server, so validation and tests against it cannot be. This is a capability
> row, not a footnote.

Sourced findings that shaped the roster:

- **DuckLake is "parquet dir + SQL catalog".** [ducklake.select](https://ducklake.select/):
  *"DuckLake is an integrated data lake and catalog format"*, *"a lakehouse
  format built on SQL"*, delivering its features *"by using Parquet files and
  a SQL database"*, where *"The catalog is served by an ACID-compliant SQL
  database."* Per [Choosing a Catalog Database](https://ducklake.select/docs/stable/duckdb/usage/choosing_a_catalog_database),
  it *"can use PostgreSQL, SQLite or DuckDB as the catalog database."*
  → Postgres and SQLite therefore appear in **two distinct roles**: as
  DuckLake *catalog* backends, and as dbdict targets in their own right. The
  direction document must keep those roles separate.
- **Quack is not storage.** [duckdb.org/quack](https://duckdb.org/quack/):
  *"a Remote Procedure Call (RPC) protocol for DuckDB that enables DuckDB
  instances to talk to each other, effectively turning DuckDB into a
  client-server database management system."* Beta in
  [v1.5.3](https://duckdb.org/2026/05/20/announcing-duckdb-153); *"breaking
  changes are expected"*; stable targeted for v2.0, September 2026.
  → an access mode on axis 2, not a target.
- **QuackIO.jl is a driver, not storage.** [QuackIO.jl](https://github.com/JuliaAPlavin/QuackIO.jl):
  *"provides a native Julia interface to DuckDB read/write functions."*
- **JLD2 is a driver for HDF5, not a target.** [JLD2.jl](https://github.com/JuliaIO/JLD2.jl):
  *"JLD2 files adhere to the HDF5 format specification making it compatible
  with HDF5 tooling and H5 libraries in other languages. (Can also read HDF5
  files.)"* — and JLD2 is *"in pure Julia"*.
  → **HDF5 is the target; JLD2 is one Julia driver for it.**

> **JLD2 caveat — a constraint on the HDF5 target.** *Project constraint,
> maintainer-stated:* JLD2 is a **superset** of HDF5, so it is not always
> compatible. Format conformance and semantic portability are different
> guarantees: bytes can satisfy the HDF5 specification while their meaning is
> recoverable only from Julia.
>
> The specific mechanism is **compound values** — see the compounds section
> below. Using them through JLD2 is what breaks JLD2↔HDF5 compatibility.
> Since compounds are out of V1 anyway, V1 emission stays inside the portable
> subset by construction; the constraint is recorded so it is not rediscovered
> the first time compounds are attempted.
>
> `Inferred:` the sourced quote establishes format conformance only, not
> semantic portability for arbitrary Julia values. **Probe:** write a table
> via JLD2, open it with a non-Julia H5 library, report what is recoverable.

**Invariants:**

- the dataspec **names drivers, never type mappings** — mappings are
  determined by the (target database, driver) pair and compiled into Rust
  source
- adding a **driver** never touches `source:`
- the dataspec is **SQL-free** — this is *why* views are deferred to V2
- **one dataspec = one store**; **one dataspec = many named language targets**
- each backend is its own module/crate

### `languages:` — named language targets

The mapping from dbdict types to a language's types is **fully determined by the
(target database, driver) pair**. DuckDB.jl decides what a `BIGINT` arrives as
in Julia; that is not a design choice dbdict gets to make. Consequence:
**no language-specific mapping file is needed for V1** — naming the driver is
sufficient.

Because one database may be read from several languages, the dataspec carries
a `languages:` section. Each entry gets a **NAME**, and code is generated
against the NAME:

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

> **Why NAMEs rather than keying on language.** Two entries can share a
> language and differ in driver (`DuckDB.jl` vs `QuackIO.jl`) or in codegen
> options (comments-only vs live-read). Keying on `julia:` would forbid that;
> a NAME does not. It also gives the CLI a stable handle that survives
> switching drivers.

> This **replaces** the earlier "the dataspec is language-free" invariant. The
> spec is not language-free — it names language targets. It stays free of
> *type mappings*, which is the property that actually mattered.

### the dbdict type vocabulary

Multi-target × multi-language means the dataspec cannot be typed in any one
system's types. Today's 0.2.0 types are DuckDB-spelled, which privileges
DuckDB and does not map cleanly.

> The repo has already tried both ends of this axis. Legacy 0.1.0 used nine
> coarse *semantic* types (`schema.yaml` line 87: `"enum"`,
> `"number(ordinal)"`, `"number(quantity)"`, `"date"`, `"datetime"`,
> `"number"`, `"number(id)"`, `"string"`, `"boolean"`) — portable but unable
> to drive codegen. The fork replaced them with DuckDB-native types —
> precise but bound to one target. The dbdict type vocabulary is the missing third
> option, and it works because 0.1.0 conflated two orthogonal things:
> *physical storage* and *semantic role*. Split them and both problems go.

> **REVISED IN PHASE 2 — the vocabulary is called "dbdict types", it has 10
> members, and every member carries a bit layout.** Full record, with
> reasoning: `.claude-work/notes/20260731-1552-dbdict-type-system-decisions.md`.

**V1 vocabulary — ~~12~~ 10 scalars.** Numeric and boolean types are defined by
**bit layout**; temporal types by a **pinned RFC profile**. Both are exact and
mechanically checkable:

| dbdict type | definition | width | DuckDB equivalent |
|---|---|---|---|
| `bool` | `0` = false, `1` = true | 8 bits | `BOOLEAN` |
| `int8` `int16` `int32` `int64` | two's complement, signed | 8/16/32/64 bits | `TINYINT` `SMALLINT` `INTEGER` `BIGINT` |
| `float32` `float64` | IEEE 754 binary32 / binary64 | 32/64 bits | `FLOAT` `DOUBLE` |
| `string` | UTF-8, unbounded | *variable* | `VARCHAR` |
| `date` | **RFC 3339 `full-date`** — `YYYY-MM-DD`, no time, no zone | 10 bytes | `DATE` |
| `timestamp` | **RFC 3339 `date-time`**, µs; optional **RFC 9557** `[Zone]` suffix | 27–61 bytes | `TIMESTAMP` / `TIMESTAMPTZ` |

**Canonical vs physical.** The RFC form is the *canonical* definition — what a
value is, what the spec is written in, what `draft` emits. **Physical storage
is each target's native type where one exists** (DuckDB, DuckLake, Postgres);
the lexical form is the storage only where no native type exists — **SQLite**
(which is what Python's and Rust's drivers already write) and **HDF5**.

**Removed from the earlier 12:**

- ~~`decimal(p,s)`~~ → **V2+**. Maintainer: little used in practice; and every
  available encoding was unattractive (SQLite stores it as lossy `REAL`; the
  `decimal.c` extension is not in the amalgamation and loads per-connection).
- ~~`timestamptz`~~ → **removed permanently**. Zone information now rides
  inside the `timestamp` value (RFC 9557 `[Zone]` suffix), or alongside it via
  a `timezone:` / `timezone_from:` attribute on targets whose native type
  discards it. Measured on DuckDB: one stored `TIMESTAMPTZ` renders as `+00`,
  `+12` or `-04` purely by session setting — the input zone is gone. Postgres
  is explicit: *"the value is stored internally as UTC, and the originally
  stated or assumed time zone is not retained."*

**Never introduced:** `datestamp` (a date carrying a zone). Two independent
reasons: **no compliant spelling exists** — RFC 3339 attaches `time-offset`
only to a *time*, and RFC 9557 extends only `date-time`, so neither
`2026-07-31+12:00` nor `2026-07-31[Pacific/Auckland]` is standard — and a
zoned date is **provenance, not a distinct value**: same digits, different
provenance zone, same day. Provenance is a column attribute.

**`string` takes no length on any target** — all five have an unbounded
variable-length string type. Length limits are optional *constraints*,
`max_chars:` (Unicode characters) or `max_bytes:` (UTF-8 bytes), named
separately because Postgres counts characters and HDF5 counts bytes.

DuckDB names cited from
[DuckDB data types overview](https://duckdb.org/docs/current/sql/data_types/overview).

**Out of V1:** every compound — the same page names them as *"ARRAY, LIST,
MAP, STRUCT and UNION"*, plus `VARIANT` (*"a semi-structured type where each
value is self-contained with its own type information"*), all of which *"can
be arbitrarily nested to any depth"*. Also out: `ENUM`, `TIME`, `INTERVAL`,
`UUID`, `BLOB`, `BIT`, `JSON`, all unsigned integers, `HUGEINT`, `UHUGEINT`,
`BIGNUM`.

**Compounds are deferred. The mechanism for their return is TBD and out of
scope for v0.3.0** — the direction document should say so rather than sketch
a design nobody has requirements for yet. When they do return it will be as a
**(target × language) pairing**, not as dbdict type entries.

Two independent reasons, and the second is the harder one:

> **1 — no neutral spelling exists.** A neutral vocabulary works for scalars
> because width and precision are universal concepts. For `STRUCT` ↔
> `NamedTuple` ↔ `dataclass` ↔ `struct`, field ordering, optionality and
> nesting all diverge, so the mapping has to be pinned per (db, language)
> pair. This is an argument about design difficulty.

> **2 — on this stack there is currently nowhere for them to work.**
> *Maintainer-stated:* compound types are not really practical for Julia at
> the moment, and certainly not with DuckDB. They are fine through JLD2 — but
> **using them breaks JLD2↔HDF5 compatibility**, which is exactly the property
> that made HDF5 worth having as a target. So each available path fails
> differently: one is not ready, the other costs the portability the target
> was chosen for. This is an argument about availability, and it is why the
> deferral is not merely tidy scoping.

> **The structural cost finding — ~~8 of the 12 types are free on every
> target~~. CORRECTED IN PHASE 2**, then revised again when the set shrank to
> 10. Against the **V1 targets**:
>
> | target | native | needs work |
> |---|---|---|
> | `duckdb`, `ducklake` | 10 | — |
> | `hdf5` | 7 | 3 encodings (`bool`, `date`, `timestamp`) |
> | `sqlite` | 3 (`int64`, `float64`, `string`) | 3 encodings · 3 unenforced int widths · `float32` absent |
> | ~~`postgres`~~ (V2) | 9 | `int8` — no 1-byte integer, widens to `smallint` |
>
> Only **three** types (`int64`, `float64`, `string`) are native on every V1
> target — not eight. The shape of the original claim survives even though its
> number did not: a small fixed set costs a decision *twice* — one storage
> encoding per target *and* one library type per language — and that set is
> still the whole hard part of V1. It is now **3 rows on two targets**.

### `attrdef:` — declared, expandable attributes

Column, table and view attributes must be expandable (`description:`,
`source:`, `scale:`, `label:`, … and others — flexible and optional). Today
every schema object is `closed: true` (unknown keys rejected).

Resolution: an **`attrdef:` section** declares which attributes are legal for
each object kind, exactly as `typedef:` declares type aliases. The schema
stays closed; the *closure* is authored by the document.

`attrdef.meta:` **defines** the meta-attributes an attribute declaration may
carry. Those come in two kinds:

- **structural** — `type:` (required) and `mandatory:` (bool, default
  `false`). dbdict *acts* on these: `type` emits a struct field and validates
  values; `mandatory` fails the spec when an object omits the attribute. This
  set is **closed and dbdict-owned**, because each member needs a code path.
- **documentary** — `description:`, `notes:`, and anything you define. dbdict
  *passes these through* to emitted comments and the metadata table. This set
  is **open and yours**.

```yaml
attrdef:
  meta:                              # defines the meta-attribute vocabulary
    type:        { type: string }    # structural (reserved)
    mandatory:   { type: bool }      # structural (reserved)
    description: { type: string }    # documentary
    notes:       { type: string }    # documentary
    example:     { type: string }    # documentary - yours, passthrough
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

> `default:` is deliberately **not** a meta-attribute. A defaulted attribute
> is indistinguishable from an authored one, which destroys the "is this
> actually documented?" signal that the whole attribute layer exists to give.

> **The name is `mandatory:`, not `required:`, to avoid colliding with the
> column-level `constraints: [required]`** — which means NOT NULL and is an
> entirely different idea. Two unrelated "required"s in one file is a
> readability trap.

> **Why the recursion terminates — and it is not because the vocabulary is
> closed.** An earlier draft argued meta-attributes must be a fixed set,
> since anything dbdict has not heard of is inert. That holds only for the
> *structural* half. The documentary half is passthrough, exactly like column
> attributes — read by people, not executed by the tool — so there is no
> principled reason to close it. `example:` on an attribute declaration is as
> legitimate as `lineage:` on a column.
>
> Recursion terminates for a simpler reason: **documentary meta-attributes are
> leaf values with no internal structure.** A string has no attributes. You go
> one level up and stop, however many names live at that level.

| level | describes | vocabulary | extensible |
|---|---|---|---|
| column / table / view attributes | your data | `attrdef.column:` etc. | **yes** |
| structural meta-attributes | how dbdict *executes* an attribute | reserved: `type`, `mandatory` | **no** |
| documentary meta-attributes | the attribute itself, for readers | `attrdef.meta:` | **yes** |
| ⊥ | — | *leaf values have no attributes* | recursion ends |

> Attribute types are drawn from **the same 10 dbdict types**, so
> the attribute layer reuses the type layer rather than inventing a parallel
> one. This is not decoration: the hard-coded-struct codegen mode needs a type
> per attribute to emit a struct field, and without it every attribute would
> arrive as a string in every language (`scale: 4` → `"4"`).

### metadata propagation — attributes land in the outputs

Generated artifacts carry the dataspec's attributes, not just its structure.

**Into a SQL store (DuckDB / DuckLake / Postgres / SQLite) — both, table
canonical:**

- a `_dbdict_*` metadata table holds the full open attribute set (queryable
  with plain SQL, handles arbitrary attributes, supports round-tripping)
- `COMMENT ON` mirrors `description:` so standard tooling shows something
  sensible. [DuckDB COMMENT ON](https://duckdb.org/docs/current/sql/statements/comment_on):
  *"allows adding metadata to catalog entries (tables, columns, etc.). It
  follows the PostgreSQL syntax."* Applies to `TABLE`, `COLUMN`, `VIEW`,
  `INDEX`, `SEQUENCE`, `TYPE`, `MACRO`; read back via `duckdb_tables()` /
  `duckdb_columns()`. Limits: *"not possible to comment on schemas or
  databases"*, *"not possible to comment on things that have a dependency."*
  ~~`Inferred:`~~ **Confirmed in phase 2** — Postgres does have `COMMENT ON`
  ([PostgreSQL COMMENT](https://www.postgresql.org/docs/current/sql-comment.html)):
  *"COMMENT stores, replaces, or removes the comment on a database object."*
  Read back with `obj_description`/`col_description`. DuckLake also has it,
  storing comments in `ducklake_tag`/`ducklake_column_tag`.

  **SQLite comment support — resolved in phase 2: there is no `COMMENT ON`
  statement.** SQLite's `comment` documentation is comment *syntax* (`--`,
  `/* */`), *"treated as whitespace by the parser"*
  ([SQL Comment Syntax](https://www.sqlite.org/lang_comment.html)). Probed
  finding: DDL comments nevertheless **survive verbatim** in
  `sqlite_schema.sql`, so they can carry documentation — but retrieval means
  parsing DDL text, not querying a column. The `_dbdict_*` side table is
  therefore the primary metadata surface on SQLite, not a supplement.

> The side table is needed because `COMMENT ON` holds **one string per
> object** and the attribute set is open. The mirror is needed because a store
> whose documentation is invisible to `duckdb_columns()` is not documented.

**Into an HDF5 store:** native attributes, which are key–value and therefore
take the open set 1:1. [HDF5 user guide](https://support.hdfgroup.org/documentation/hdf5/latest/_h5_a__u_g.html):
*"An HDF5 attribute is a small metadata object describing the nature and/or
intended usage of a primary data object"*, attachable to *"a dataset, group,
or committed datatype."* Caveats: *"Attributes are assumed to be very small as
data objects go"*, *"there is no compression or chunking, and attributes are
not extendable"*, ~64K in compact storage.

**Into generated source, three modes — `comments only` is the default:**

1. a documentation comment block *(default)*
2. a hard-coded typed data struct *(opt-in)*
3. live read from the dataspec YAML at runtime *(opt-in)*

> Modes 1 and 2 are *snapshots* — self-contained, no runtime dependency,
> stale if the dataspec changes without regeneration. Mode 3 is never stale
> but makes the dataspec a runtime dependency that must ship alongside the
> code. Different deployment stories, not variants of one feature.

> **Why metadata-into-the-store matters beyond documentation:** a database
> generated by dbdict carries its own dataspec, so pointing the brown-field
> path back at it *recovers* the spec rather than inferring it from
> statistics. Worth stating as a testable property:
> `spec → DDL → db → draft → spec` should be identity, or the direction
> document should say exactly where it is not.

### naming and versioning

- **Dataspec files are `NAME.dbdict.yaml`**, where `NAME` is chosen per
  dataspec (e.g. `warehouse.dbdict.yaml`). This matches the convention the
  held codegen session already proposed and gives companion files a shared
  stem.
- **"dataspec" is the concept only.** The `dbdict` binary and the `dbdict*`
  crates keep their names.
- the dbdict type vocabulary is a **breaking format change**, and the next version is
  therefore `0.3.0`. That *decision* is made here; *acting* on it — editing
  `schema-0.2.yaml`/writing `schema-0.3.yaml`, and the 0.2.0 migration
  story — is downstream work, per the scope rule above.

### the brown-field `draft` command is in V1

`dbdict draft <db>` emits a starting dataspec from an existing store:

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
> counter-evidence, and printing the counts is what lets a reader tell "no
> nulls in 8,412 rows" from "no nulls in 12 rows". The "not production"
> positioning is what makes shipping hypotheses acceptable; the evidence is
> what makes them judgeable.

### archive layout and tag point

- `docs/v0.2.0/` receives **copies** of the current `README.md` and
  `CLAUDE.md` — both must remain at the repo root to keep working, so this is
  a copy, not a move.
- git tag **`v0.2.0` at `ab468fa`** ("State: post-close checkpoint, review
  follow-ups pending") — the current HEAD and the last commit before any
  direction change.

> The tag is created during the session, with the SHA confirmed at that point
> rather than assumed from this document.

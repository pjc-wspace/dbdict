# capability matrix — the five targets

created: 2026-07-31T12:53:03+12:00
session: `20260731-0930-revisit-app-objectives-and-goals-for-v0.3.0`, phase 2
status: **PARTLY SUPERSEDED** — capability research stands; type set does not

> ## ⚠ read this first
>
> The **capability research in this file is still valid** — the per-target
> facts, citations and probe output are unchanged and were the input to the
> decisions that followed.
>
> The **type set is not.** Decisions taken in dialogue after this file was
> written supersede it. See
> **`.claude-work/notes/20260731-1552-dbdict-type-system-decisions.md`**.
>
> What changed:
>
> | this file says | now |
> |---|---|
> | "LF" / "lingua franca" types | **"dbdict types"** — that terminology is retired |
> | 12 types | **10** — `decimal(p,s)` → V2+, `timestamptz` removed |
> | §3b `DECIMAL_TEXT(p,s)` convention | **dropped entirely** — `decimal` is out of V1 |
> | §3 "four encoding conventions" | **three** — `bool`, `date`, `timestamp` |
> | STRICT-vs-affinity left open | **decided: non-STRICT** |
> | `postgres` a V1 target | **V2** |
> | types named only | every type now has a **stated bit layout** |

Per-target capability for the five dataspec targets. Phase 3 embeds this in
`docs/vision-direction-0.3.0.md`.

**Evidence conventions used throughout:**

- **`[cited]`** — a link to official documentation with the supporting sentence
  quoted in §7 below.
- **`[measured]`** — probed locally on this machine, output recorded in §6.
  Versions: DuckDB CLI **v1.5.4**, SQLite **3.37.2** (Python 3.10.12 stdlib
  `sqlite3`).
- **`Inferred:`** — reasoning from a cited fact, not itself cited. Never
  presented as fact.
- **`unknown — needs probe: <name>`** — unresolved, with the probe that settles
  it named.

---

## 1. headline finding — the plan's cost model was wrong

`goal.md` predicted `duckdb → ducklake → postgres → sqlite` ≈ flat cost, with a
single step up to `hdf5`. **That is falsified.** SQLite is affinity-typed, not
declared-typed, and needs the *same four encoding conventions* as HDF5.

The corrected shape is three tiers, not two:

```
duckdb ≈ ducklake ≈ postgres        native types, COMMENT ON, SQL constraint queries
        │                            (one gap: postgres has no 1-byte integer)
        ▼
      sqlite                         4 encoding conventions; no COMMENT ON;
        │                            widths unenforced — but keeps DDL,
        │                            declared types, and SQL constraint queries
        ▼
       hdf5                          same 4 encoding conventions, AND no DDL,
                                     no comment statement, no SQL at all
```

A second `goal.md` claim also falls. It states *"8 of the 12 types are free on
every target and in every language."* Counting from the type rows below, the
types native on **all five** targets are **`float64` and `string` — two, not
eight.** The eight-free figure holds only across `duckdb`/`ducklake`/`postgres`.

> Both corrections are applied to `goal.md` in this phase rather than deferred,
> per the phase-2 verify rule.

---

## 2. type rows — the 12 dbdict type scalars

`native` = the target has a distinct declared type with the intended semantics.
`convention` = no native type; dbdict must pick an encoding and record it.

| dbdict type | duckdb | ducklake | postgres | sqlite | hdf5 |
|---|---|---|---|---|---|
| `bool` | native `BOOLEAN` [measured] | native — DuckDB SQL [cited] | native `boolean` [cited] | **convention** — no bool storage class; int 0/1 [cited] | **convention** — no bool in predefined types [cited] |
| `int8` | native `TINYINT` [measured] | native [cited] | **absent** — no 1-byte int; widen to `smallint` [cited] | **unenforced** — one INTEGER class, no widths [cited] | native `H5T_STD_I8LE` [cited] |
| `int16` | native `SMALLINT` [measured] | native [cited] | native `smallint` [cited] | **unenforced** — as above [cited] | native `H5T_STD_I16LE` [cited] |
| `int32` | native `INTEGER` [measured] | native [cited] | native `integer` [cited] | **unenforced** — as above [cited] | native `H5T_STD_I32LE` [cited] |
| `int64` | native `BIGINT` [measured] | native [cited] | native `bigint` [cited] | **unenforced** — as above [cited] | native `H5T_STD_I64LE` [cited] |
| `float32` | native `FLOAT` [measured] | native [cited] | native `real` (4 bytes) [cited] | **absent** — REAL is 8-byte only [cited] | native `H5T_IEEE_F32LE` [cited] |
| `float64` | native `DOUBLE` [measured] | native [cited] | native `double precision` [cited] | native `REAL` (8-byte IEEE) [cited] | native `H5T_IEEE_F64LE` [cited] |
| `string` | native `VARCHAR` [measured] | native [cited] | native `text`/`varchar` [cited] | native `TEXT` [cited] | native varlen UTF-8 [cited] |
| `date` | native `DATE` [measured] | native [cited] | native `date` [cited] | **convention** — no date storage class [cited] | **convention** — no date type [cited] |
| `timestamp` | native `TIMESTAMP` [measured] | native [cited] | native `timestamp without time zone` [cited] | **convention** — as above [cited] | **convention** — as above [cited] |
| `timestamptz` | native `TIMESTAMP WITH TIME ZONE` [measured] | native [cited] | native `timestamp with time zone` [cited] | **convention** — as above [cited] | **convention** — as above [cited] |
| `decimal(p,s)` | native, exact [measured] | native [cited] | native `numeric(p,s)`, exact [cited] | **convention** — NUMERIC affinity → REAL, **lossy** [measured] | **convention** — no decimal type [cited] |

> **The `int8`-on-Postgres gap is a real asymmetry, not a rounding error.**
> Postgres's smallest integer is two bytes, so `int8` must widen. Widening is
> value-safe (every `int8` fits a `smallint`) but breaks round-trip identity:
> `spec → DDL → db → draft → spec` returns `int16` where `int8` went in. The
> direction document should state this rather than let it be discovered.

> **SQLite integer widths are unenforced, not merely unmapped.** Every integer
> column is the same storage class, so an `int8` column will accept `10^18`
> without complaint. This is a *validation* consequence, not just a codegen
> one — `dbdict validate-data` against SQLite cannot assume the store enforced
> the declared width, and a range check becomes dbdict's job.

---

## 3. ~~the four encoding conventions~~ — SUPERSEDED

> **This whole section is superseded.** `decimal` moved to V2+ and
> `timestamptz` was removed, so only **three** types need an encoding
> (`bool`, `date`, `timestamp`). The `DECIMAL_TEXT(p,s)` proposal below is
> **withdrawn** — it is rejected by STRICT tables, and `decimal` is out of V1
> regardless. §3b's *affinity* findings remain correct and useful; its
> *conclusions* do not.
>
> Current scheme: §8 of
> `.claude-work/notes/20260731-1552-dbdict-type-system-decisions.md`.

### (superseded content follows, retained as the research record)

## ~~3. the four encoding conventions — decided~~

Both `sqlite` and `hdf5` need conventions for the same four types. The
precedent chosen is the **Apache Arrow columnar format**, because it is an
existing, widely-implemented, citable specification for exactly this problem —
inventing a private encoding would be strictly worse. Arrow definitions quoted
in §7.

### 3a. HDF5 — Arrow-shaped, integer-encoded

| dbdict type | encoding | marker attribute |
|---|---|---|
| `bool` | `H5T_STD_I8LE`, values 0/1 | `_dbdict_logical = "bool"` |
| `date` | `H5T_STD_I32LE` = days since 1970-01-01 (Arrow Date32) | `_dbdict_logical = "date"` |
| `timestamp` | `H5T_STD_I64LE` = microseconds since 1970-01-01, no zone | `_dbdict_logical = "timestamp"` |
| `timestamptz` | `H5T_STD_I64LE` = microseconds since 1970-01-01 **UTC** | `_dbdict_logical = "timestamptz"`, `_dbdict_tz = "<tz name>"` |
| `decimal(p,s)` | `H5T_STD_I64LE` two's-complement **unscaled** integer | `_dbdict_logical = "decimal"`, `_dbdict_precision`, `_dbdict_scale` |

The marker rides in an HDF5 attribute, which is native key–value and takes the
open attribute set 1:1 [cited, via `goal.md`]. Without the marker an `int64`
column of microseconds is indistinguishable from an `int64` column of counts —
the attribute is what makes `db → draft → spec` recover `timestamp` rather than
`int64`.

> `decimal` is capped at `int64` unscaled, i.e. 18–19 significant digits. Arrow
> permits 32/64/128/256-bit. **Decision: V1 supports `decimal(p,s)` with
> `p ≤ 18` on HDF5 and refuses higher precision** rather than shipping a
> 128-bit encoding no Julia driver reads naturally. Recorded as a V1 limit, not
> a permanent one.

### 3b. SQLite — text-encoded, and the affinity trap is real

The naive choice (declare `DATE`, `DECIMAL(18,4)`, store text) is **half
correct**, and the half that fails is not obvious. Both halves were measured:

| dbdict type | declared type | storage class reached | exact? |
|---|---|---|---|
| `date` | `DATE` | `text` ✓ | yes [measured] |
| `timestamp` | `TIMESTAMP` | `text` ✓ | yes [measured] |
| `timestamptz` | `TIMESTAMPTZ` | `text` ✓ | yes [measured] |
| `decimal(p,s)` | `DECIMAL(18,4)` | **`real`** ✗ | **no — `1.05*3 = 3.1500000000000004`** [measured] |
| `decimal(p,s)` | `DECIMAL_TEXT(18,4)` | `text` ✓ | yes — `'1.05'` verbatim [measured] |

The mechanism: all five declared types fall through to **NUMERIC affinity**
(rule 5 — none contains `INT`, `CHAR`, `CLOB`, `TEXT`, `BLOB`, `REAL`, `FLOA`
or `DOUB`) [cited]. NUMERIC affinity converts inserted text to INTEGER or REAL
*only if the text is a well-formed numeric literal* [cited]. ISO-8601 strings
contain dashes and colons, so they are **not** well-formed literals and survive
as TEXT. `"1.05"` **is** one, so it is silently converted to REAL and loses
exactness.

**Decision — the SQLite conventions:**

| dbdict type | declared type | stored as |
|---|---|---|
| `bool` | `BOOLEAN` | INTEGER 0/1 [cited] |
| `date` | `DATE` | TEXT `YYYY-MM-DD` |
| `timestamp` | `TIMESTAMP` | TEXT `YYYY-MM-DD HH:MM:SS[.SSS]` |
| `timestamptz` | `TIMESTAMPTZ` | TEXT ISO-8601 with offset |
| `decimal(p,s)` | **`DECIMAL_TEXT(p,s)`** | TEXT, exact decimal digits |

> **Why `DECIMAL_TEXT` rather than plain `TEXT`.** The declared type string is
> what `db → draft → spec` reads back, and it is preserved verbatim by
> `PRAGMA table_info` [measured]. Declaring plain `TEXT` would give exactness
> but lose `decimal(18,4)` — the drafted spec would say `string`. The token
> `DECIMAL_TEXT` contains the substring `TEXT`, so affinity rule 2 fires before
> rule 5 and the column gets TEXT affinity [cited], while `PRAGMA table_info`
> still returns `DECIMAL_TEXT(18,4)` [measured]. Both properties at once.
>
> The cost is a non-standard type name in the generated DDL. Acceptable given
> the research-tool positioning, and it is *visible* rather than silent — a
> reader who has never seen `DECIMAL_TEXT` will look it up, whereas silent
> float corruption of monetary values is discovered much later and much worse.

> The ISO-8601 text choice for dates is also the encoding SQLite's own date and
> time functions accept [cited], so `date(col)` and friends keep working on a
> dbdict-generated SQLite store. Julian-day REAL and Unix-epoch INTEGER are the
> two alternatives SQLite documents; both were rejected because they are not
> human-readable in a store whose main use is being poked at by hand.

---

## 4. capability rows

| capability | duckdb | ducklake | postgres | sqlite | hdf5 |
|---|---|---|---|---|---|
| **schema generation (DDL)** | yes — `CREATE TABLE` [measured] | yes — DuckDB SQL; **no PK/FK/UNIQUE/CHECK** [cited] | yes [cited] | yes — `CREATE TABLE` [measured] | **no DDL** — datasets created via the library API; `Inferred:` from HDF5 being a C library API with no SQL surface [cited] |
| **type oracle** (read types back) | `duckdb_columns()` / `DESCRIBE` [measured] | `Inferred:` same, from *"used just like any other DuckDB database"* [cited] — probe: `attach-ducklake-describe` | `information_schema.columns` — `unknown — needs probe: pg-type-oracle` (no server available here) | `PRAGMA table_info` — returns declared type verbatim [measured] | `H5Tget_class`/`H5Tget_size` + the `_dbdict_logical` attribute; `Inferred:` from the datatype properties [cited] |
| **metadata surface** | `COMMENT ON`; read via `duckdb_tables()`/`duckdb_columns()` [measured] | `COMMENT ON`; stored in `ducklake_tag` / `ducklake_column_tag` [cited] | `COMMENT ON`; read via `obj_description`/`col_description` [cited] | **no `COMMENT ON` statement** — SQLite's `comment` is `--`/`/* */` syntax, *"treated as whitespace by the parser"* [cited]. But DDL comments **survive verbatim** in `sqlite_schema.sql` [measured] | native attributes, key–value, open set 1:1 [cited] |
| **`_dbdict_*` side table** | yes | yes | yes | yes | n/a — attributes serve this role |
| **D01–D05 constraint checks** | yes — SQL [cited] | yes — SQL; note these are *queries*, unaffected by DuckLake's lack of *declared* constraints [cited] | yes — SQL | yes — SQL | **no** — no query engine; must be computed in-process over datasets |
| **in-process guarantee** | **holds** — *"does not run as a separate process, but completely embedded within a host process"* [cited] | **conditional** — holds with a DuckDB or SQLite catalog, **breaks** with a Postgres catalog [cited] | **BREAKS** — requires a running `postgres` server process [cited] | **holds** — *"an in-process library"*, *"does not have a separate server process"* [cited] | **holds** — `Inferred:` HDF5 is a linked C library with no server component [cited] |
| **round-trip** `spec→DDL→db→draft→spec` | identity for all 12 [measured] | `Inferred:` identity — probe: `ducklake-roundtrip` | **not identity** — `int8` returns as `int16` [cited] | **schema identity, value fidelity lost** — declared types recover [measured], but widths unenforced and `float32` unavailable [cited] | identity **only via** `_dbdict_logical` attributes; without them `date`/`timestamp`/`decimal` all return as integers |

> **The in-process row is a test-suite fact, not a feature list entry.**
> `CLAUDE.md` currently promises *"everything runs in-process; no runtime
> `duckdb` on PATH is needed by the library, the CLI, or the tests"*. That
> promise survives for `duckdb`, `sqlite` and `hdf5`, is conditional for
> `ducklake`, and **fails for `postgres`** — which means Postgres tests need a
> live server, i.e. either testcontainers, a CI service, or being skipped by
> default. Phase 4 must reword the guarantee per-target rather than delete it.

---

## 5. open items — every one names its probe

| # | open question | probe |
|---|---|---|
| 1 | Postgres type oracle — exact `information_schema.columns` output for the 11 mappable dbdict types | **`pg-type-oracle`**: start Postgres (docker `postgres:17`), create a table with all 11, dump `information_schema.columns`. Blocked here: no `psql`/server on this machine |
| 2 | Does DuckLake's `DESCRIBE` match DuckDB's for all 12? | **`ducklake-describe`**: `ATTACH 'ducklake:x.ducklake'`, create the 12-column table, `DESCRIBE`. Blocked: needs the `ducklake` extension installed |
| 3 | Does the DuckLake round-trip preserve types through Parquet? | **`ducklake-roundtrip`**: as above, then re-read after a snapshot |
| 4 | JLD2 ↔ HDF5 semantic portability for the encoded conventions | **`jld2-h5-crosscheck`** (already named in `goal.md`): write via JLD2, read with `h5py`, report what survives. Blocked: no `h5py` on this machine |
| 5 | Do SQLite DDL comments survive `VACUUM` / `ALTER TABLE`? | **`sqlite-comment-durability`**: create with comments, `VACUUM`, `ALTER TABLE ADD COLUMN`, re-read `sqlite_schema.sql`. Matters because the comment *is* the metadata carrier on SQLite |

> Item 5 is the one that could change a decision. If comments do not survive
> `ALTER TABLE`, then SQLite's documentation story rests entirely on the
> `_dbdict_*` side table and the DDL-comment mirror should be dropped rather
> than shipped as a half-guarantee.

---

## 6. probe output (verbatim, this machine)

**SQLite 3.37.2 — comment preservation and decimal fidelity**

```
--- comments preserved? ---
line comment  : True
block comment : True
row: (1, 1.05, 'integer', 'real')
--- decimal exactness ---
(0.30000000000000004,)
--- PRAGMA table_info ---
(0, 'qty', 'BIGINT', 0, None, 0)
(1, 'price', 'DECIMAL(18,4)', 0, None, 0)
```

**SQLite 3.37.2 — affinity behaviour of the four convention types**

```
storage class per column: {'date': 'text', 'timestamp': 'text',
  'timestamptz': 'text', 'decimal(NUMERIC aff)': 'real',
  'decimal(TEXT aff)': 'text'}
declared types recoverable:
  d     -> DATE
  ts    -> TIMESTAMP
  tstz  -> TIMESTAMPTZ
  dec_n -> DECIMAL(18,4)
  dec_t -> DECIMAL_TEXT(18,4)
exactness:
  NUMERIC-affinity sum: 3.1500000000000004
  TEXT-affinity  raw  : '1.05'
```

**DuckDB v1.5.4 — all 12 dbdict types + `COMMENT ON` round-trip**

```
c_bool BOOLEAN | c_i8 TINYINT | c_i16 SMALLINT | c_i32 INTEGER | c_i64 BIGINT
c_f32 FLOAT | c_f64 DOUBLE | c_str VARCHAR | c_date DATE | c_ts TIMESTAMP
c_tstz TIMESTAMP WITH TIME ZONE | c_dec DECIMAL(18,4)   -- comment: 'column doc'
duckdb_tables(): t -> 'table doc'
DECIMAL(18,4)*3 = 0.3000     DOUBLE*3 = 0.30000000000000004
```

---

## 7. sources

**SQLite** — [Datatypes In SQLite](https://www.sqlite.org/datatype3.html):
five storage classes, *"NULL … INTEGER. The value is a signed integer, stored
in 0, 1, 2, 3, 4, 6, or 8 bytes depending on the magnitude of the value …
REAL. The value is a floating point value, stored as an 8-byte IEEE floating
point number … TEXT … BLOB"*; *"as soon as INTEGER values are read off of disk
and into memory for processing, they are converted to the most general datatype
(8-byte signed integer)"*; affinity is *"the recommended type for data stored in
that column. The important idea here is that the type is recommended, not
required. Any column can still store any type of data"*; the five affinities
*"TEXT, NUMERIC, INTEGER, REAL, BLOB"*; the determination rules — *"1. If the
declared type contains the string "INT" then it is assigned INTEGER affinity.
2. If the declared type of the column contains any of the strings "CHAR",
"CLOB", or "TEXT" then that column has TEXT affinity … 5. Otherwise, the
affinity is NUMERIC."*; NUMERIC behaviour — *"When text data is inserted into a
NUMERIC column, the storage class of the text is converted to INTEGER or REAL
(in order of preference) if the text is a well-formed integer or real literal,
respectively … If the TEXT value is not a well-formed integer or real literal,
then the value is stored as TEXT"*, and *"about 15.95 significant decimal
digits of the number are preserved"*; booleans — *"SQLite does not have a
separate Boolean storage class. Instead, Boolean values are stored as integers
0 (false) and 1 (true)"*; dates — *"SQLite does not have a storage class set
aside for storing dates and/or times"*, stored as *"TEXT as ISO8601 strings
("YYYY-MM-DD HH:MM:SS.SSS") … REAL as Julian day numbers … INTEGER as Unix
Time"*.

[SQL Comment Syntax](https://www.sqlite.org/lang_comment.html): *"Comments are
not SQL commands, but can occur within the text of SQL queries … Comments are
treated as whitespace by the parser."* — i.e. the `comment` entry in SQLite's
statement index is comment *syntax*, **not** a `COMMENT ON` statement.

[The Schema Table](https://www.sqlite.org/schematab.html): *"The
sqlite_schema.sql column stores SQL text that describes the object … The text
is usually a copy of the original statement used to create the object but with
normalizations applied"*. The five listed normalizations concern keyword case,
`TEMP`, database qualifiers and spaces; **the list is silent on comments** —
which is why comment survival was settled by probe rather than by reading.

[About SQLite](https://www.sqlite.org/about.html): *"SQLite is an in-process
library that implements a self-contained, serverless, zero-configuration,
transactional SQL database engine"*; *"Unlike most other SQL databases, SQLite
does not have a separate server process."*

**PostgreSQL** — [Data Types](https://www.postgresql.org/docs/current/datatype.html):
`boolean` *"logical Boolean (true/false)"*; `smallint` *"signed two-byte
integer"*, `integer` *"signed four-byte integer"*, `bigint` *"signed eight-byte
integer"* — **no one-byte integer appears in the table**; `real` *"single
precision floating-point number (4 bytes)"*, `double precision` *"double
precision floating-point number (8 bytes)"*; `character varying`/`text`
*"variable-length character string"*; `date` *"calendar date (year, month,
day)"*; `timestamp without time zone` *"date and time (no time zone)"*;
`timestamp with time zone` *"date and time, including time zone"*; `numeric`
(alias `decimal`) *"exact numeric of selectable precision"*.

[COMMENT](https://www.postgresql.org/docs/current/sql-comment.html): *"COMMENT
stores, replaces, or removes the comment on a database object."* Applies to
`TABLE` and `COLUMN` among many others; *"Only one comment string is stored for
each object"* — which is exactly why the open attribute set needs the
`_dbdict_*` side table and `COMMENT ON` can only mirror `description:`.
Retrieval: *"built-in functions that psql uses, namely `obj_description`,
`col_description`, and `shobj_description`."*

[Architectural Fundamentals](https://www.postgresql.org/docs/current/tutorial-arch.html):
*"A server process, which manages the database files, accepts connections to
the database from client applications … The database server program is called
`postgres`."*; *"the client and the server can be on different hosts. In that
case they communicate over a TCP/IP network connection."*

**DuckDB** — [Data Types Overview](https://duckdb.org/docs/current/sql/data_types/overview)
(type names, as already cited in `goal.md`).
[COMMENT ON](https://duckdb.org/docs/current/sql/statements/comment_on.html):
attaches metadata to catalog objects, implements *"PostgreSQL syntax"*; applies
to tables, columns, views, indexes, sequences, types, macros; read back via
`duckdb_tables()` and `duckdb_columns()`; limitations — schemas and databases
cannot be commented, nor objects with dependencies.
[Why DuckDB](https://duckdb.org/why_duckdb): *"DuckDB does not run as a
separate process, but completely embedded within a host process."*; *"there is
no DBMS server software to install, update and maintain."*; *"DuckDB has no
external dependencies, neither for compilation nor during run-time."*

**DuckLake** — [DuckLake introduction](https://ducklake.select/docs/stable/duckdb/introduction):
*"DuckLake is used just like any other DuckDB database."*; attached with
`ATTACH 'ducklake:my_ducklake.ducklake' AS my_ducklake;`; *"the DuckLake format
does not support indexes, primary keys, foreign keys, and `UNIQUE` or `CHECK`
constraints."*; *"DuckLake v1.0 is supported by DuckDB v1.5.2+."*
[Comments](https://ducklake.select/docs/stable/duckdb/advanced_features/comments):
`COMMENT ON` on tables, views and columns, stored transactionally — tables and
views in `ducklake_tag`, columns in `ducklake_column_tag`.
[Choosing a Catalog Database](https://ducklake.select/docs/stable/duckdb/usage/choosing_a_catalog_database):
*"can use PostgreSQL, SQLite or DuckDB as the catalog database"* — the source
of the conditional in-process row.

**HDF5** — [Datatypes (user guide)](https://support.hdfgroup.org/documentation/hdf5/latest/_h5_t__u_g.html):
classes *"Integer, Float, Character, Bitfield, Opaque, Enumeration, Reference,
Array, Variable-length, and Complex"*; *"The precision property identifies the
number of significant bits of a datatype and the offset property … identifies
its location."*
[Predefined Datatypes](https://support.hdfgroup.org/documentation/hdf5/latest/predefined_datatypes_tables.html):
explicit-width integers `H5T_STD_I8BE`/`I8LE` through 64-bit, signed and
unsigned; IEEE floats `H5T_IEEE_F16/F32/F64` in both endiannesses; string
`H5T_C_S1`. **No date/time and no decimal/fixed-point type appears in the
predefined tables** — the basis for the two `convention` cells.
[Attributes (user guide)](https://support.hdfgroup.org/documentation/hdf5/latest/_h5_a__u_g.html)
(as cited in `goal.md`): *"An HDF5 attribute is a small metadata object
describing the nature and/or intended usage of a primary data object"*,
attachable to *"a dataset, group, or committed datatype"*; caveats —
*"Attributes are assumed to be very small as data objects go"*, *"there is no
compression or chunking, and attributes are not extendable"*.
[h5py strings](https://docs.h5py.org/en/stable/strings.html): *"HDF5 supports
two string encodings: ASCII and UTF-8"*; `h5py.string_dtype()` creates
variable-length UTF-8 strings.

**Apache Arrow** (precedent for the encoding conventions) —
[Schema.fbs](https://github.com/apache/arrow/blob/main/format/Schema.fbs), the
file the [columnar specification](https://arrow.apache.org/docs/format/Columnar.html)
defers to: Date is *"either a 32-bit or 64-bit signed integer type representing
an elapsed time since UNIX epoch (1970-01-01)"* with *"Days (32 bits) since the
UNIX epoch"*; Timestamp is *"a 64-bit signed integer representing an elapsed
time since a fixed epoch, stored in either of four units: seconds,
milliseconds, microseconds or nanoseconds, and is optionally annotated with a
timezone"*, and *"If a Timestamp column has a non-empty timezone value, its
epoch is 1970-01-01 00:00:00 … in the *UTC* timezone"*; Decimal is *"Exact
decimal value represented as an integer value in two's complement"* with
precision *"Total number of decimal digits"* and scale *"Number of digits after
the decimal point '.'"*.

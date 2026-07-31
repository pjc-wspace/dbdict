# dbdict type system — decisions

created: 2026-07-31T15:52:28+12:00
revised: 2026-08-01 — temporal types adopt RFC 3339 / RFC 9557
session: `20260731-0930-revisit-app-objectives-and-goals-for-v0.3.0`, phase 2
status: **settled** — the SQLite encoding question is now closed

Supersedes the type-system content of
`.claude-work/notes/20260731-1253-capability-matrix.md`, which was written
before these decisions. That file's *capability research* stands; its *type
set* and its `decimal` conventions do not.

Evidence markers: **[cited]** = official docs, quoted here or in the matrix
note; **[measured]** = probed on this machine (DuckDB CLI v1.5.4, SQLite 3.37.2
via Python 3.10.12 stdlib); **`Inferred:`** = reasoning, not fact.

---

## 1. terminology — "dbdict types"

The type vocabulary is called **"dbdict types"**. The terms *lingua franca*
and *LF* are retired and must not appear in any document. Both `goal.md` and
the capability-matrix note have been swept.

## 2. the ten dbdict types

Types are **precisely defined**, so that "does this backend/driver support this
type?" is a mechanical check rather than a judgement call. Two kinds of
definition, both exact:

- **numeric and boolean types** — defined by **bit layout**
- **temporal types** — defined by a **pinned RFC profile** (lexical form)

| dbdict type | definition | width |
|---|---|---|
| `bool` | `0` = false, `1` = true; no other value legal | 8 bits |
| `int8` `int16` `int32` `int64` | two's complement, signed | 8 / 16 / 32 / 64 bits |
| `float32` `float64` | IEEE 754 binary32 / binary64 | 32 / 64 bits |
| `string` | UTF-8, unbounded | variable |
| `date` | **RFC 3339 `full-date`** — `YYYY-MM-DD`. No time, no zone. | 10 ASCII bytes |
| `timestamp` | **RFC 3339 `date-time`**, microsecond precision; optionally an **RFC 9557 (IXDTF)** `[Zone]` suffix | 27–61 ASCII bytes |

**Ten types.** `string` and `timestamp` are the two without a fixed width —
`string` inherently, `timestamp` only when it carries a variable-length IANA
zone name.

> **Naming: semantic, not width-carrying.** `date` and `timestamp`, **not**
> Arrow's `date32` / `timestamp64`. Decided after the temporal types became
> lexical RFC forms: a `32` suffix would describe nothing real, since the value
> is a 10-byte ASCII string rather than a 32-bit integer. Width-carrying names
> would actively mislead. The numeric types already carry their width in the
> name (`int32`, `float64`), where it is accurate.

Fixed widths, measured, for sizing fixed-size storage:

| form | example | bytes |
|---|---|---|
| `full-date` | `2026-07-31` | 10 |
| `date-time`, µs, `Z` | `2026-07-31T12:00:00.123456Z` | 27 |
| `date-time`, µs, numeric offset | `2026-07-31T12:00:00.123456+12:00` | 32 |
| IXDTF, longest IANA zone name | `…Z[America/Argentina/ComodRivadavia]` | 61 |

> `bool` is 8 bits rather than 1 because no target stores a 1-bit boolean.
> Stating 8 makes the check honest.

## 3. what is *not* a dbdict type

| not a type | why |
|---|---|
| `decimal(p,s)` | **V2+.** Little used in practice; every available encoding was unattractive — SQLite stores it as lossy `REAL` [measured], and the `decimal.c` extension is not in the amalgamation and must be loaded per connection [cited]. |
| `timestamptz` | **Removed permanently.** Zone information now rides in the `timestamp` value itself (RFC 9557) or alongside it — §6. |
| `datestamp` | **Never introduced.** A "date with a time zone" has no standards-compliant spelling *and* is not a distinct value — §6. |
| compound types | Deferred, unchanged from `goal.md`. |

## 4. target roster — Postgres moves to V2

| target | V1 | note |
|---|---|---|
| `duckdb` | **yes** | reference target |
| `ducklake` | **yes** | DuckDB SQL dialect and types [cited] |
| `sqlite` | **yes** | temporal types stored lexically — §8 |
| `hdf5` | **yes** | temporal types stored lexically — §8 |
| `postgres` | **V2 — TODO** | see below |

**Postgres → V2**, because:

1. It is the only target that **breaks the in-process guarantee** — it needs a
   running `postgres` server process [cited], so its tests need a container or
   a CI service.
2. It has a genuine type gap: **no 1-byte integer** [cited], so `int8` widens
   to `smallint` and `spec → DDL → db → draft → spec` is not identity.
3. Its capability cells could not be resolved on this machine (no server), so
   it is the only target still carrying an `unknown` — probe `pg-type-oracle`.

> Deferring the Postgres *target* does not defer DuckLake, which can use
> Postgres as a *catalog* database [cited]. Separate roles.

## 5. SQLite emission — non-STRICT, with deliberately chosen affinities

**dbdict generates non-STRICT SQLite tables.** Affinities are chosen per type
and the reasoning is recorded, so this is a decision and not a default.

Rejected: `STRICT` tables. They enforce the declared type [measured — `'abc'`
into an `INT` column is rejected] but collapse the vocabulary to
*"INT, INTEGER, REAL, TEXT, BLOB, ANY. No other datatype names are allowed"*
[cited]. Measured: `BIGINT`, `BOOLEAN` and `DATE` are all **rejected outright**
in a STRICT table.

Three reasons non-STRICT wins:

1. **It matches dbdict's existing correctness model** — correctness is
   established by *querying after load*, not by constraining at insert. D01–D05
   are after-the-fact queries and the DDL generator already omits
   `PRIMARY KEY`/`NOT NULL`/`UNIQUE`. Store-level enforcement was never the
   mechanism.
2. **Declared types stay readable and recoverable** — `PRAGMA table_info`
   returns the declared type string verbatim [measured], so `BIGINT` and `DATE`
   survive into `draft`. Under STRICT they could not be written at all.
3. **Brown-field needs it** — `draft` runs against databases dbdict did not
   create: no sidecar, no STRICT guarantee. The declared-type route is the only
   one that works there.

**Cost, stated plainly:** nothing prevents a wrong-typed value entering. Type
checking becomes dbdict's job — a value scan folded into the existing D01–D05
pass, not new machinery.

> **STRICT would not have solved the width problem anyway.** `INT` in a STRICT
> table is 8-byte, so `int8`/`int16`/`int32` are unenforced either way. STRICT
> buys storage-class enforcement (int vs text vs blob), never range checking.

## 6. time zones

### the model

- **`date` never carries a zone.** A calendar day has no position on the
  timeline, so a zone cannot shift it. There is no operation "convert this date
  to another zone".
- **`timestamp` may carry a zone**, in the value, per RFC 9557:
  `2026-07-31T12:00:00.123456Z[Pacific/Auckland]`.
- **Absent any zone information, UTC is assumed.**

### why there is no `datestamp`

A "date with a time zone" fails on two independent grounds:

1. **No compliant spelling exists.** RFC 3339 puts `time-offset` inside
   `full-time`, and `date-time = full-date "T" full-time` — an offset can
   attach only to a *time* [cited]. RFC 9557 extends only
   `date-time-ext = date-time suffix`, so **IXDTF cannot attach to a date-only
   value** either [cited]. Both `2026-07-31+12:00` and
   `2026-07-31[Pacific/Auckland]` are non-standard.
2. **It is not a distinct value.** *Decision: the meaning is **provenance*** —
   "this calendar day, as reckoned in Auckland". The zone is context describing
   *how the day was determined*, not part of the day. Two dates with the same
   digits and different provenance zones denote **the same day**.

Provenance, where it matters, is a **column attribute** on a `date` column, not
a type.

> The rejected alternative reading was *interval* — "the 24-hour span that is
> that day in Auckland". That is genuinely different data, but it is not a date
> at all: it is a pair of instants, and would need a start plus a duration.
> Recorded so the question is not reopened without noticing it changed.

### where the zone is physically stored

**The canonical form can express a zone that no native SQL timestamp column can
hold.** This is measured, not theoretical:

```
DuckDB, one stored TIMESTAMPTZ value inserted as '2026-07-31 12:00:00+12:00':
  session TimeZone = UTC               -> 2026-07-31 00:00:00+00
  session TimeZone = Pacific/Auckland  -> 2026-07-31 12:00:00+12
  session TimeZone = America/New_York  -> 2026-07-30 20:00:00-04
```

The value is an *instant*; the zone is display-only and the input zone is gone.
PostgreSQL is explicit about the same behaviour: *"the value is stored
internally as UTC, and the originally stated or assumed time zone is not
retained."* [cited]

Consequently the zone must be stored **alongside** the instant on any target
whose native timestamp type discards it:

| scope | attribute | use |
|---|---|---|
| per row | `timezone_from: <column>` | a sibling `string` column holds the zone |
| per column | `timezone: "Pacific/Auckland"` | one fixed zone for the column |
| per table / dataspec | `timezone:` | default for temporal columns in scope |
| absent | — | **UTC** |

Precedence: column `timezone_from:` → column `timezone:` → table → dataspec →
UTC.

> **Confirmed: `timezone:` and `timezone_from:` are kept**, alongside RFC 9557
> in-value zones rather than replaced by them.
>
> They are **a storage mapping, not a modelling choice.** On SQLite and HDF5
> the zone rides inside the lexical value and the attributes are unnecessary;
> on DuckDB, DuckLake and Postgres they are the only way a zone survives a
> round-trip, because those native types discard it [measured]. Same model,
> different mechanics per target.
>
> They also remain the mechanism for **`date` provenance**, which has no
> in-value form on any target (§6, "why there is no `datestamp`").

**Invariant to state loudly wherever `timestamp` is documented:** the *instant*
is always UTC. A zone — in the value or in an attribute — records where the
instant was observed. **It never changes which instant is meant.**

### why `date` and `timestamp` stay separate types

Not because dates break under zone conversion — they cannot. Because declaring
`date` is a **prohibition**: it tells every driver and every generated client
*this value has no time and no zone, do not attach one*. With only `timestamp`,
a calendar day would have to be stored as an instant, and that write is the one
step where a date can acquire a wrong day.

The error is real but lives at the **type boundary**, and is normally crossed
by a driver rather than by the user:

- Python: *"The default 'timestamp' converter ignores UTC offsets in the
  database and always returns a naive `datetime.datetime` object."* [cited]
- rusqlite [issue #1039]: a `DateTime<FixedOffset>` is converted to UTC on
  write and the offset lost; reading back matches **"only because read in same
  timezone"** — correct on the author's machine, wrong on anyone else's.

## 7. strings — no length required anywhere

**Every target has an unbounded variable-length string type**, so `string` is
unbounded and no length is ever structural:

| target | unbounded string |
|---|---|
| `duckdb` / `ducklake` | `VARCHAR` [measured / cited] |
| `sqlite` | `TEXT` [cited] |
| `hdf5` | copy `H5T_C_S1` then `H5Tset_size(type, H5T_VARIABLE)` [cited] — *"variable-length strings will transparently accommodate ASCII strings or UTF-8 strings"* |
| `postgres` (V2) | `text` [cited] |

Length limits are **optional validation constraints**:

| attribute | unit | checked as |
|---|---|---|
| `max_chars: N` | Unicode characters | character count |
| `max_bytes: N` | UTF-8 bytes | encoded byte length |

Two names because the targets disagree on the unit: Postgres's `varchar(n)`
counts *"n characters (not bytes)"* [cited]; HDF5's `H5Tset_size` is *"the
length of the string, in bytes"* [cited]. Measured: `"café €10"` is **8
characters, 11 bytes**.

### HDF5 variable-length strings work — but cannot be compressed

Confirmed from the HDF5 docs [cited]:

```c
strtype = H5Tcopy(H5T_C_S1);
status  = H5Tset_size(strtype, H5T_VARIABLE);
```

The cost is larger than a general "heap overhead". Verbatim:

> *"Under the covers, variable-length strings are stored in a heap, potentially
> impacting efficiency in the following ways: Heap storage requires more space
> than regular raw data storage. Heap access generally reduces I/O efficiency
> because it requires individual read or write operations for each data element
> rather than one read or write per dataset or per data selection.* **Chunking
> and filters, including compression, are not available for heaps.**"

**So `max_bytes:` is not only a validation constraint — on HDF5 it is the
switch that enables chunking and compression.** A `string` column with no
`max_bytes:` is stored variable-length and is therefore *uncompressible*; one
with `max_bytes: N` can be a fixed-size `H5T_C_S1` of N bytes, contiguous,
chunkable and compressible.

That is a real reason to declare `max_bytes:` on wide string columns, and it
should be documented as a performance lever rather than buried as a validation
nicety. It does not change the default — `string` stays unbounded, because
correctness should not require a performance annotation.

If fixed-size is taken, the padding mode must be recorded (null-terminate,
null-pad, space-pad [cited]) and an over-length value must be an **error, not a
truncation**.

## 8. physical storage — native where it exists, lexical where it does not

**The canonical definition is the RFC form. Physical storage is per target.**

| dbdict type | duckdb / ducklake | sqlite | hdf5 | postgres (V2) |
|---|---|---|---|---|
| `bool` | `BOOLEAN` | `BOOLEAN` decl → integer `0`/`1` [cited] | `H5T_STD_I8LE`, `0`/`1` | `boolean` |
| `int8…int64` | `TINYINT`…`BIGINT` | `TINYINT`…`BIGINT` decl (width **unenforced**) | `H5T_STD_I8LE`…`I64LE` | `smallint`… (**no `int8`**) |
| `float32` / `float64` | `FLOAT` / `DOUBLE` | `FLOAT` decl → **8-byte REAL**; `float32` **unavailable** | `H5T_IEEE_F32LE` / `F64LE` | `real` / `double precision` |
| `string` | `VARCHAR` | `TEXT` | varlen UTF-8 | `text` |
| `date` | **native `DATE`** | **ISO text** `YYYY-MM-DD` | **ISO text**, fixed 10 bytes | **native `date`** |
| `timestamp` | **native `TIMESTAMP`/`TIMESTAMPTZ`** + zone alongside | **ISO text** (RFC 3339, optional IXDTF suffix) | **ISO text** | **native `timestamp`** + zone alongside |

**Rationale for lexical-on-SQLite** — this is what the drivers already do, so
integers would have fought the ecosystem:

| driver | `date` | `timestamp` |
|---|---|---|
| Python `sqlite3` | ISO 8601 text [cited] | ISO 8601 text, µs precision [cited] |
| Rust `rusqlite` (chrono) | text `%F` [cited] | text `%F %T%.f` [cited] |
| Julia `SQLite.jl` | **unresolved** — open issue *"Convert date/datetimes to text when storing"*; docs say non-native values are serialized to `BLOB`. `Inferred:` — **needs probe `sqlitejl-temporal`** |

> Writing `int64` microseconds into a column declared `TIMESTAMP` would break
> Python's converter (expects ISO) and rusqlite's `FromSql for NaiveDateTime`
> (expects a string). The encoding would have broken every stock driver on the
> target chosen for portability.
>
> ISO text also keeps SQLite's own date and time functions working — they
> accept *"TEXT as ISO8601 strings"* [cited] — and µs precision survives
> exactly: 6 fractional digits *is* microseconds.

**On HDF5** the lexical form is likewise the storage, and a marker attribute is
still required — a 10-byte string column that is a `date` is otherwise
indistinguishable from one that is a `string`:

- `_dbdict_logical = "date" | "timestamp" | "bool"` on the dataset. HDF5
  attributes are native key–value and take the open attribute set 1:1 [cited].

### HDF5 temporal columns must be fixed-size

The sizing question is **settled by the compression finding in §7**: HDF5
variable-length strings get no chunking and no filters, so a variable-length
temporal column would be uncompressible — and ISO-8601 columns are among the
most compressible data there is, since consecutive values share long prefixes.

| dbdict type | HDF5 storage |
|---|---|
| `date` | fixed-size `H5T_C_S1`, **10 bytes**, null-padded |
| `timestamp`, no zone suffix | fixed-size, **27 bytes** |
| `timestamp` with IXDTF zone | fixed-size, sized to the longest zone name in the column, **≤ 61 bytes** |

> **The honest cost of lexical-on-HDF5.** A `timestamp` at 27–61 bytes per row
> is 3.4–7.6× the 8 bytes an `int64` µs encoding would use, before compression.
> The offsetting arguments: it is self-describing, it needs no epoch
> convention, it survives JLD2 without a Julia-specific reader, and — because
> it is now fixed-size — it compresses well, which the integer encoding would
> also have needed chunking to beat.
>
> **`Inferred:`** that ISO-8601 columns compress to well under the integer
> encoding's raw size. Not measured. **Probe `hdf5-temporal-compression`**:
> write 10⁶ timestamps both ways, apply gzip/szip, compare on-disk bytes and
> read throughput. Worth running before the encoding is frozen in the spec.

## 9. ~~SQLite date/timestamp: integers or ISO text?~~ — RESOLVED

**ISO text**, and it is no longer a deviation: §8 makes "native where it
exists, lexical where it does not" the general rule, and SQLite simply has no
native temporal type. The earlier framing — one byte-identical scheme shared
with HDF5 — was the wrong goal. What is shared is the **type definition**; the
serialization is properly per-target, which is what a type-mapping layer is
for.

---

## 10. sources

Sources for the *capability* claims (DuckDB/DuckLake/Postgres/SQLite/HDF5 type
rosters, `COMMENT ON`, in-process, SQLite affinity rules) are in §7 of
`.claude-work/notes/20260731-1253-capability-matrix.md` and are not repeated
here. Below are the sources for claims **new to this document**.

**Temporal formats**

- [RFC 3339](https://www.rfc-editor.org/rfc/rfc3339) — `full-date =
  date-fullyear "-" date-month "-" date-mday`; `full-time = partial-time
  time-offset`; `date-time = full-date "T" full-time`. The offset lives inside
  `full-time`, so **it cannot attach to a date alone**. `Z` is *"a suffix
  which, when applied to a time, denotes a UTC offset of 00:00"*; numeric
  offsets are *"calculated as 'local time minus UTC'"*.
- [RFC 9557](https://www.rfc-editor.org/rfc/rfc9557) (IXDTF) — *"defines an
  extension to the timestamp format defined in RFC 3339 for representing
  additional information, including a time zone"*, e.g.
  `2022-07-08T00:14:07+01:00[Europe/London]`. Grammar extends only
  `date-time-ext = date-time suffix`, so **IXDTF cannot attach to a date-only
  value**. A critical suffix is marked with `!`, and a recipient *"MUST NOT act
  on the IXDTF string unless it can process the suffix tag as specified"*.
  `Z` with a named zone *"creates no inconsistency — the application calculates
  the local offset from zone rules"*.
- [PostgreSQL Date/Time Types](https://www.postgresql.org/docs/current/datatype-datetime.html)
  — `timestamp` 8 bytes, resolution 1 microsecond; `date` 4 bytes, resolution
  1 day; and *"For `timestamp with time zone` values, an input string that
  includes an explicit time zone will be converted to UTC … the value is stored
  internally as UTC, and the originally stated or assumed time zone is not
  retained."*

**SQLite drivers**

- [Python `sqlite3`](https://docs.python.org/3/library/sqlite3.html) — default
  adapters convert `datetime.date` and `datetime.datetime` to *"strings in ISO
  8601 format"*; the `timestamp` converter truncates fractional parts *"to 6
  digits for microsecond precision"*. **Deprecated as of Python 3.12**: *"The
  default adapters and converters are deprecated as of Python 3.12."* Caveat:
  *"The default 'timestamp' converter ignores UTC offsets in the database and
  always returns a naive `datetime.datetime` object."*
- [rusqlite `types/chrono.rs`](https://docs.rs/rusqlite/latest/src/rusqlite/types/chrono.rs.html)
  — `NaiveDate` is stored as text formatted `%F` (`YYYY-MM-DD`);
  `NaiveDateTime` as text formatted `%F %T%.f`.
- [rusqlite issue #1039](https://github.com/rusqlite/rusqlite/issues/1039) —
  *"Timezone offset is not preserved when reading/writing `chrono::DateTime`s"*;
  a `DateTime<FixedOffset>` is UTC-converted on write and the offset lost, with
  the round-trip matching **only because read in the same timezone**.
- [SQLite.jl issue #160](https://github.com/JuliaDatabases/SQLite.jl/issues/160)
  — open request *"Convert date/datetimes to text when storing"*. Its existence
  implies text is **not** the current behaviour.
  [SQLite.jl docs](https://juliadatabases.org/SQLite.jl/stable/): *"By default,
  `sqlreturn` maps the returned value to a native SQLite type or, failing that,
  serializes the julia value and stores it as a `BLOB`."* `Inferred:` — that
  statement is about `sqlreturn`, not necessarily about table loads, so the
  temporal behaviour is **unconfirmed**; probe `sqlitejl-temporal`.

**SQLite typing and exactness**

- [STRICT Tables](https://www.sqlite.org/stricttables.html) — *"if the "STRICT"
  table-option keyword is added to the end, after the closing ")", then strict
  typing rules apply to that table"*; permitted types are *"INT, INTEGER, REAL,
  TEXT, BLOB, ANY. No other datatype names are allowed"*. Added in *"version
  3.37.0 (2021-11-27)"*.
- [Floating Point Numbers](https://sqlite.org/floatingpoint.html) — *"Floating
  point values are approximate."*; for a price column *"the only cents value
  that can be exactly represented are 0.00, 0.25, 0.50, and 0.75"*, with
  `47.49` stored as `47.49000000000000198951966012828052043914794921875`. The
  decimal extension *"provides arbitrary-precision decimal arithmetic on
  numbers stored as text strings"* and a *"'decimal' collating sequence that
  compares decimal text strings in numeric order"*, but *"The decimal extension
  is not (currently) part of the SQLite amalgamation. However, it is included
  in the CLI."*
- [Run-Time Loadable Extensions](https://www.sqlite.org/loadext.html) —
  *"For security reasons, extension loading is turned off by default."*
- [SQL Comment Syntax](https://www.sqlite.org/lang_comment.html) — *"Comments
  are treated as whitespace by the parser."* — SQLite's `comment` entry is
  comment *syntax*, not a `COMMENT ON` statement.

**HDF5 strings**

- [Datatype Basics](https://support.hdfgroup.org/documentation/hdf5/latest/_l_b_datatypes.html)
  — fixed: `strtype = H5Tcopy(H5T_C_S1); status = H5Tset_size(strtype, 5);`
  variable: `H5Tset_size(strtype, H5T_VARIABLE);`. And the cost of
  variable-length: *"Heap storage requires more space than regular raw data
  storage. Heap access generally reduces I/O efficiency because it requires
  individual read or write operations for each data element rather than one
  read or write per dataset or per data selection."* plus **"Chunking and
  filters, including compression, are not available for heaps."**
- [Datatypes user guide](https://support.hdfgroup.org/documentation/hdf5/latest/_h5_t__u_g.html)
  — for string datatypes, *"Set the length of the string, in bytes"* (so HDF5
  sizes strings in **bytes**); character sets `H5T_CSET_ASCII` and
  `H5T_CSET_UTF8`; padding options *"Null terminate (as C does)"*, *"Pad with
  zeros"*, *"Pad with spaces (as FORTRAN does)"*.
- [PostgreSQL Character Types](https://www.postgresql.org/docs/current/datatype-character.html)
  — *"Both of these types can store strings up to `n` characters (not bytes) in
  length"* (so Postgres sizes strings in **characters**), and *"It wouldn't be
  useful to change this because with multibyte character encodings the number
  of characters and bytes can be quite different."*
- [h5py strings](https://docs.h5py.org/en/stable/strings.html) — *"HDF5
  supports two string encodings: ASCII and UTF-8"*; `h5py.string_dtype()`
  creates variable-length UTF-8 strings.

## decision log

1. Vocabulary is **"dbdict types"**; *lingua franca* / *LF* retired
2. Numeric types defined by **bit layout**; temporal types by **RFC profile**
3. **10 types**: `bool`, `int8/16/32/64`, `float32/64`, `string`, `date`, `timestamp`
4. **`decimal(p,s)` → V2+**
5. **`timestamptz` removed**
6. **`datestamp` never introduced** — no compliant spelling, and a zoned date
   is provenance, not a distinct value
7. **`date` = RFC 3339 `full-date`**; **`timestamp` = RFC 3339 `date-time`**,
   µs, optional **RFC 9557** `[Zone]` suffix
8. **Zone is provenance/observation context; the instant is always UTC**
9. **Zone storage**: in-value on SQLite/HDF5; alongside via
   `timezone:` / `timezone_from:` on DuckDB/DuckLake/Postgres, because their
   native types discard it [measured]
10. **`string` unbounded**; `max_chars:` / `max_bytes:` optional constraints —
    and on HDF5 `max_bytes:` doubles as the **compression switch**, because
    variable-length strings get no chunking or filters [cited]
11. **HDF5 temporal columns are fixed-size strings** (10 / 27 / ≤61 bytes) so
    they remain compressible
12. **SQLite emission is non-STRICT** with deliberately chosen affinities
13. **Postgres → V2**; V1 targets are `duckdb`, `ducklake`, `sqlite`, `hdf5`
14. **Physical storage: native where it exists, lexical where it does not**
15. **`decimal.c` rejected** — not in the amalgamation, per-connection load,
    off by default [cited]

## still open

- probe **`hdf5-temporal-compression`** — the one open item that could revisit a
  settled decision. Lexical temporal columns cost 27–61 bytes/row against 8 for
  an integer encoding; the claim that compression closes that gap is
  `Inferred:`, not measured (§8).
- probe **`sqlitejl-temporal`** — what does SQLite.jl actually write for
  `Date`/`DateTime`? Julia 1.12.6 is on this machine but SQLite.jl is not
  installed. Matters because Julia is the first codegen target.
- probe **`pg-type-oracle`** — deferred with Postgres to V2
- probe **`sqlite-comment-durability`** — do DDL comments survive `VACUUM` and
  `ALTER TABLE`? The comment is a metadata carrier on SQLite
- probe **`jld2-h5-crosscheck`** — JLD2 ↔ HDF5 semantic portability

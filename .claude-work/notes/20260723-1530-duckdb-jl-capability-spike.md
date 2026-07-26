# duckdb.jl capability spike — findings

> **HISTORICAL RECORD — superseded 2026-07-26.** the current consolidated
> reference is `research/duckdb-driver-jl/reference.md`, which merges this
> spike, the driver study (`20260725-1007`), phase-1 verification, and
> benchmark results. six claims in this note were corrected by later
> measurement — see that document's Appendix A. read it, not this, for
> current behaviour.

phase 1 of session `20260723-1109-julia-read-write-codegen`. all results
measured against DuckDB.jl **1.5.2** (latest release; pins DuckDB_jll 1.5.2)
on julia 1.12.6, spike scripts in the session's `spike/` dir. the bundled
rust duckdb is 1.5.4.

## 1. read path (query → DataFrame) — confirmed, with deviations

measured type table (all columns arrive as `Union{Missing, T}`):

| duckdb type    | julia type (measured)                          |
|----------------|------------------------------------------------|
| BOOLEAN        | Bool                                           |
| INTEGER        | Int32                                          |
| BIGINT         | Int64                                          |
| HUGEINT        | Int128                                         |
| DOUBLE         | Float64                                        |
| DECIMAL(18,4)  | FixedPointDecimals.FixedDecimal{Int64, 4}      |
| VARCHAR        | String                                         |
| BLOB           | **Base.CodeUnits{UInt8, String}** (not Vector{UInt8}) |
| DATE / TIME    | Dates.Date / Dates.Time                        |
| TIMESTAMP      | Dates.DateTime                                 |
| TIMESTAMPTZ    | Dates.DateTime, **normalized to UTC, offset dropped** |
| UUID           | Base.UUID                                      |
| ENUM           | String                                         |
| LIST (T[])     | Vector{Union{Missing, T}}                      |
| STRUCT         | NamedTuple{names} — **field types not in the type** |
| MAP            | Dict{Any, Any} — untyped                       |
| ARRAY (T[n])   | **UNSUPPORTED — query throws** (see §5)        |

deviations vs the main-branch result.jl table from the goal discussion:
BLOB (CodeUnits), and ARRAY (unreleased). struct NamedTuples carrying only
field *names* means downstream field access is `Any`-typed — the argument
for generated typed structs (phase 6).

## 2. write paths — no single binding path covers the matrix

measured matrix (spike `write_path.jl`, one table per type × path):

| type    | appender | register_df + INSERT | prepared ? |
|---------|----------|----------------------|------------|
| bool/int/bigint/double/varchar/date/time/ts/enum | ok | ok | ok |
| hugeint | ok       | ok                   | ERR (bind) |
| decimal | ok       | ok                   | ERR (bind) |
| uuid    | ok       | ERR (logical_type)   | ERR (bind) |
| blob    | ERR      | ERR (logical_type)   | ok         |
| list    | ok       | ERR (logical_type)   | ok         |
| struct  | ERR      | ERR                  | ERR        |
| map     | ERR      | ERR                  | ERR        |
| nested  | ERR      | ERR                  | ERR        |

**STRUCT/MAP cannot be written by any value-binding path.**

**path D — generated SQL literals — works for everything tested**, including
quote escaping (`o''brien`), nested struct-in-struct, and MAP
(`literal_and_structarrays.jl`, round-trip verified).

**path E — flatten + SQL reassembly — works for struct columns**
(`flatten_write.jl`): register the struct's *field arrays* as flat columns
(a StructArray's in-memory layout gives them for free), then
`INSERT ... SELECT {'x': x, 'y': y} FROM view`. verified: flat structs,
NULL struct rows (validity column + CASE WHEN), nested struct-of-struct via
recursive flattening. boundary: list-typed fields can't be registered, so
structs containing lists stay on the literal path.

→ writer strategy recommendation for phase 5, three tiers per table:
1. appender when every column is appender-safe (fast path)
2. register-flattened + SQL struct reassembly when struct columns' leaf
   fields are all registerable (vectorized, no serialization; natural fit
   for StructArray input, works from Vector{NamedTuple} too)
3. batched `INSERT INTO ... VALUES` generated literals for the remainder
   (maps, structs containing lists, blob) — universal fallback
final call at phase 5 design time.

## 2b. addendum (review finding 3): literal path measured over the full matrix

`literal_matrix.jl`, 27 cells, **all pass**, each type × {value, NULL}:
bool, all int widths incl. hugeint 2^100 and unsigned, float/double,
NaN/+Inf/-Inf (`'nan'::DOUBLE` spellings), decimal, varchar with
quote/newline/tab, blob with embedded 0x00 and 0x27 (`'\xAA...'::BLOB`),
date, time(ms), timestamp(ms), **timestamptz**, **timetz**, uuid, enum,
list-containing-NULL, struct, map, nested. `missing` serializes as
`NULL` on every path tested.

**timezone policy (a), adopted and verified:** julia `DateTime` ≡ UTC
instant is the generated-code contract. literals carry an explicit
`+00` offset; TIMESTAMPTZ reads arrive UTC-normalized (measured). the
binding paths (appender, register_df) also bind naive DateTime as the
UTC instant — verified with session `TimeZone = Pacific/Auckland`
(+12) actually in effect, so this is not "session happened to be UTC".
TIMETZ follows the same contract (`+00` literals, `Time` on read).

serializer gotcha for phase 5: blob dispatch on `AbstractVector{UInt8}`
would collide with a `UTINYINT[]` column under bare julia dispatch —
the generated serializer must be type-directed by the column's
`DuckType`, not by the value's julia type alone.

## 3. structarrays — feasible, read-side only, better with typed structs

`StructArray(collect(skipmissing(col)))` works on a struct column and behaves
as a DataFrame column (`StructVector`). field arrays come out `Vector{Any}`
because the input NamedTuples are untyped (§1) — generated typed structs
would make them concrete. write side is moot: the writer serializes literals
regardless (§2). nullable struct columns need a policy (skipmissing loses row
alignment — phase 6 design point).

## 4. storage-format compatibility 1.5.2 ↔ 1.5.4 — both directions OK

- julia-written `.duckdb` (jll 1.5.2) opens fine in the bundled rust 1.5.4
  (`dbdict types duckdb`), structs intact
- `dbdict dummy`-written db (1.5.4) opens fine from julia, structs/enums/
  lists read correctly

## 5. fixed-size ARRAY is unusable via DuckDB.jl 1.5.2

any query touching an `INTEGER[3]` column throws
`Unsupported type for duckdb_type_to_julia_type: DUCKDB_TYPE_ARRAY` at
result materialization — reads *and* the read-back half of writes. support
exists on DuckDB.jl main (`convert_vector_array` in result.jl) but is
unreleased. → generator must detect fixed-size array columns and emit a
clear diagnostic (table unreadable from julia until DuckDB.jl ships array
support). phase 5 decision: hard error vs warn-and-skip the table.

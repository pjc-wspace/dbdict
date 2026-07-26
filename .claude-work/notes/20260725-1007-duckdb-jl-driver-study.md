# DuckDB.jl 1.5.2 driver capability study (for dbdict Julia codegen)

> **HISTORICAL RECORD — superseded 2026-07-26.** the current consolidated
> reference is `research/duckdb-driver-jl/reference.md`, which merges this
> study, the capability spike (`20260723-1530`), phase-1 verification, and
> benchmark results. seven claims in this note were corrected by later
> measurement — including three marked *Inferred* here (now measured), the
> §3c bind-time claim (wrong), and implication 4's appender-first tier
> recommendation (contradicted by benchmark). see that document's
> Appendix A. read it, not this, for current behaviour.

Ground truth: installed source at `/home/pjc/.julia/packages/DuckDB/2J7sd/src/` (package
version 1.5.2, `DuckDB_jll` 1.5.2 — Project.toml). All `file:line` citations below refer
to that directory. Docs page consulted: https://duckdb.org/docs/lts/clients/julia.html
(the `/docs/stable/clients/julia` URL currently 404s; it redirects via `/docs/clients/julia`
to the LTS page). Where docs and code disagree, the code wins (discrepancies noted).

## Executive summary

- Reading is complete and rich: every DuckDB type a dbdict schema is likely to use converts
  to a sensible Julia type — except `ARRAY` (fixed-size), which throws at result-construction
  time in 1.5.2. Streaming (chunk-at-a-time, 2048 rows) reads exist via `StreamResult` +
  `Tables.partitions`.
- Writing is the weak side. Three paths: Appender (row-wise C calls, fastest per docs),
  prepared-statement binds (narrower type coverage than the appender; no Int128/UUID/decimal),
  and registered tables/`DuckDB.load!` (flat primitive + decimal columns only).
- Appender covers ints/uints (incl. 128-bit), floats, strings, blobs, Date/Time/DateTime,
  UUID and FixedDecimal (both via string), and 1-level lists of primitives. No interval,
  struct, map, enum-native, or nested-list appends.
- All appender return codes are ignored by the Julia wrapper — append errors are silent.
- Several precision/asymmetry traps: Time ns→µs truncation (appender) vs InexactError (bind),
  TIMESTAMP_NS reads truncated to ms, BLOB reads back as `Base.CodeUnits` not `Vector{UInt8}`,
  empty list appends become NULL, `create_value` string length bug truncates non-ASCII
  strings inside bound lists.

## 1. API surface for reading

### Entry points

| Call | Where | Notes |
|---|---|---|
| `DBInterface.execute(db_or_con, sql)` | result.jl:876-886 | prepares a `Stmt`, executes, returns `QueryResult`; default `MaterializedResult` |
| `DBInterface.execute(db_or_con, sql, result_type)` | result.jl:876-886 | `result_type` is `DuckDB.MaterializedResult` or `DuckDB.StreamResult` (DuckDB.jl:14-16) |
| `DBInterface.execute(stmt, params)` | result.jl:875 | rebinding + execute of a prepared `Stmt` |
| `DBInterface.prepare(con_or_db, sql[, result_type])` | result.jl:856-860 | returns `Stmt` (statement.jl:1-28) |
| `DuckDB.query(con_or_db, sql)` | result.jl:895-906 | direct `duckdb_query`; supports multi-statement SQL; always materialized |
| `DuckDB.toDataFrame` | old_interface.jl:11-12 | deprecated shim; returns `Tables.columntable` (a NamedTuple, not a DataFrame) |

Execution goes through a pending result: `PendingQueryResult` (result.jl:569-580), created
with `duckdb_pending_prepared` (materialized) or `duckdb_pending_prepared_streaming`
(result.jl:582-596). With `Threads.nthreads() == 1` tasks are pumped on the main thread
(result.jl:674-684, 721-726); otherwise one Julia task per thread is `@spawn`ed to execute
DuckDB tasks (result.jl:686-708, 727-729).

### QueryResult and Tables.jl interface

`QueryResult` (result.jl:3-36) captures column names (deduplicating duplicates by appending
`_1`, `_2`, … — result.jl:14-24) and column types, each wrapped as
`Union{Missing, T}` (result.jl:26-30).

- `Tables.istable/isrowtable/columnaccess` are all true (result.jl:759-761);
  `Tables.schema` reports the `Union{Missing,...}` types (result.jl:762).
- `Tables.columns(q)` — full materialization (result.jl:543-567): fetches **all** data chunks
  into a `Vector{DataChunk}` first, then converts **column-at-a-time across all chunks**
  (`convert_columns`, result.jl:534-541). The result is cached on `q.tbl` and wrapped in
  `Tables.CopiedColumns` (result.jl:566).
- Row iteration (`Base.iterate`) simply defers to `Tables.rows(Tables.columns(q))`
  (result.jl:768-769) — i.e. iterating rows materializes everything anyway.

### Materialization mechanics

`convert_column` (result.jl:522-532) picks, per column: an internal (storage) type, a target
Julia type, a per-value conversion function (result.jl:460-500), and a per-vector loop function
(result.jl:502-520). `convert_column_loop` (result.jl:352-404) does two passes:

1. scan all chunks' validity masks to decide if the column has any NULLs
   (result.jl:359-367; `all_valid` data_chunk.jl:52-54, vector.jl:28-34);
2. allocate one full-length output array — `Vector{DST}` if no NULLs, otherwise
   `Vector{Union{Missing,DST}}` prefilled with `missing` (result.jl:368-387) — and fill it
   chunk by chunk via `get_array` / `unsafe_wrap` over the raw vector data (vector.jl:13-17),
   converting value-by-value in a loop (result.jl:111-133).

So: chunk-at-a-time fetch, column-at-a-time conversion, value-at-a-time inner loop. Strings
are decoded from `duckdb_string_t` with the 12-byte inline optimization
(`STRING_INLINE_LENGTH`, ctypes.jl:1; result.jl:68-80). Nested types recurse (list:
result.jl:160-205, struct: 235-263, map: 298-350, union: 265-296).

### Streaming

Yes — prepare/execute with `DuckDB.StreamResult`, then either:

- `Tables.partitions(q)` → `QueryResultChunkIterator` (result.jl:784-822): each partition is
  one data chunk (≤ `VECTOR_SIZE` = 2048 rows) converted to a NamedTuple table
  (`QueryResultChunk`, result.jl:771-796), or
- `DuckDB.nextDataChunk(q)` for raw `DataChunk`s (result.jl:824-843; streaming branch uses
  `duckdb_stream_fetch_chunk`, materialized branch pages through
  `duckdb_result_get_chunk`).

Restrictions: strictly single-pass — iterating partitions twice throws
(result.jl:800-807), and calling `Tables.columns` after `nextDataChunk` throws
(result.jl:545-551). `Tables.partitions` also works on materialized results (it then pages
through the already-computed chunks without building the whole Julia table).

## 2. Read type support (definitive for 1.5.2)

Mapping from `JULIA_TYPE_MAP` (ctypes.jl:382-413), special cases in
`duckdb_type_to_julia_type` (ctypes.jl:423-463), and conversion functions
(result.jl:460-500, ctypes.jl:509-586). Column type is always reported as
`Union{Missing, T}` in the schema (result.jl:29), but the actual column array is
`Vector{T}` when the column contains no NULLs (result.jl:385-402).

| DuckDB type | Julia type | Notes / citation |
|---|---|---|
| BOOLEAN | `Bool` | ctypes.jl:384 |
| TINYINT / SMALLINT / INTEGER / BIGINT | `Int8` / `Int16` / `Int32` / `Int64` | ctypes.jl:385-388 |
| UTINYINT / USMALLINT / UINTEGER / UBIGINT | `UInt8` / `UInt16` / `UInt32` / `UInt64` | ctypes.jl:391-394 |
| HUGEINT | `Int128` | ctypes.jl:389; ctypes.jl:511 |
| UHUGEINT | `UInt128` | ctypes.jl:390; ctypes.jl:512 |
| FLOAT / DOUBLE | `Float32` / `Float64` | ctypes.jl:395-396 |
| DECIMAL(w,s) | `FixedDecimal{Int16\|Int32\|Int64\|Int128, s}` by internal storage | ctypes.jl:425-438; reinterpret, result.jl:103-109 |
| VARCHAR | `String` | ctypes.jl:407; result.jl:68-80 |
| ENUM | `String` (dictionary lookup) | ctypes.jl:408; result.jl:99-101; logical_type.jl:86-96 |
| BLOB | `Base.CodeUnits{UInt8, String}` | ctypes.jl:409; result.jl:82-84 |
| BIT | `Base.CodeUnits{UInt8, String}` (raw internal bytes incl. padding byte) | ctypes.jl:410; result.jl:464 |
| GEOMETRY | `Base.CodeUnits{UInt8, String}` (raw bytes) | ctypes.jl:412; result.jl:464 |
| DATE | `Dates.Date` | ctypes.jl:397; ctypes.jl:533-535 |
| TIME | `Dates.Time` (µs resolution) | ctypes.jl:398; ctypes.jl:540-548 |
| TIME_TZ | `Dates.Time` — **UTC offset discarded** ("TODO: how to preserve the offset?") | ctypes.jl:399; ctypes.jl:550-560 |
| TIMESTAMP | `Dates.DateTime` (µs → **ms truncation**) | ctypes.jl:400; ctypes.jl:566-567 |
| TIMESTAMP_TZ | `Dates.DateTime` — offset/zone info not represented | ctypes.jl:401; result.jl:472-473 |
| TIMESTAMP_S / TIMESTAMP_MS | `Dates.DateTime` | ctypes.jl:402-403; ctypes.jl:562-565 |
| TIMESTAMP_NS | `Dates.DateTime` (ns → **ms truncation**, `÷ 1_000_000`) | ctypes.jl:404; ctypes.jl:568-569 |
| INTERVAL | `Dates.CompoundPeriod` (Month+Day+Microsecond) | ctypes.jl:405; ctypes.jl:571-572 |
| UUID | `UUIDs.UUID` | ctypes.jl:406; ctypes.jl:574-582 |
| LIST(T) | `Vector{Union{Missing, julia(T)}}` | ctypes.jl:439-440; result.jl:160-205 |
| STRUCT(...) | `NamedTuple{(field names...)}` — field types untyped (built as `Vector()` → `Any` values) | ctypes.jl:441-449; result.jl:235-263 |
| MAP(K,V) | `Dict` (untyped `Dict{Any,Any}`) | ctypes.jl:411; result.jl:298-350 |
| UNION(...) | `Union{Missing, member types...}` | ctypes.jl:450-457; result.jl:265-296 |
| INVALID | `Missing` | ctypes.jl:383 |

**Types that throw on read** (`NotImplementedException("Unsupported type for
duckdb_type_to_julia_type: ...")`, ctypes.jl:459-461): **ARRAY** (fixed-size arrays,
type id 33), BIGNUM, SQLNULL, ANY, STRING_LITERAL, INTEGER_LITERAL, TIME_NS (type ids
ctypes.jl:190-197). The throw happens in the `QueryResult` constructor (result.jl:28-29),
i.e. merely executing a query whose result contains such a column throws — you never get a
result handle to work with. (GitHub main has since added ARRAY support; 1.5.2 has not.)

Nullability: schema always advertises `Union{Missing,T}` (result.jl:26-30); actual column
arrays are `Vector{T}` when NULL-free, `Vector{Union{Missing,T}}` otherwise
(result.jl:368-402). List/struct/map children are always allocated as
`Union{Missing,...}` arrays (result.jl:179, 217, 317).

## 3. API surface for writing

### 3a. Appender (appender.jl)

Lifecycle: `Appender(db_or_con, table[, schema])` (appender.jl:40-62, C call
`duckdb_appender_create` api.jl:6687) → per row: one `append(appender, val)` per column,
then `end_row(appender)` (appender.jl:121-124) → `flush(appender)` (appender.jl:126-129)
→ `close(appender)` / `DBInterface.close!` (appender.jl:72-75, 131; destroy at 64-70).

`append` dispatches on the Julia value type:

| Julia type | C call | Citation |
|---|---|---|
| `Bool` | `duckdb_append_bool` | appender.jl:78 |
| `Int8`/`Int16`/`Int32`/`Int64` | `duckdb_append_int8/16/32/64` | appender.jl:79-82 |
| `Int128` | `duckdb_append_hugeint` | appender.jl:83 |
| `UInt8`/`UInt16`/`UInt32`/`UInt64` | `duckdb_append_uint8/16/32/64` | appender.jl:85-88 |
| `UInt128` | `duckdb_append_uhugeint` | appender.jl:84 |
| `Float32` / `Float64` | `duckdb_append_float` / `_double` | appender.jl:89-90 |
| other `AbstractFloat` (e.g. `Float16`) | widened to `Float64`, `duckdb_append_double` | appender.jl:77 |
| `Missing` / `Nothing` | `duckdb_append_null` | appender.jl:91 |
| `AbstractString` | `duckdb_append_varchar` | appender.jl:92 |
| `Base.UUID` | **stringified**, then varchar append | appender.jl:93 |
| `Vector{UInt8}` | `duckdb_append_blob` | appender.jl:94 |
| `FixedDecimal` | **stringified**, then varchar append | appender.jl:95 |
| `Date` | `duckdb_append_date` (epoch-days int) | appender.jl:97-98 |
| `Time` | `duckdb_append_time`, ns `÷ 1000` → µs (**truncates**) | appender.jl:100 |
| `DateTime` | `duckdb_append_timestamp`, ms `* 1000` → µs | appender.jl:103-104 |
| `AbstractVector{T}` | list via `create_value` + `duckdb_append_value`; **empty vector appends NULL** | appender.jl:106-114 |
| anything else | `println(val)` then `NotImplementedException("unsupported type for append")` | appender.jl:116-119 |

Not appendable: `Dates.CompoundPeriod`/intervals (a `duckdb_append_interval` wrapper exists
at api.jl:7197 but is never wired up), structs/NamedTuples, Dicts/maps, nested lists
(`create_value` on `Vector{Vector{T}}` fails — see 3d), enums as a distinct type (strings
are appended as VARCHAR; whether the C appender casts VARCHAR→ENUM for the column is not
visible in this Julia code — Inferred: the UUID path (appender.jl:93) already relies on the
C appender casting VARCHAR to the column's UUID type, so VARCHAR→ENUM casting likely works
the same way; verify empirically).

**All `append`/`end_row`/`flush` return codes (`duckdb_state`) are discarded** — no method
checks for `DuckDBError` or calls `duckdb_appender_error` after creation
(appender.jl:77-129). A cast failure or constraint violation during append/flush is silent
at the Julia level.

### 3b. Prepared statements (statement.jl)

`Stmt` (statement.jl:1-28); binding via `duckdb_bind_internal` dispatch, driven by
`bind_parameters` for positional (statement.jl:79-87) and named parameters
(statement.jl:89-113; named lookup via `duckdb_parameter_name`, with a NamedTuple
positional fallback at statement.jl:101-103). Bind failures throw `QueryException`
(statement.jl:82-84, 109-111).

| Julia type | C call | Citation |
|---|---|---|
| `Bool` | `duckdb_bind_boolean` | statement.jl:47 |
| `Int8`-`Int64`, `UInt8`-`UInt64` | `duckdb_bind_int*/uint*` | statement.jl:48-55 |
| `Float32`/`Float64` | `duckdb_bind_float/_double` | statement.jl:56-57 |
| other `AbstractFloat` | widened to `Float64` | statement.jl:46 |
| `Date` | `duckdb_bind_date` via `value_to_duckdb` | statement.jl:58; table_scan.jl:26 |
| `Time` | `duckdb_bind_time` via `value_to_duckdb` — uses float `/1000` then `convert(Int64, …)`: **throws `InexactError` for sub-µs precision** | statement.jl:59; table_scan.jl:27 |
| `DateTime` | `duckdb_bind_timestamp` | statement.jl:60-61; table_scan.jl:28 |
| `Missing` / `Nothing` | `duckdb_bind_null` | statement.jl:62-63 |
| `AbstractString` | `duckdb_bind_varchar_length` (correct `ncodeunits`) | statement.jl:64-65 |
| `Vector{UInt8}` | `duckdb_bind_blob` | statement.jl:66 |
| `WeakRefString{UInt8}` | `duckdb_bind_varchar_length` | statement.jl:67-68 |
| `AbstractVector{T}` | list `Value` via `create_value` + `duckdb_bind_value` | statement.jl:69-72 |
| anything else | `println(val)` + `NotImplementedException` | statement.jl:74-77 |

**Bind gaps vs the appender**: no `Int128`, `UInt128`, `UUID`, `FixedDecimal`, interval —
all throw. A codegen emitting parameterized INSERTs must stringify these (and rely on
DuckDB's implicit VARCHAR cast) or use the appender.

### 3c. Registered tables / DataFrames (table_scan.jl, replacement_scan.jl)

`register_table(con_or_db, tbl, name)` (table_scan.jl:200-208; aliases
`register_data_frame`, table_scan.jl:218): stores `columntable(tbl)` (Tables.jl
NamedTuple-of-vectors — no element copies for columnar sources) in
`db.registered_objects` and creates a SQL view
`CREATE OR REPLACE VIEW "name" AS SELECT * FROM julia_tbl_scan('name')`
(table_scan.jl:201-205). `unregister_table` drops it (table_scan.jl:210-215). The scan
table function `julia_tbl_scan` is registered at DB construction (`_add_table_scan`,
table_scan.jl:222-236; called from database.jl:87).

Column type support: the bind step strips `Missing` from the eltype
(`table_result_type`, table_scan.jl:19) and calls
`add_result_column(info, name, result_type)` (table_scan.jl:114), which goes through
`create_logical_type` (table_function.jl:38-39). **Therefore a registered table's column
eltypes are limited to `create_logical_type` coverage** (logical_type.jl:28-66):

- supported: `String`/`AbstractString`, `Bool`, `Int8/16/32/64/128`, `UInt8/16/32/64/128`,
  `Float32/64`, `Date`, `Time`, `DateTime`, `FixedDecimal{Int16|32|64|128,s}`
  (logical_type.jl:28-62);
- everything else — `UUID`, `Vector`s (list columns), `NamedTuple`, `Dict`,
  `CompoundPeriod`, `Char`, `Symbol`, `Any`, … — throws
  `NotImplementedException("Unsupported type for create_logical_type")`
  (logical_type.jl:64-66) when the view is first queried (bind time).

Scan mechanics: values are copied element-by-element from the Julia column into DuckDB
vectors, `VECTOR_SIZE` rows per chunk (`tbl_scan_column`, table_scan.jl:36-57; strings via
`assign_string_element`, table_scan.jl:59-79, vector.jl:52-58; NULLs via
`setinvalid`, validity_mask.jl:23-28). Date/Time/DateTime are converted per value with
`value_to_duckdb` (table_scan.jl:26-28) — the same `Time` `InexactError` hazard applies.
Parallel: `max_threads = ceil(rowcount / ROW_GROUP_SIZE)` (table_scan.jl:138-145), work
handed out in `ROW_GROUP_SIZE` blocks under a lock (table_scan.jl:152-176).

`replacement_scan.jl` (add_replacement_scan!, replacement_scan.jl:63-72) is lower-level
machinery for resolving unknown table names to table functions; the package itself does not
use it for DataFrames (registration uses an explicit view instead). Not needed for codegen.

### 3d. Value API (value.jl) — used by list bind/append

`create_value` supports: `Bool`, `Int8..Int128`, `UInt8..UInt128`, `Float32/64`, `Date`,
`Time`, `DateTime`, `AbstractString`, `AbstractVector{T}` (value.jl:33-56); anything else
throws (value.jl:57-59). List values call `create_logical_type(T)` (value.jl:53), so:

- `Vector{Union{Missing,T}}` throws (no `create_logical_type` for a Union; also
  `create_value(missing)` throws) — **lists with NULL elements cannot be written**;
- nested `Vector{Vector{T}}` throws (no `create_logical_type` for `Vector`);
- **bug**: `create_value(::AbstractString)` uses `duckdb_create_varchar_length(val,
  length(val))` (value.jl:51) — `length` counts characters, not bytes, so non-ASCII strings
  inside bound/appended lists are truncated. (Scalar string bind is correct —
  `ncodeunits`, statement.jl:65.)

### 3e. Other write paths

- `DuckDB.load!(con, tbl, table[, schema])` (old_interface.jl:28-33): registers the table
  as `__append_df`, runs `CREATE TABLE ... AS SELECT * FROM __append_df`, unregisters.
- `DuckDB.appendDataFrame(tbl, con, table[, schema])` (old_interface.jl:14-21): same but
  `INSERT INTO`. Both use the **fixed temp name `__append_df`** — not safe for concurrent
  use — and inherit the table-scan type restrictions (3c).
- `DuckDB.drop!(db, table; ifexists)` (ddl.jl:2-5), with `esc_id` identifier quoting
  (helper.jl:4-5).

## 4. Performance characteristics

### Docs claims (exact quotes, https://duckdb.org/docs/lts/clients/julia.html)

- "The DuckDB Julia package also supports the Appender API, which is much faster than using
  prepared statements or individual INSERT INTO statements."
- "Appends are made in row-wise format. For every column, an append() call should be made,
  after which the row should be finished by calling flush()." — **docs error**: the code
  (and the docs' own example) finish rows with `end_row()` (appender.jl:121-124); `flush()`
  flushes buffered rows to the table (appender.jl:126-129).
- "Note that the DataFrames are directly read by DuckDB – they are not inserted or copied
  into the database itself." — true for storage (registration stores only a `columntable`
  reference, table_scan.jl:201), but each query over the view copies scanned values
  element-wise into DuckDB vectors (table_scan.jl:49-56, 71-78). Not zero-copy per query.
- "The package also supports multi-threaded execution. It uses Julia threads/tasks for this
  purpose. If you wish to run queries in parallel, you must launch Julia with
  multi-threading support (by e.g., setting the JULIA_NUM_THREADS environment variable)."
- "Within a Julia process, tasks are able to concurrently read and write to the database,
  as long as each task maintains its own connection to the database."

### What the code implies

- **Appender is row-wise, value-at-a-time**: one `ccall` per cell + one per `end_row`
  (appender.jl:77-124). It is *not* vectorized on the Julia side; batching happens inside
  DuckDB's C appender. `duckdb_append_data_chunk` exists (api.jl:7309, header doc:
  "Appends a pre-filled data chunk … Attempts casting, if the data chunk types do not match
  the active appender types") but is **not** used by any high-level Julia API.
- **Registered-table scan is the vectorized bulk path**: 2048-row chunks
  (`VECTOR_SIZE = duckdb_vector_size()`, database.jl:106), parallelizable in
  `ROW_GROUP_SIZE = VECTOR_SIZE * 100` = 204,800-row units (database.jl:107,
  table_scan.jl:140-145). So `DuckDB.load!`/`INSERT INTO ... SELECT FROM registered_view`
  is multi-threaded and chunk-based, while the appender is a single-threaded scalar loop
  per connection.
- **Prepared statement per-execute overhead**: each `execute` re-binds all params, creates a
  `PendingQueryResult`, pumps tasks (spawning `nthreads` Julia tasks per query when
  multi-threaded), then builds a `QueryResult` with per-column `LogicalType` allocation
  (result.jl:711-740, 686-708, 26-30). Heavy for per-row INSERT loops — consistent with the
  docs' appender claim.
- **Read materialization** allocates exactly one output array per column (result.jl:368-387)
  but converts value-at-a-time through function-barrier loops; strings allocate per value
  (result.jl:68-80). NULL-free columns skip validity checks entirely (`all_valid` fast path,
  result.jl:385-402).
- DB construction sets `threads` and `external_threads` to `Threads.nthreads()`
  (database.jl:81-82), i.e. DuckDB spawns no internal worker threads; parallelism comes from
  the Julia task pump. Inferred: `DuckDB.query()` (result.jl:895-906) calls blocking
  `duckdb_query` with no Julia task pump, so it executes without that parallelism.
- Worth benchmarking later: appender vs `load!`(registered scan) vs parameterized INSERT for
  bulk loads; streaming `Tables.partitions` vs full materialization for large reads.

## 5. Transactions (transaction.jl)

All SQL-based, no C transaction API:

- `begin_transaction(con|db)` → `execute("BEGIN TRANSACTION;")` (transaction.jl:25-28)
- `commit(con|db)` → `execute("COMMIT TRANSACTION;")` (transaction.jl:37-38)
- `rollback(con|db)` → `execute("ROLLBACK TRANSACTION;")` (transaction.jl:47-48)
- `DBInterface.transaction(f, con|db)` (transaction.jl:2-16): runs `f()`, rolls back and
  rethrows on exception, commits on success. Note the commit call is *outside* the
  `try` (transaction.jl:4-11): if `COMMIT` itself fails, no rollback is attempted.

Transactions are per-connection (database.jl docstring, database.jl:36-42). This is
sufficient for bulk-replace semantics: `BEGIN; DELETE FROM t; <append/insert>; COMMIT` —
but note the appender buffers rows until `flush`/`close`; flush inside the transaction
before `COMMIT`. (Appender flush participating in the connection's active transaction is
standard DuckDB appender behavior — Inferred; verify empirically.)

## 6. Gotchas for codegen

1. **ARRAY columns are unreadable** in 1.5.2 — executing any query returning `ARRAY` throws
   `NotImplementedException` in the `QueryResult` constructor (ctypes.jl:459-461,
   result.jl:28-29). Generated readers must cast: `SELECT col::T[] ...` (LIST reads fine).
2. **Appender errors are silent**: every `duckdb_state` return from
   `append`/`end_row`/`flush`/destroy is discarded (appender.jl:77-129, 64-70). Generated
   writers should verify with a follow-up `COUNT(*)` or checksum, or use paths that throw.
3. **Bind coverage ⊂ appender coverage**: prepared statements cannot bind `Int128`,
   `UInt128`, `UUID`, `FixedDecimal`, intervals (statement.jl:74-77); the appender handles
   the first four (appender.jl:83-84, 93, 95). Intervals are read-only everywhere.
4. **BLOB asymmetry**: write `Vector{UInt8}` (appender.jl:94, statement.jl:66), read back
   `Base.CodeUnits{UInt8, String}` (ctypes.jl:409). Round-trip comparisons need
   `collect`/`==` on bytes.
5. **UUID / DECIMAL write as strings**: appender stringifies both (appender.jl:93, 95),
   relying on C-appender VARCHAR casts; read back as `UUID` / `FixedDecimal`. Bind: neither.
6. **Time precision**: appender truncates ns→µs (`÷1000`, appender.jl:100); bind and
   table-scan throw `InexactError` on sub-µs `Time` values (float `/1000` +
   `convert(Int64, …)`, table_scan.jl:27). `TIMESTAMP_NS` reads truncate to ms
   (ctypes.jl:568-569). Julia `DateTime` is ms-resolution, so µs stored via SQL are lost on
   read (ctypes.jl:566-567) — full round-trip fidelity only down to ms.
7. **TIME_TZ / TIMESTAMP_TZ lose zone info on read** (ctypes.jl:550-560 with in-code TODO;
   TIMESTAMP_TZ read as plain UTC-ish `DateTime`, result.jl:472-473, ctypes.jl:363).
8. **Empty Julia vector appends/binds as NULL, not `[]`** (appender.jl:108-111). Lists with
   `missing` elements and nested lists cannot be written at all (value.jl:52-56 +
   logical_type.jl:64-66).
9. **Non-ASCII strings inside written lists are truncated** — `create_value` uses
   `length(val)` instead of `ncodeunits` (value.jl:51). Scalar string bind/append is fine.
10. **Registered tables (and thus `load!`/`appendDataFrame`) support only flat
    primitive/decimal columns** (logical_type.jl:28-66 via table_function.jl:38-39); no
    UUID, list, struct, map, interval columns. Failure occurs at query bind time, not at
    registration.
11. **`__append_df` fixed temp name** makes `load!`/`appendDataFrame` non-reentrant across
    concurrent tasks (old_interface.jl:14-33).
12. **Enum write** has no native path — write string values and rely on VARCHAR→ENUM cast
    (appender: Inferred, see 3a; plain SQL INSERT casts fine). Enum reads come back as
    `String` (ctypes.jl:408).
13. **Struct/map/union are read-only**: no write path in appender, bind, value, or scan.
14. **`Union{Missing,T}` schema vs concrete column arrays**: `Tables.schema` always says
    `Union{Missing,T}` (result.jl:29) but materialized columns are `Vector{T}` when
    NULL-free (result.jl:385-402). Generated code must not assume element type
    `Union{Missing,T}` when consuming `Tables.columns` output directly.
15. **Single-pass results**: `QueryResult` chunks can be consumed once; mixing
    `Tables.partitions`/`nextDataChunk` with `Tables.columns` throws (result.jl:545-551,
    800-807).
16. **DB vs Connection**: `DB` wraps a database handle plus a `main_connection`
    (database.jl:76-98); passing a `DB` to any API uses `main_connection`
    (e.g. result.jl:755-756). One connection = one query at a time; concurrent tasks need
    `DBInterface.connect(db)` for their own `Connection` (database.jl:113, docstring
    database.jl:36-42, and the docs concurrency quote in §4). Transactions are
    per-connection.
17. **Multi-statement SQL** (also `PIVOT`, `IMPORT DATABASE`) fails under
    `DBInterface.execute` (single prepared statement); use `DuckDB.query`
    (result.jl:891-906; docs: "they can be run with DuckDB.query() instead of
    DuckDB.execute() and will always return a materialized result").
18. **Duplicate result column names are renamed** `name`, `name_1`, `name_2`, …
    (result.jl:14-24).
19. `DBInterface.lastrowid` always throws (result.jl:845-847) — don't emit it.
20. Failure-mode noise: unsupported append/bind values are `println`ed to stdout before the
    throw (appender.jl:117, statement.jl:75).

## Implications for dbdict-julia codegen

1. **Readers**: emit `DBInterface.execute(con, sql)` + `Tables.columns`/`DataFrame` for the
   default path, and offer `DuckDB.StreamResult` + `Tables.partitions` for large tables.
   Declare column types as `Union{Missing,T}` only for nullable columns in *dbdict's* model,
   but accept both `Vector{T}` and `Vector{Union{Missing,T}}` at runtime (gotcha 14).
2. **Supported-type split (read)**: everything in the §2 table is green except ARRAY (red —
   or auto-cast to LIST in generated SQL), BIGNUM/TIME_NS (red), TIME_TZ/TIMESTAMP_TZ
   (yellow: zone dropped), TIMESTAMP_NS (yellow: ms truncation), BIT/GEOMETRY (yellow: raw
   bytes).
3. **Supported-type split (write)**: green for appender = bool, all int/uint widths, floats,
   varchar, blob, Date, Time (µs), DateTime (ms), UUID, DECIMAL (≤38 digits), LIST of
   non-missing primitives (non-ASCII string lists broken, gotcha 9). Red: interval, struct,
   map, union, nested list, list-with-NULLs, ARRAY. Enum: yellow (string + cast, verify).
4. **Bulk write strategy**: prefer the **Appender** per table (docs-verified fastest), one
   append per cell + `end_row`, `flush` before `COMMIT`, then `close`. For very wide/large
   loads of flat primitive tables, `register_table` + `INSERT INTO real_table SELECT * FROM
   view` is the vectorized, multi-threaded alternative — but only for the narrower type set
   in 3c (no UUID/list columns), so the appender is the safer default for dbdict's rich
   types.
5. **Bulk-replace**: emit `DBInterface.transaction(con) do ... end` (or explicit
   BEGIN/COMMIT) around `DELETE FROM t` + appender writes; flush the appender inside the
   transaction. Use a dedicated `Connection` per writer task.
6. **Avoid parameterized per-row INSERTs** entirely: slower (docs quote) and narrower type
   support than the appender (gotcha 3).
7. **Verification step**: because appender errors are silent (gotcha 2), generated loaders
   should end with a row-count check (and optionally a checksum query) and raise on
   mismatch.
8. **Do not emit** `DuckDB.load!`/`appendDataFrame` (fixed temp-name collision, type
   limits), `lastrowid`, intervals in writable schemas, or reliance on `ARRAY` columns.
9. For enum columns, generate `INSERT ... SELECT CAST(? AS enum_type)`-style SQL or appender
   string writes guarded by a round-trip test in dbdict's validation suite; treat appender
   enum-cast behavior as unverified until tested.

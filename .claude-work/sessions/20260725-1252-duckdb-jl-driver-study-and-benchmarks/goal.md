# duckdb.jl: document and benchmark the julia duckdb driver

## problem

The julia codegen session (`20260723-1109`, on hold) rests on knowledge of
DuckDB.jl that is code-read and partially spiked but not measured: writer
tier selection (appender vs registered-scan vs literal SQL) has no
performance numbers behind it, several driver behaviors are inferred
rather than verified, one spike/study discrepancy is unresolved, and the
knowledge is scattered across two notes files. Before codegen resumes,
the driver must be fully understood, benchmarked, and documented — this
session is that resumption gate.

## success criteria

- **benchmarks** of the driver's bulk-write paths — appender,
  register + `INSERT INTO ... SELECT`, generated literal SQL — and of
  materialized vs streaming reads, across representative type profiles
  (flat primitives; flat + uuid/decimal; struct column; list column)

> defaults pending review: BenchmarkTools.jl for rigor (warmup, samples,
> medians — defensible and comparable across driver upgrades); scales
> 10k / 100k / 1M rows (100k is the realistic working size; 1M surfaces
> chunking/parallelism/string-building scaling; 10M omitted)

- **discrepancies and inferred behaviors settled empirically**:
  - appender blob: spike measured ERR, driver code has `duckdb_append_blob`
    wired — one measurement is confounded
  - appender VARCHAR→ENUM cast (inferred from the UUID stringify path)
  - appender flush participating in the connection's open transaction
  - StructArray accepted by `register_table` (Tables.jl route)
- **consolidated driver reference** in `research/duckdb-driver-jl/`:
  one document merging the capability spike, the driver study, and the
  benchmark results — read/write type-support tables per path, precision
  and UTC contracts, the gotcha list, benchmark methodology + numbers —
  explicitly versioned against DuckDB.jl 1.5.2 (latest registered)
- **runnable test examples alongside it**: the benchmark and verification
  scripts live in `research/duckdb-driver-jl/` with their own
  Project.toml/Manifest.toml, re-runnable when a new DuckDB.jl releases
  (that's the trigger to refresh numbers and re-check gotchas)
- everything committed; the held codegen session's `review-decisions.md`
  gains a pointer to the reference doc as the driver ground truth

## scope

- in: benchmark harness + runs, verification scripts for the four open
  behaviors, the consolidated reference doc, migration of durable content
  from the two existing notes into it (notes stay as historical record)
- out: any dbdict codegen work (stays in the held session); site/ rebuild
  (parked in todos/legacy-site); patching DuckDB.jl itself. Filing
  upstream issues for the confirmed driver bugs (silent appender errors,
  empty-vector→NULL, list non-ASCII truncation) is optional stretch — a
  decision at close, not a commitment

## constraints

- environment pinned: julia 1.12.6 (juliaup), DuckDB.jl 1.5.2 /
  DuckDB_jll 1.5.2 — the latest registered release (verified); numbers
  and behaviors are claims about this version only
- benchmarks are single-machine, indicative — for *tier ordering*
  decisions, not absolute throughput claims
- measure, don't assume: every behavior claim in the reference doc traces
  to a script in the directory or a file:line in the driver source
- findings feed the held session's writer-tier and supported-list
  decisions; if numbers contradict a recorded decision (e.g. appender vs
  registered-scan ordering), the reference doc flags it for the codegen
  session to reconcile on resume

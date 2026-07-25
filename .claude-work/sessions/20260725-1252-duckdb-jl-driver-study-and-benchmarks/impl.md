# implementation: duckdb.jl document and benchmark the julia duckdb driver

> workflow notes:
> - context budget rule: don't start a phase at ≥25% context — /ws pause,
>   fresh session, /state load
> - /code-review mandate: no rust/production code changes planned this
>   session (julia scripts + markdown); mandate applies only if that
>   changes
> - driver ground truth: installed source ~/.julia/packages/DuckDB/2J7sd/
>   (1.5.2); existing findings: notes/20260723-1530 (spike),
>   notes/20260725-1007 (study), spike scripts in session
>   20260723-1109's spike/ dir

## phases

### phase 1: environment + verification scripts (the four open behaviors) — DONE 2026-07-26T11:28:27+12:00

- [x] create `research/duckdb-driver-jl/` with `Project.toml` +
      `Manifest.toml`: DuckDB (=1.5.2), DataFrames, StructArrays,
      FixedPointDecimals, BenchmarkTools
  - also: Manifest seeded from session `20260723-1109`'s `spike/` so the
    resolution is identical; `[compat] DuckDB = "=1.5.2"` makes the pin
    explicit; added stdlibs Dates, UUIDs, Random, Tables, Printf
  - verified: DuckDB.jl 1.5.2, DuckDB_jll 1.5.4, engine `version()` =
    v1.5.4, driver source resolves to the `2J7sd` tree the study cites,
    `Threads.nthreads()` = 1
- [x] `verify_blob_appender.jl` — settle the spike/study discrepancy:
      append `Vector{UInt8}` into a BLOB column in isolation, no
      confounds; if it errors, isolate why the code path (`appender.jl:94`)
      and the spike measurement disagree
  - also: added a raw-`ccall` control re-declaring the same C entry point
    with `Ptr{Cvoid}`, which localised the defect to `api.jl:7261`
  - also: needed THREE payload classes (ASCII / non-UTF-8 / with-NUL) —
    the first two probes were confounded by Julia's `Cstring` conversion
    and by DuckDB's UTF-8 validation, neither of which is the cast
  - result: **both notes were right** — path wired but unusable
- [x] `verify_enum_appender.jl` — appender string → ENUM column cast
      (inferred from the UUID stringify path; measure it)
  - also: UUID + FixedDecimal controls (the sibling stringify paths),
    over-precision decimal (silently rounds), multi-row batch
  - also: added a multi-column probe that found the phase's most serious
    result — a failed cell does not advance the appender's column cursor,
    so subsequent values MISALIGN across columns rather than just dropping
- [x] `verify_appender_transaction.jl` — appender rows written inside
      `DBInterface.transaction`: visible after commit, gone after
      rollback (flush-before-commit semantics)
  - also: buffered (unflushed) rows escape the transaction; measured 5
    rows appearing after a forced `GC.gc()` post-rollback via the
    `appender.jl:59` finalizer. mitigation (appender lifetime inside the
    txn body, `try`/`finally`) measured to hold
  - also: bulk-replace atomicity and cross-connection isolation confirmed
- [x] `verify_structarray_register.jl` — StructArray through
      `register_table` (Tables.jl route): flat StructArray of primitives,
      and one with a nested field (expected to fail at bind — record it)
  - also: measured that `columntable` aliases (`===`) the StructArray's
    component arrays — registration is zero-copy, the per-query scan is not
  - also: nullable / UUID / list field boundary cases, and the spike's
    path-E leaf-flatten + SQL reassembly workaround end to end
  - **corrects the study**: §3c says failure happens at query bind time,
    not registration — measured, the throw comes out of `register_table`
    itself (it creates a view, and DuckDB binds at view creation)
- [x] each script prints MEASURED verdicts; record results in a running
      `findings.md` in the same dir (becomes raw material for phase 3)
- **verify:** all four scripts run to completion with unambiguous
  verdicts; findings.md records each with the script name and driver
  file:line it confirms or refutes
  - PASSED: 4/4 scripts exit 0; findings.md has 4 script attributions,
    4 VERDICT lines, 19 distinct driver `file:line` citations

> carried into phase 2: add a JSON dependency for `results.json`.
> `Threads.nthreads()` = 1 in this environment — the study (§4) notes DB
> construction sets DuckDB's thread count from Julia's, so the registered-scan
> path will be measured single-threaded unless the suite is launched with
> `JULIA_NUM_THREADS` set. decide and record that in the benchmark header.

### phase 2: benchmark harness + runs

- [ ] `bench_common.jl` — data generation for the four type profiles
      (flat primitives; flat + uuid + decimal; struct column; list
      column) at 10k / 100k / 1M rows; deterministic seeds; literal-SQL
      serializer lifted from the spike's `literal_matrix.jl`
- [ ] `bench_write.jl` — BenchmarkTools benchmarks, per profile × scale ×
      applicable path: appender (per-cell append loop), register +
      `INSERT INTO ... SELECT`, batched literal `INSERT ... VALUES`;
      skip inapplicable cells (e.g. struct via appender) explicitly, not
      silently
- [ ] `bench_read.jl` — materialized (`Tables.columns` → DataFrame) vs
      streaming (`StreamResult` + `Tables.partitions`) reads of the same
      tables, per profile × scale; include time-to-first-chunk for
      streaming
- [ ] `run_all.jl` — one entry point: runs verifications + benchmarks,
      writes `results.md` (tables: median times, allocation counts,
      rows/sec) + raw `results.json`; julia version, package versions,
      thread count, and machine line recorded in the output header
- [ ] run the suite twice; confirm path *orderings* are stable between
      runs (absolute numbers may wobble; ordering is the deliverable)
- **verify:** results.md exists with all profile × scale × path cells
  filled or explicitly marked skipped; second run reproduces the same
  per-cell path ordering; everything committed

### phase 3: consolidated driver reference

- [ ] `research/duckdb-driver-jl/reference.md` — the single document,
      merging: the capability spike (+§2b addendum), the driver study,
      phase 1 verdicts, phase 2 numbers. structure: executive summary;
      read path (API, type table, precision contracts); write paths (API,
      per-path type tables, the gotcha list with all confirmed bugs);
      transactions/connections; benchmark methodology + results +
      tier-ordering conclusions; versioning statement (DuckDB.jl 1.5.2,
      refresh triggers)
- [ ] every behavior claim traces to a script in the dir or a driver
      file:line — no unsourced claims survive the merge
- [ ] the two notes files gain a one-line header pointing to reference.md
      as the current consolidated version (notes stay as history)
- [ ] held session's `review-decisions.md` gains the pointer to
      reference.md as driver ground truth; if benchmark orderings
      contradict any recorded tier decision, add a flagged
      reconciliation note there (decide on codegen resume, not here)
- [ ] close-time decision (recorded, not implemented): file upstream
      DuckDB.jl issues for silent appender errors, empty-vector→NULL,
      list non-ASCII truncation — yes/no per bug
- **verify:** reference.md complete per goal success criteria; spot-check
  three claims back to their script/source; commits clean

> stretch (not a phase): upstream issue filing if the close-time
> decision says yes — would be its own small follow-up

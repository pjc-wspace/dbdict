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
    `appender.jl:56` finalizer. mitigation (appender lifetime inside the
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

### phase 2: benchmark harness + runs — DONE 2026-07-26T13:22:37+12:00

> decisions taken at phase start (user): measure BOTH thread configs
> (`-t 1` and `-t auto`), because DuckDB inherits Julia's thread count
> (database.jl:81-82) and a 1-thread run would measure the registered-scan
> tier with its parallelism off; and full default BenchmarkTools sampling
> everywhere (self-limiting — the 5s budget caps sample count per cell)

- [x] `bench_common.jl` — data generation for the four type profiles
      (flat primitives; flat + uuid + decimal; struct column; list
      column) at 10k / 100k / 1M rows; deterministic seeds; literal-SQL
      serializer lifted from the spike's `literal_matrix.jl`
  - also: a **content gate** (`check_written`) — row counts alone are the
    check phase 1 §2b proved insufficient, so every cell is value-verified
    before being timed. it earned its keep immediately (see §6 below)
  - also: an applicability matrix where every skip carries the driver
    `file:line` or measured reason that justifies it
- [x] `bench_write.jl` — BenchmarkTools benchmarks, per profile × scale ×
      applicable path: appender (per-cell append loop), register +
      `INSERT INTO ... SELECT`, batched literal `INSERT ... VALUES`;
      skip inapplicable cells (e.g. struct via appender) explicitly, not
      silently
  - also: added a 4th path `register_flat` (struct leaves registered flat,
    struct rebuilt in SQL — the spike's path E), since plain `register`
    cannot carry a struct column and the cell would otherwise be blank
- [x] `bench_read.jl` — materialized (`Tables.columns` → DataFrame) vs
      streaming (`StreamResult` + `Tables.partitions`) reads of the same
      tables, per profile × scale; include time-to-first-chunk for
      streaming
- [x] `run_all.jl` — one entry point: runs verifications + benchmarks,
      writes `results.md` (tables: median times, allocation counts,
      rows/sec) + raw `results.json`; julia version, package versions,
      thread count, and machine line recorded in the output header
  - also: split into `run <tag>` / `merge` modes, because thread count is
    fixed at process start — comparing configs means separate processes
- [x] run the suite twice; confirm path *orderings* are stable between
      runs (absolute numbers may wobble; ordering is the deliverable)
  - also: `run_sweep.sh` drives 2 configs × 2 repeats. the `-t 1` repeats
    run CONCURRENTLY (1 thread each, 64 cores); the `-t auto` repeats stay
    serial because each claims every core and contention could flip the
    very orderings the sweep exists to check
- **verify:** results.md exists with all profile × scale × path cells
  filled or explicitly marked skipped; second run reproduces the same
  per-cell path ordering; everything committed
  - PASSED: 84 cells per run × 4 runs — 60 measured, 24 skipped, **0
    failed**; **all 24 write orderings reproduced**; 2 of 36 read
    orderings did not (materialized-vs-streaming near-ties, flagged in
    results.md as too close to call)

#### two unplanned findings (recorded in findings.md §5, §6)

- **§5 — appender + LIST SEGFAULTS the process** at ~1.0–1.2M appends;
  prepared bind over the same `create_value` survives 4M. Found when the
  harness died mid-benchmark. Two hypotheses tested and NOT confirmed
  (both recorded so they are not re-run). Cell excluded from the suite
  with the crash as its stated reason. Codegen must never emit it.
- **§6 — literal SQL silently loses 1 ULP on DOUBLE**: DuckDB parses a
  bare decimal literal as DECIMAL, and `::DOUBLE` does not help because
  the DECIMAL parse happens first. Caught by the content gate. Fixed with
  `@sprintf("%.17e", v)`; verified exact over 2005 values. Affects
  dbdict's universal-fallback writer tier.

#### headline results (feed phase 3)

- **contradicts study §4**: `register` + `INSERT…SELECT` beats the
  appender by 3.4× at 1M flat rows (58.1 ms vs 196.0 ms) and allocates
  538× less (14.8k vs 8.0M) — the appender costs one Julia allocation per
  cell.
  > corrected during phase 3: this line originally read "crossover
  > between 10k and 100k; below that the appender wins", which holds
  > **only at 64 threads**. at 1 thread `register` wins at *every* scale
  > measured, including 10k (1.015 ms vs 2.051 ms). write/flat/10k is the
  > single ordering that differs between thread configs — stable within
  > each, so a real effect, not noise. reference.md §7.5 states it
  > per-config.
- **threads are counterproductive**: `-t auto` (64) is *slower* at every
  scale measured, and no cell improved.
  > refined during phase 3: "~2×" is right for the paths that matter
  > (register flat 1M 58.1 → 111.2 ms) but not uniform — the appender is
  > essentially indifferent to thread count (flat 1M 196.0 → 203.5 ms;
  > rich 1M actually 7% faster), while register/register_flat degrade
  > worst, up to 7.8× at small scales. reference.md §7.4 has the table.
- per-profile winners at 1M: flat → `register`; rich → `appender`
  (register cannot carry UUID); struct → `register_flat`; list →
  `literal` only.

### phase 3: consolidated driver reference — DONE 2026-07-26T13:59:39+12:00

- [x] `research/duckdb-driver-jl/reference.md` — the single document,
      merging: the capability spike (+§2b addendum), the driver study,
      phase 1 verdicts, phase 2 numbers. structure: executive summary;
      read path (API, type table, precision contracts); write paths (API,
      per-path type tables, the gotcha list with all confirmed bugs);
      transactions/connections; benchmark methodology + results +
      tier-ordering conclusions; versioning statement (DuckDB.jl 1.5.2,
      refresh triggers)
  - delivered: 1106 lines, 9 sections + appendix A (corrections to the
    source notes), structured exactly as planned
- [x] every behavior claim traces to a script in the dir or a driver
      file:line — no unsourced claims survive the merge
  - also: adopted an explicit **evidence marker** per claim — M measured
    (script named) / C code (file:line) / D docs (verbatim + URL) / I
    inferred-and-flagged. the merge sources disagree in several places
    *because* they are different evidence classes; flattening them into
    one voice would have destroyed that distinction
  - also: re-fetched all six docs quotes live rather than trusting the
    study's transcription (CLAUDE.md sourcing rule — documentation
    amplifies errors). all six matched
  - **also: audited 27 load-bearing citations against the driver source
    and found one wrong** — the appender finalizer is `appender.jl:56`,
    not `:59` (line 59 is a `DB` constructor overload). the error
    originated in phase 1's findings.md §3b and had already propagated to
    impl.md, a saved insight file, and the new reference doc. corrected
    in all four live docs; left in the phase-2 state dump, which is a
    point-in-time snapshot. the other 26 were exact
- [x] the two notes files gain a one-line header pointing to reference.md
      as the current consolidated version (notes stay as history)
  - also: each header states the *count* of claims that later measurement
    corrected (6 spike, 7 study) and points at appendix A, so a reader
    landing on a note knows how much of it to distrust
- [x] held session's `review-decisions.md` gains the pointer to
      reference.md as driver ground truth; if benchmark orderings
      contradict any recorded tier decision, add a flagged
      reconciliation note there (decide on codegen resume, not here)
  - also: **finding 14 RESOLVED there** (it was PENDING) — the recorded
    `DuckDB_jll 1.5.2` came from reading DuckDB.jl's `[compat]` *bound*
    as a pin. resolved artifact is **1.5.4+0**, engine `version()` =
    v1.5.4. consequence: the spike's "1.5.2 ↔ 1.5.4 storage compat" check
    actually ran the same engine on both sides
  - also: the flagged block retires a queued phase-5 harness task — the
    appender-blob discrepancy is settled (wired at `appender.jl:94`, but
    throws before reaching C via `Ref{Cvoid}` at `api.jl:7261`), so
    phase 5 needs no harness work for it, just a never-emit rule
- [x] close-time decision (recorded, not implemented): file upstream
      DuckDB.jl issues for silent appender errors, empty-vector→NULL,
      list non-ASCII truncation — yes/no per bug
  - **decision (user, 2026-07-26): YES to all four** — the list-append
    segfault and the blob `Ref{Cvoid}` bug joined the original three
    candidates. recorded in reference.md §5.4 with the reproducer script
    named per bug and a note to cite DuckDB_jll 1.5.4+0 when filing.
    filing itself remains a separate follow-up, not this session
- **verify:** reference.md complete per goal success criteria; spot-check
  three claims back to their script/source; commits clean
  - PASSED: all goal criteria present (read + per-path write type tables,
    precision/UTC contracts, gotcha list, benchmark methodology + numbers,
    explicit versioning). three spot-checks, two of them by **executing**
    rather than re-reading: `verify_structarray_register.jl` re-run
    (registration-time throw + path-E reassembly reproduced exactly),
    `verify_blob_appender.jl` re-run (raw `Ptr{Cvoid}` ccall succeeds,
    String workaround silently loses the non-UTF-8 row, NUL throws), and
    the headline numbers traced to `raw/results-t1-a.json`
    (appender 195.964 ms / 7,996,936 allocs vs register 58.115 ms /
    14,853 allocs → 3.372× and 538.4×, at `threads: 1`,
    `duckdb_jll: 1.5.4+0`)

> **all phases complete.** next: `/ws close`.

> stretch (not a phase): upstream issue filing if the close-time
> decision says yes — would be its own small follow-up

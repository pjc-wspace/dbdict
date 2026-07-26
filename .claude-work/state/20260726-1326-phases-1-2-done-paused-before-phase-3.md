---
created: 2026-07-26T13:26:17+12:00
title: phases 1-2 done, paused before phase 3
tags: [duckdb, julia, benchmarking, ws-mid-session]
summary: Driver study session phases 1 (verification) and 2 (benchmarks) complete and committed (6b4ff19, d11ff24). Paused before phase 3 (reference.md) per the >=25% context rule. All raw material is on disk — findings.md §1-§6 and results.md.
---

## Goal

Session `20260725-1252-duckdb-jl-driver-study-and-benchmarks` (ACTIVE,
paused): fully understand, benchmark, and document DuckDB.jl 1.5.2 in
`research/duckdb-driver-jl/`. This is the resumption gate for the held
julia codegen session `20260723-1109-julia-read-write-codegen`.

## Current State

**Phase 1 DONE** (`6b4ff19`) — four verification scripts + `findings.md`
§1-§4. All four open behaviors settled; three `Inferred` claims promoted
to measured, one study claim refuted.

**Phase 2 DONE** (`d11ff24`) — benchmark harness + full sweep. 84 cells
per run × 4 runs (2 thread configs × 2 repeats), 60 measured, 24 skipped,
**0 failed**. All 24 write orderings reproduced; 2 of 36 read orderings
did not (materialized-vs-streaming near-ties, flagged in results.md).

**Phase 3 NOT STARTED** — `reference.md`, the consolidated document.

Environment is committed and reproducible: DuckDB.jl 1.5.2 / DuckDB_jll
1.5.4, julia 1.12.6, `Project.toml` pins `DuckDB = "=1.5.2"`.

### the six findings (all in research/duckdb-driver-jl/findings.md)

1. **appender BLOB** — spike/study discrepancy settled: both right. Path
   is wired (`appender.jl:94`) but broken by `Ref{Cvoid}` at
   `api.jl:7261` (`Cvoid === Nothing`). Same call with `Ptr{Cvoid}`
   round-trips exactly. Use prepared bind for BLOB.
2. **appender VARCHAR→ENUM** — confirmed (was Inferred). Invalid and
   wrong-case labels silently lost. **A failed cell misaligns later
   columns** — `[(1,"sad"),(2,"banana"),(3,"ok"),(4,"happy")]` landed as
   `[(1,"sad"),(2,"ok"),(4,"happy")]`. `COUNT(*)` is necessary but not
   sufficient.
3. **appender flush in transaction** — confirmed for flushed rows.
   Buffered rows escape the txn and leak at GC time (5 rows appeared
   after a forced `GC.gc()` post-rollback, via the `appender.jl:59`
   finalizer). No discard path (`api.jl:6820`). Mitigation measured:
   appender lifetime inside the txn body with `try`/`finally`.
4. **StructArray via register_table** — works flat/nullable; rejects
   nested/UUID/list. Registration is alias-based (`===` measured), the
   per-query scan is not. **Corrects study §3c**: the throw surfaces from
   `register_table`, not at a later query's bind.
5. **appender + LIST SEGFAULTS** (unplanned, phase 2) at ~1.0-1.2M
   appends; prepared bind over the same `create_value` survives 4M. Two
   hypotheses tested and NOT confirmed — both recorded in §5b so they are
   not re-run. Root-causing is out of scope (goal.md).
6. **literal SQL loses 1 ULP on DOUBLE** (unplanned, phase 2). DuckDB
   parses a bare decimal literal as DECIMAL; `::DOUBLE` does not help
   because the DECIMAL parse happens first. Fixed with `%.17e`; verified
   exact over 2005 values.

### headline benchmark results (research/duckdb-driver-jl/results.md)

- **contradicts study §4**: at 1M flat rows single-threaded, `register` +
  `INSERT…SELECT` = 58.1 ms / 17.2M rows/s / 14.8k allocations vs
  `appender` = 196.0 ms / 5.1M rows/s / **8.0M allocations**. 3.4× faster,
  538× fewer allocations. Crossover between 10k and 100k — below that the
  appender wins.
- **threads are counterproductive**: `-t auto` (64) is ~2× slower than 1
  thread at every scale (flat/register 1M: 58.1 → 111.2 ms).
- per-profile winners at 1M: flat → `register`; rich (uuid+decimal) →
  `appender` (register cannot carry UUID); struct → `register_flat`;
  list → `literal` only.
- `literal` is 2-3 orders of magnitude behind everywhere (17.7 s at flat
  1M) and allocates up to 1.7 GiB.

## Key Decisions

- benchmark thread policy: measure BOTH `-t 1` and `-t auto` (user
  decision) — the answer inverted the expectation
- BenchmarkTools full default sampling everywhere (user decision);
  self-limiting because the 5 s budget caps sample count
- harness **content-verifies** every write before timing it, not just row
  counts — a direct consequence of finding 2; it caught finding 6
- added a 4th write path `register_flat` (spike path E) so the struct
  profile has a real cell instead of a blank
- `run_sweep.sh` runs `-t 1` repeats CONCURRENTLY, `-t auto` repeats
  SERIALLY (each claims all 64 cores; contention could flip orderings)
- `sweep*.log` gitignored — regenerable; `raw/results-*.json` is the record
- upstream issue filing still a close-time decision, stretch only. Now
  **four** candidates: blob `Ref{Cvoid}`, silent appender errors,
  empty-vector→NULL / list non-ASCII truncation, and the LIST segfault
  (strongest — a supported API that kills the process)
- (standing) no unprompted next-step nudges; user triggers workflow steps
- (new, 2026-07-26) parallelize independent long jobs by default; state
  wall-clock up front — see memory `parallelize-long-independent-work`

## Next Steps

Resume with `/ws resume` (no arg — `.active` is set), then start phase 3
per impl.md:

1. write `research/duckdb-driver-jl/reference.md` merging: capability
   spike (+§2b addendum), driver study, phase 1 verdicts §1-§4, phase 2
   findings §5-§6, and the benchmark numbers. Structure per impl.md:
   executive summary; read path; write paths (per-path type tables +
   gotcha list); transactions/connections; benchmark methodology +
   results + tier-ordering conclusions; versioning statement.
2. every claim traces to a script in the dir or a driver `file:line`
3. add pointer headers to the two notes files (they stay as history)
4. add the ground-truth pointer to the held codegen session's
   `review-decisions.md`, **plus a flagged reconciliation note**: the
   measured tier ordering contradicts the recorded appender-first
   decision (decide on codegen resume, not here)
5. record the close-time yes/no per upstream bug

**Do not re-run the sweep** unless the harness changes — it is ~30 min.

## Relevant Files

- research/duckdb-driver-jl/ — findings.md (§1-§6), results.md,
  results.json, raw/results-*.json, bench_common.jl, bench_write.jl,
  bench_read.jl, run_all.jl, run_sweep.sh, verify_*.jl (5 scripts),
  Project.toml + Manifest.toml (pinned env)
- .claude-work/sessions/20260725-1252-duckdb-jl-driver-study-and-benchmarks/
  goal.md, impl.md (phases 1-2 marked DONE with the actual record)
- .claude-work/notes/20260725-1007-duckdb-jl-driver-study.md — the study
  being corrected; .claude-work/notes/20260723-1530-...capability-spike.md
- .claude-work/sessions/20260723-1109-julia-read-write-codegen/ — held
  session; review-decisions.md needs the phase 3 pointer
- ~/.julia/packages/DuckDB/2J7sd/src/ — driver source, ground truth
- untracked, not mine: research/parquet2-driver-jl/,
  research/quackio-driver-jl/

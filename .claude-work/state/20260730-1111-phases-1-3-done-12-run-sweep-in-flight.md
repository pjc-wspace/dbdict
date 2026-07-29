---
created: 2026-07-30T11:11:03+12:00
title: phases 1-3 done, 12-run sweep in flight
tags: [benchmarking, duckdb, julia, verification, ws-mid-session]
summary: Session 20260727-1540 paused with phases 1-3 committed and a 12-run benchmark sweep (6 repeats at each thread count, ~90 min) still executing. §7's transcription was proven correct against the original data; the harness was then repaired twice and re-measured. Phase 4 rewrites §7 against the new numbers and should start in a fresh context.
---

## Goal

Session `20260727-1540-benchmark-result-reconciliation-and-clarity` (ACTIVE,
paused mid-phase-2-amendment). Reconcile `reference.md` §7 against
`raw/*.json` and make §7 readable. Scope was widened twice by code review —
see the amendment block at the top of `goal.md`.

## Current State

**Phases 1–3 are DONE and committed** (`048cfc2`, `01f0df7`, `04c0482`,
`1aeacfd`). Phases 4–6 remain.

**A sweep is running in the background.** Started 11:07, ~90 min, so it lands
around 12:35. `./run_sweep.sh 6 6` — 6 repeats at 1 thread (three sequential
batches of 2) and 6 at 64 threads (serial). It cleared `raw/`, so **`raw/` is
empty or partial until it finishes**. On resume, check for **12** files
(`results-t1-{a..f}.json`, `results-tauto-{a..f}.json`).

The headline results so far:

- **§7's hand-transcription was already correct.** 142/142 claims verified
  against the ORIGINAL data, all 142 confirmed genuinely compared by mutation
  testing. The session's founding suspicion was wrong; the real defect was one
  level up, in the measurement.
- **Two measurement confounds fixed, harness re-measured twice.** The first
  repair was partial — only `read_first_chunk` closed its `QueryResult` — which
  made the three ranked read modes *non-comparable* and was worse than no fix.
  All three close now, and fixtures are dropped between cells.
- **Writes never move.** 24/24 orderings unanimous across 6 repeats at 64
  threads. §8.1's writer tiers are confirmed; the codegen contract is safe.
- **Reads: the fastest path is stable in 23 of 24 cells.** One genuine tie:
  `64t · read · flat · 10k` gave four distinct orderings in six runs.

## Key Decisions

- **Comparison is numeric within last-displayed-digit tolerance**, never string
  re-rendering — re-implementing `prettytime`/`format_bytes` from memory is the
  sourcing failure the project rules forbid.
- **Mutation testing over fixtures.** The failure mode that burned two earlier
  audit tools was a claim parsed and counted but never compared. Note it cannot
  catch *vacuous* both-absent checks — those need a separate bucket, which
  `bench.py` and `numbers.py` now have.
- **`PARALLEL_1T` capped at 2.** The harness's "no measurable contention" claim
  was established for two concurrent 1-thread runs; six was never verified, and
  `materialized` (builds a DataFrame) would not contend evenly with
  `stream_first` (one chunk). Six repeats run as three batches of two instead.
  Raising it requires a measurement.
- **Clear-and-resweep rather than appending repeats** — mixed provenance in
  `raw/` is what the new mtime guard flags as dangerous.
- §7.5 should stop reporting "N of 24 reproduced": that conflates the
  fastest-path claim with the full-ordering claim. Report both.

## Next Steps

1. **Wait for the sweep, then re-run the analysis** (all from the repo root):
   ```
   S=.claude-work/sessions/20260727-1540-benchmark-result-reconciliation-and-clarity
   ls research/duckdb-driver-jl/raw/          # expect 12 files
   python3 $S/tools/bench.py research/duckdb-driver-jl/raw research/duckdb-driver-jl/results.md
   python3 $S/tools/stability.py research/duckdb-driver-jl/raw --kind=read
   python3 $S/tools/stability.py research/duckdb-driver-jl/raw --kind=write
   python3 $S/tools/orderings.py /home/pjc/.claude/jobs/3702f96b/tmp/raw-old research/duckdb-driver-jl/raw
   ```
   The `raw-old` snapshot is in a job tmp dir that may not survive — it is
   recoverable with `git show 048cfc2^:research/duckdb-driver-jl/raw/<f>.json`.
2. **Answer the question the 1-thread repeats were run for:** was
   `1t · read · struct · 10k`'s split at n=2 real? Append the finding to
   `ordering-delta.md`, which already has a "read the last section first"
   marker because three sweeps are recorded there.
3. **Phase 4 — re-transcribe §7.** `numbers.py` will list every failing claim.
   `mismatches.md` lists what must change *beyond* the numbers. Trace every
   correction into §1, §4.1, §8.1, §8.2 — every defect across three sessions
   has been in a summary construct.
4. Phases 5 (repeat-collapse disclosure, needs a `run_all.jl` generator edit)
   and 6 (plain-language §7 summary, checker-verifiable ranking claims).

**Start phase 4 in a fresh context.** This session ran very long. Everything
phase 4 needs is on disk; `/state load` plus the four session docs is enough.

## Relevant Files

- `.claude-work/sessions/20260727-1540-…/goal.md` — amendment block at top
  records both scope widenings
- `…/impl.md` — six phases, 1–3 marked DONE with what actually happened
- `…/ordering-delta.md` — **authoritative stability analysis; read its last
  section first**, three sweeps are recorded
- `…/mismatches.md` — what phase 4 must change beyond the numbers
- `…/inventory.md` — every §7 claim mapped to a line number
- `…/review-triage.md` — both code review rounds, with what was rejected and why
- `…/tools/` — `bench.py`, `numbers.py`, `orderings.py`, `stability.py`,
  `inventory_check.py`
- `research/duckdb-driver-jl/` — `run_all.jl`, `bench_read.jl`, `bench_write.jl`,
  `run_sweep.sh` all repaired; `logs/` now committed
- Untracked and **not mine**: `research/duckdb-examples/`,
  `research/parquet2-as-alternative-backend/`, `research/quackio-driver-jl/`

---
created: 2026-07-27T08:45:29+12:00
title: session closed — duckdb.jl driver reference complete
tags: [duckdb, julia, benchmarking, documentation, ws-close]
summary: Driver study session closed. All 3 planned phases plus an unplanned phase 3b (adversarial review + full rewrite of reference.md). The codegen resumption gate is satisfied; next work is the held session 20260723-1109-julia-read-write-codegen.
---

## Where things stand

Session `20260725-1252-duckdb-jl-driver-study-and-benchmarks` is **CLOSED**.
Summary at `.claude-work/sessions/20260725-1252-.../summary.md`.

Commits: `6b4ff19` (phase 1), `d11ff24` (phase 2), `47bc2b4` (phase 3),
`8b31c48` (phase 3b rewrite). Working tree clean apart from two untracked
research dirs that are not mine (`research/parquet2-as-alternative-backend/`,
`research/quackio-driver-jl/`).

## The deliverable

`research/duckdb-driver-jl/reference.md` — 1527 lines, the single source of truth
for DuckDB.jl 1.5.2. TOC + quick-answers index; parenthetical citations
(`script.jl` / `file.jl:line`) with `Inferred:` spelled out; §4 ordered by writer
tier; §8 self-contained (5-tier selection, 16 never-emit/emit-instead rules with
code inline, required imports); 14 Julia examples, all executed, output verified
byte for byte.

Supporting: `findings.md` (raw record, superseded banner), `results.md` +
`raw/results-*.json`, five `verify_*.jl`, `read_path.jl` + `literal_matrix.jl`
(copied from the spike, confirmed to run here), the harness, pinned Manifest.

## What the next session needs to know

**The resumption gate is satisfied.** Next work is the held session
`20260723-1109-julia-read-write-codegen` — `/ws resume 20260723-1109-julia-read-write-codegen`.

**One decision is deliberately left open for it:** `review-decisions.md` finding 4
records "appender tier = scalar-only tables", justified by the docs' unmeasured
"much faster" claim. Measurement contradicts it — `register` + `INSERT…SELECT` is
3.4× faster at flat/1M with 538× fewer allocations, wins at every scale at 1
thread, and fails *loudly* where the appender fails silently. reference.md §8.1
proposes register → register_flat → bind → appender → literal. **Reconcile before
phase 5 writer-tier work.** A ⚠️ flag is in `review-decisions.md` itself.

**Two things that session's plan can now drop:**
- The appender-blob discrepancy queued for the phase-5 harness is settled — wired
  at `appender.jl:94`, throws before reaching C via `Ref{Cvoid}` at `api.jl:7261`.
  Just a never-emit rule; no harness work.
- Finding 14 is resolved: DuckDB_jll is **1.5.4+0**, engine v1.5.4. Fix impl.md,
  which says 1.5.3.

**One correction in its favour:** ENUM stays in the fastest writer tier. A Julia
`String` column registers fine and DuckDB casts VARCHAR→ENUM on insert — the
source notes implied `register` couldn't carry ENUM. Measured this session.

## Known follow-ups, not done

1. File the five upstream DuckDB.jl issues (decision recorded: yes to all five;
   reference.md §5.4 has ranks and reproducers). Filing is its own small task.
2. reference.md does not note that §5.2.1's bare-decimal-literal parsing also
   reaches **struct field literals** — `{'x': 1.0}` makes the field DECIMAL, not
   DOUBLE. Observed at close time while answering a question about read types;
   unrecorded in the doc.
3. Deep dedup between reference.md and findings.md was scoped out of the rewrite;
   ~24% of findings.md is verbatim-duplicated. Drift hazard if either is edited.

## Hard-won facts worth not rediscovering

- The appender **segfaults** on LIST at ~1M appends. Not a capability gap — the
  process dies, so no generated error handling can recover. Prepared bind survives
  4M over the same `create_value` path.
- A failed appender cell **does not advance the column cursor**, so later values
  land in the wrong columns. `COUNT(*)` is necessary but not sufficient.
- An `Appender` that outlives its transaction flushes at **GC time**, after a
  rollback. Non-deterministic, and does not reproduce reliably under test.
- More Julia threads never helped anything; the registered scan degrades worst
  (up to 7.8× at small scales). Run single-threaded.
- `using DuckDB, DBInterface` **fails** — DBInterface is a transitive dep.
- A streamed chunk declares `Tables.columnaccess` true but `columnnames` returns
  `(:tbl,)` with no error. Streaming readers must use `Tables.columns(chunk)`.

## Process lesson (also in insights)

Phase 3 audited every `file:line` and found one error; an adversarial pass then
found twelve, five critical, while confirming ~100 citations clean. Auditing
citations is not auditing claims — internal consistency, whether "measured" claims
were actually measured, and derived counts are separate passes. Giving reviewers
an executable environment is what turned opinion into findings.

## Context advice

Close-time context reading was requested from the user (Claude cannot measure it).
This session ran long — phases 1–2 in a prior context, phase 3 + 3b in this one,
including three subagent reviews. Recommend a **fresh session** before resuming the
codegen work, then `/state load` this file.

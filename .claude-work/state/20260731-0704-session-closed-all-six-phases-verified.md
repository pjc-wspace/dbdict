---
created: 2026-07-31T07:04:51+12:00
title: session closed, all six phases verified
tags: [benchmarking, duckdb, verification, ws-close]
summary: Session 20260727-1540 closed with all six phases done and all thirteen success criteria met. §7's transcription turned out to have been correct all along; the real defect was in the measurement, and after repair zero orderings moved. Three /code-review runs were skipped and are the top follow-up.
---

## Goal

Session `20260727-1540-benchmark-result-reconciliation-and-clarity` — **CLOSED**.
Verify `reference.md` §7 against `raw/*.json` and make §7 readable. Scope widened
twice by code review to include repairing the benchmark harness and re-running
the sweep.

## Current State

**All six phases DONE, all thirteen success criteria met.** Commits `048cfc2`
`01f0df7` `04c0482` `1aeacfd` `cbcd8bf` `4e82991` `2769930` `48705b3`.

Final verification, all green:

```
numbers.py    159 verified · 17 ranking · 0 vacuous · 0 FAILED
  --selftest  159 mutated · 0 survived
bench.py      results.md agrees with raw on every value
runblocks.py  14 clean · 0 failing
citations.py  160 resolved · 0 unresolved
anchors.py    57 links · 58 headings · 0 unresolved
vruns.py      0 shared verbatim runs
```

Two results worth carrying forward:

- **§7's hand-transcription was already correct** — 142/142 against the original
  data. The founding suspicion was wrong; the defect was one level up, in the
  measurement.
- **After repairing two confounds and re-sweeping 12 runs: `orderings MOVED: 0`.**
  Every absolute number in §7 changed, no ranking did. §8.1's writer tiers and
  the held codegen session's contract were never at risk.

## Key Decisions

- Compare numerically within last-displayed-digit tolerance, never by
  re-rendering strings — re-implementing `prettytime`/`format_bytes` from memory
  is the sourcing failure the project rules forbid.
- Transcribe from the regenerated `results.md` (mechanically produced,
  independently re-derived by `bench.py`) rather than hand-rendering nanoseconds.
- Mutation testing over fixtures, because the failure mode that burned two
  earlier tools was a claim parsed and counted but never compared.
- `PARALLEL_1T` capped at 2 — "no measurable contention" was established for two
  concurrent 1-thread runs and never for more. Raising it needs a measurement.
- Brace notation `stream_first < {materialized, streaming}` for pairs the sweep
  does not order. The three-way ordering would have been false.
- `mismatches.md` Part 2 was **superseded, not followed** — four of its rows were
  falsified by the 12-run sweep.

**The transferable finding:** a verification tool needs two orthogonal guards.
Mutation catches a claim parsed but never *compared*; coverage-count delta
catches a claim that stopped being *found*. `numbers.py` had hardcoded the
claimed values in its search patterns, so correcting a number made the claim
vanish and the run still reported clean — `--selftest` structurally cannot see
that.

## Next Steps

This session is closed. When picking up this area again:

1. **`/code-review` on three code changes** — `numbers.py` pattern fix (phase 4),
   `run_all.jl` header edit (phase 5), `numbers.py` ranking extractor (phase 6).
   The last is ~70 lines, the largest code change of the session, and its
   correctness rests on negative tests written by the same author as the
   implementation. **Highest-value item.**
2. Promote the nine audit tools from closed session dirs to
   `research/duckdb-driver-jl/tools/`.
3. Measure prepared bind (tier 3) and per-row INSERT to close the
   four-measured-vs-five-tiers gap that §7.0 now discloses. Needs a sweep.
4. Fix the memory-figure tolerance in `numbers.py` (coarser than
   last-displayed-digit — permitted a wrong third decimal).
5. Fix the allocations-column mislabel, two instances (§7.2's `1.705 GiB` cell,
   §7.3's `58.541 vs 59.137 MiB` prose) — memory figures in a column headed
   *allocations*.
6. The held **codegen session** is now unblocked: §8.1's tiers are confirmed
   unchanged, so its contract is safe to build on.

## Relevant Files

- `.claude-work/sessions/20260727-1540-…/summary.md` — the close-out record,
  criteria-by-criteria
- `…/impl.md` — six phases, each with what actually happened vs what was planned
- `…/mismatches.md` — Parts 1–4; **Part 2 is superseded, read Parts 3–4**
- `…/ordering-delta.md` — four sweeps recorded; **read the last section first**
- `…/inventory.md`, `…/review-triage.md`
- `…/tools/` — `bench.py`, `numbers.py`, `orderings.py`, `stability.py`,
  `inventory_check.py`
- `research/duckdb-driver-jl/reference.md` — §7.0 summary is new; §7.1–§7.5
  re-transcribed
- `research/duckdb-driver-jl/` — `run_all.jl`, `bench_read.jl`, `bench_write.jl`,
  `run_sweep.sh` all repaired; `raw/` holds 12 runs; `logs/` committed
- Untracked and **not mine**: `research/duckdb-examples/`,
  `research/parquet2-as-alternative-backend/`, `research/quackio-driver-jl/`

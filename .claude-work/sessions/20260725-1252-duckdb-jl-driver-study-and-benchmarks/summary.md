# summary: duckdb.jl — document and benchmark the julia duckdb driver

started: 2026-07-25T12:52
closed: 2026-07-27T08:45:29+12:00

## goal

Fully understand, benchmark, and document DuckDB.jl 1.5.2 in
`research/duckdb-driver-jl/`, as the resumption gate for the held julia codegen
session `20260723-1109-julia-read-write-codegen`. The codegen plan rested on
driver knowledge that was code-read and partially spiked but not measured:
writer-tier selection had no numbers behind it, several behaviors were inferred,
one spike/study discrepancy was unresolved, and the knowledge was scattered
across two notes files.

## what was accomplished

**Phase 1 — verification (`6b4ff19`).** Four scripts settled the four open
behaviors. Three claims the study marked *Inferred* were promoted to measured;
one study claim was refuted outright (§3c: registered-table type failure surfaces
at `register_table`, not at query bind time). Two results were more serious than
the questions asked: the appender's VARCHAR→ENUM cast works, but a failed cell
**does not advance the column cursor**, so surviving rows silently pair the wrong
values together — a row-count check cannot detect it; and appender rows still
buffered at rollback time escape the transaction and land later, at GC time.

**Phase 2 — benchmarks (`d11ff24`).** Harness plus a full sweep: 84 cells per run
× 4 runs (2 thread configs × 2 repeats), 60 measured, 24 skipped, 0 failed. All
24 write orderings reproduced; 22 of 24 read orderings did. The harness
content-verifies every cell before timing it rather than checking row counts — a
direct consequence of phase 1 — and that gate immediately caught a silent 1-ULP
DOUBLE loss in generated literal SQL. It also found that appending LIST values
**segfaults the process** at ~1M appends, while prepared bind survives 4M over the
same code path.

**Phase 3 — consolidated reference (`47bc2b4`).** `reference.md` merging the
spike, the study, phase 1 verdicts and phase 2 numbers, with every claim carrying
its source. Pointer headers added to both notes; the held codegen session's
`review-decisions.md` gained a driver ground-truth pointer, a flagged
reconciliation on finding 4, and a resolution for finding 14.

**Phase 3b — adversarial review and full rewrite (`8b31c48`), unplanned.** Three
parallel adversarial agents (accuracy / readability / examples), each given the
pinned Julia environment so they could execute rather than opine. Twelve
substantive errors found, all re-verified before acting. Five were critical,
including a tier table that routed BLOB columns to the appender while the same
document said never to emit `duckdb_append_blob`. Three new driver findings were
absorbed. The document went from 2 non-runnable Julia blocks to 14 executed
examples whose documented output matches actual byte for byte.

## key decisions

- **Measure both thread configurations**, not just the default. The answer
  inverted the expectation: more Julia threads never helped, and hurt the
  fastest path worst (registered scan, flat 1M: 58.1 → 111.2 ms).
- **Content-verify every benchmark cell before timing it.** Row counts are
  insufficient once you know a failed append misaligns columns. This decision
  paid for itself twice.
- **Do not root-cause the LIST segfault.** `goal.md` puts patching DuckDB.jl out
  of scope; two hypotheses were tested, both inconclusive, and both recorded so
  they are not re-run. The measured behavior and its codegen consequence are the
  deliverable.
- **State the measured tier ordering, but do not re-decide the writer tier here.**
  The benchmarks contradict the recorded appender-first decision; that
  reconciliation belongs to the codegen session and is flagged there.
- **Upstream issues: documented, not filed.** Ranked with reproducers in
  reference.md §5.4. Decided 2026-07-26 to file all five, then reversed
  2026-07-27 (user): not filing for now. Every defect has a documented workaround,
  so nothing downstream waits on an upstream fix.
- **Single-source the tier table.** The BLOB contradiction existed only because
  tier guidance lived in two places; §7.6 now defers to §8.1.

## the deliverable

`research/duckdb-driver-jl/` — `reference.md` (1527 lines, 14 executed examples),
`findings.md` (raw record, superseded banner), `results.md` + `results.json` +
`raw/results-*.json`, five `verify_*.jl` scripts, two type-matrix scripts copied
from the spike, the benchmark harness, and a pinned `Project.toml`/`Manifest.toml`.
Re-runnable when a new DuckDB.jl releases — that is the trigger to refresh.

## what the codegen session inherits

- A five-tier writer order grounded in measurement (§8.1), flagged as
  contradicting `review-decisions.md` finding 4 — **to reconcile on resume**.
- 16 hard never-emit/emit-instead rules (§8.2), each traced to a measured failure.
- The required-imports block, including that `using DuckDB, DBInterface` fails.
- Settled: the appender-blob discrepancy needs no phase-5 harness work.
- ENUM stays in the fastest tier — `register` carries it via cast, which the
  source notes had implied otherwise.

## known follow-ups (not done, deliberately)

- Filing the five upstream DuckDB.jl issues, if that decision is ever revisited.
- ~~struct-literal DECIMAL parsing unrecorded~~ — **done 2026-07-27**: §5.2.1 and
  §8.2 rule 5 now state that the `%.17e` rule is recursive, and that the reference
  serializer already handles it.
- The deep dedup between `reference.md` and `findings.md` was scoped out of the
  rewrite; ~24% of `findings.md` is verbatim-duplicated.

## insights captured

- `.claude-work/insights/20260726-1128-duckdb-jl-appender-silent-failures-and-confounded-probes.md`
- `.claude-work/insights/20260726-1322-benchmark-harness-caught-two-driver-defects.md`
- `.claude-work/insights/20260726-1359-consolidating-notes-surfaces-citation-and-headline-drift.md`
- `.claude-work/insights/20260727-0845-adversarial-review-with-execution-rights.md`

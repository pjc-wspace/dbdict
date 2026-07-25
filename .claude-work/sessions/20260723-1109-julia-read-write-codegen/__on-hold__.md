# on hold

timestamp: 2026-07-25T12:42:43+12:00
phase: phase 1 (capability spike) — work complete, /ws done not yet run
reason: fully understand, benchmark, and document the DuckDB.jl driver
  before continuing codegen work (user direction)

## state at hold time

Full brain dump:
`.claude-work/state/20260725-1242-julia-codegen-on-hold-pending-driver-study.md`

Short version:

- phase 1 spike done (8 scripts in `spike/`, findings in
  `notes/20260723-1530-duckdb-jl-capability-spike.md` + §2b addendum);
  the phase's `/ws done` (insights/impl-mark/commit) was never run —
  this hold's commit carries the artifacts instead
- adversarial plan review: 15 findings, ledger in `review-decisions.md`;
  decided 1-7, 11, 14 + supported/unsupported type lists;
  open: 8 (identifier safety), 10 (gen julia output model),
  12 (legacy-name companion pairing), 13 (trivial verify wording),
  15 (pk phrasing + pk-on-compound)
- goal.md and impl.md are STALE vs review-decisions.md — the batch edit
  applying decided findings has not been made; review-decisions.md is
  the source of truth
- driver study complete: `notes/20260725-1007-duckdb-jl-driver-study.md`
  (code+docs, file:line cited, DuckDB.jl 1.5.2)

## resumption gate (the hold reason, concretely)

1. benchmark the driver write/read paths (study was code+docs only):
   appender vs registered-scan+INSERT..SELECT vs literal SQL at
   realistic sizes; streaming vs materialized reads
2. settle the appender-blob discrepancy (spike ERR vs code path present)
3. verify inferred items: appender VARCHAR→ENUM cast, appender flush in
   transactions, StructArray through register_table
4. consolidate spike + study + benchmarks into one driver reference doc

then: finish findings 8/10/12/13/15 → batch-edit goal.md + impl.md →
run the overdue `/ws done` for phase 1.

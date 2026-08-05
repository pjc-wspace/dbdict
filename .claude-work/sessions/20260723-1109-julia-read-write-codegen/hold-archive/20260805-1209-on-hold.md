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

## 2026-08-04 — gate satisfied, premises moved, goal superseded

Appended by session `20260801-1257-v0.3.0-direction-doc-and-repositioning`,
phase 4. **This session stays held.** Nothing here resolves anything; it records
what changed underneath it.

**The resumption gate above is satisfied.** All four driver-knowledge items were
closed by three subsequent sessions (`20260725-1252`, `20260727-0924`,
`20260727-1540`), which produced the consolidated driver reference at
`research/duckdb-driver-jl/reference.md`. What blocks resumption now is not
missing knowledge but **undecided scope**.

**`goal.md` is superseded, not rewritten.** It carries a banner as of
2026-08-04; its body is unchanged and uncorrected. The 0.3.0 re-baseline removed
most of its premises — chiefly the **per-language companion mapping file**,
which direction §7 deletes outright — and the maintainer's assessment is that
the goals themselves were wrong rather than merely stale. Rewriting it would
have produced a document matching none of the existing records. Canonical scope
is now `docs/vision-direction-0.3.0.md`; codegen's ordering and dependencies
will be carried by `docs/roadmap-0.3.0.md`.

**`review-decisions.md` is partly moot under V1 — flagged, not resolved.**
Several of its 15 findings rest on premises V1 removes: the ones concerning
`TIMESTAMPTZ` (removed permanently), "all dict-expressible types" (V1 is ten
scalars), and companion-file pairing including finding 12's legacy-name case
(no companion file exists in V1). Findings that look V1-agnostic — identifier
safety (8), output model (10), verify wording (13), primary-key phrasing (15) —
are still undecided from July and were **not** revisited here. Whoever resumes
reconciles the ledger; the batch edit the gate asks for should not be attempted
against the superseded `goal.md`.

**Practical note for whoever resumes:** `/ws plan` rebuilds `impl.md` on resume
anyway, and the goal now needs authoring rather than amending. Starting a fresh
session and mining this one for artifacts may be cheaper than resuming it.

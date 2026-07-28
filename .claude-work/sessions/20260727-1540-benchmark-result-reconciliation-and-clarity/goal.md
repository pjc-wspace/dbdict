# benchmark result reconciliation and clarity

> **AMENDMENT 2026-07-28 — scope widened after code review.** The original goal
> excluded rerunning the sweep and excluded the harness entirely. A `/code-review`
> found two *measurement confounds* rather than transcription errors: reads were
> benchmarked with every 1M-row write table still resident, and `stream_first`
> abandoned thousands of DuckDB result handles per cell so its latency partly
> measured finalizer backlog. §7 could have been made perfectly faithful to
> `raw/*.json` and still have described the wrong experiment.
>
> The user directed (2026-07-28) fixing the confounds and re-running, fixing all
> six harness bugs, and fixing `anchors.py`. Sections below marked
> **[amended]** reflect that. The consequence is that **every number in §7
> changes**, so "reconciliation" now means transcribing a fresh measurement
> rather than correcting an old one — and the orderings that feed §8.1's writer
> tiers may move, which reaches the held codegen session's contract.

## problem

`research/duckdb-driver-jl/` holds the same benchmark measurements at four
layers, and only the bottom two have ever been checked against each other:

| Layer | Nature | Ever verified? |
|---|---|---|
| `raw/results-{t1-a,t1-b,tauto-a,tauto-b}.json` | 4 runs; §9 calls these authoritative | n/a — ground truth |
| `results.json` | merged bundle, `{runs: [4]}` | derived mechanically |
| `results.md` | **generated** by `run_all.jl merge` | derived mechanically |
| `reference.md` §7 | **hand-transcribed** tables + **hand-computed** ratios | **no** |

The previous session audited `reference.md` four ways — `runblocks.py` (code
executes), `citations.py` (source cites resolve), `anchors.py` (links resolve),
`vruns.py` (no claims lost). None of them checks a *number* against a
*measurement*. §7 is the one section of a document declared "audit-clean" that
no audit actually covered, and it is entirely hand-copied arithmetic.

Separately, §7 is unreadable as an *answer*. It opens with methodology and
then presents four dense tables. Nothing tells a reader in plain language what
the measured methods are or how they came out — the reader has to already know
what `register_flat` means and cross-reference §4 to find out. And §8.1 states
**five** writer tiers while §7 measured **four** paths: prepared bind (tier 3,
§4.4) and per-row INSERT were never benchmarked, which §7.1 mentions only in a
subordinate clause of the "Paths measured" bullet. Any friendlier summary that
does not say this outright will imply all five tier positions are measured.

Three known clarity defects. The first two are the same thing:

- `run_all.jl:186` — `# collapse repeat runs: report the FIRST run's numbers
  per path`. Every absolute time in `results.md` is repeat **a** only; repeat
  **b** exists solely to populate the ordering-stability column. `results.md`
  never says so, and presents the figures as *the* numbers.
- `reference.md` §7.1 inherits that silence. A reader cannot tell whether
  `58.115 ms` is a median across repeats, a minimum, or one arbitrary run.
  It is one arbitrary run.
- Neither disclosure helps a reader who cannot tell `register` from
  `register_flat` without leaving §7.

The reconciliation half of this was recorded as an open follow-up at the close
of two prior sessions and deferred both times.

## success criteria

1. A reusable checker in the session's `tools/` re-derives every numeric claim
   in `reference.md` §7 from `raw/*.json` and reports per-claim pass/fail.
   It runs clean at session end.
2. Coverage is stated as a count, not a feeling: the checker reports how many
   claims it parsed and verified, and the inventory from phase 1 accounts for
   every number in §7 as either *checked* or *explicitly out of the checker's
   reach* (with the reason recorded).
3. Every mismatch found is either corrected in `reference.md` from `raw/*.json`,
   or recorded as a follow-up with the reason it was not corrected.
4. The two restatements of §7 figures outside §7 (§1 line ~75, §8.1 tier
   preamble) agree with the corrected §7.
5. The repeat-collapse is stated plainly in both places a reader meets the
   numbers: `results.md`'s header and `reference.md` §7.1.
6. §7 opens with a plain-language summary a reader can act on without leaving
   the section: each measured method named in one line, which paths were **not**
   measured (prepared bind / tier 3, per-row INSERT) and are therefore reasoned
   rather than measured, and how the measured methods came out relative to each
   other for writes and for reads.
7. Every ranking sentence in that summary is verified by the checker against
   `raw/*.json` — the summary is covered by criterion 2's count, not exempt
   from it. Prose the checker cannot parse is rewritten until it can, or moved
   out of the summary.
8. The summary states rankings only. It does not recommend a path — §8.1
   remains the single place tier selection is stated, per §7.6.
9. `reference.md`'s four existing audits still pass — `runblocks.py`,
   `citations.py`, `anchors.py`, `vruns.py`.

**[amended 2026-07-28]**

10. The re-run sweep completes with all four runs present, no crashed
    verification probe, and no cell left unchecked for ordering stability.
11. §7 states both confounds and what changed: that reads are now measured on a
    clean database, and that `stream_first` includes a deterministic
    `duckdb_destroy_result` inside the timed region.
12. Any ordering that moved between the old and new sweeps is called out
    explicitly, and traced into §8.1 if it changes a tier. A tier change is a
    change to the codegen contract and must not be delivered silently.
13. The old numbers are not simply overwritten: the pre-existing
    `raw/results-*.json` remain recoverable from git history, and the summary
    records that §7 describes a different experiment from the one the previous
    session certified.

## scope

**in:**
- every numeric claim in `reference.md` §7 — the §7.2 write table, the §7.3
  read table, the §7.4 thread-count table and its change ratios, §7.5's
  ordering-stability counts and named flips, §7.1's coverage counts
  (84 cells × 4 runs, 60 measured, 24 skipped, 0 failed, 9 `register_flat`
  skips per run), and the derived ratios in §7's prose (3.4×, 538×, 328×,
  304×, ~8 allocs/row, ~20 allocs/row, 1.705 GiB, 246 µs → 420 µs / 1.7×,
  58.541 vs 59.143 MiB, ≤7%)
- benchmark-derived numbers restated elsewhere in `reference.md` (§1, §8.1)
- a one-line disclosure of the repeat-collapse in `results.md` and §7.1
- a plain-language opening summary for §7: what each measured method is (one
  line, linking to its existing home in §3/§4 rather than re-explaining it),
  what was not measured, and the measured ordering for writes and reads
- the reusable checker, in this session's `tools/`

**in [amended 2026-07-28]:**
- fixing the two measurement confounds and **re-running the full sweep**:
  reads now get a fresh database (`run_all.jl`), and `read_first_chunk` closes
  its `QueryResult` deterministically (`bench_read.jl`)
- the six harness defects found by review: the signal-blind verification check,
  the discarded probe output, vacuously-true ordering stability, the swallowed
  failure in `run_sweep.sh`, `first(runs)`-only environment reporting, and
  silently unrendered out-of-range cells
- `anchors.py`, since goal criterion 9 leans on it
- disclosing both confounds and the deterministic-close trade-off in §7

**out:**
- restructuring the four layers, or demoting `results.md` the way `findings.md`
  was demoted last session. Verify and fix in place; single-sourcing is a
  separate decision
- changing what `results.md` reports per cell (both repeats, spread, min vs
  first). Disclosure only — the numbers stay as they are
- any claim in `reference.md` that is not benchmark-derived
- reconciling `sweep.log` / `sweep-t1-*.log` (gitignored console transcripts)
- re-explaining any method in §7. The summary glosses and links; §3.3, §3.4 and
  §4.2–§4.6 keep sole ownership of what each path *is*
- restructuring §7's existing tables, changing their units, or rewriting §7.4.
  The summary is added above them; they stay as they are
- **measuring** prepared bind or per-row INSERT to close the four-vs-five gap.
  The summary discloses the gap; filling it is a benchmark rerun, excluded above
- moving the eight existing audit tools out of the closed session's directory
  (recorded as a follow-up instead — see constraints)

## constraints

- **`results.md` is a build artifact.** A hand-edit to it is reverted by the
  next `run_all.jl merge`. The header disclosure must be a change to the
  generator's `println` in `run_all.jl` (~line 146), then a regeneration.
  Regeneration reads existing `raw/*.json` — no benchmarks are re-run.
- **The regeneration diff must be header-only.** If regenerating produces
  changes beyond the added line, `results.md` was hand-edited after generation
  at some point — that is a finding, and it stops the phase until understood.
- **The checker must fail loud.** Last session two verification tools were
  broken in opposite directions and both reported clean. The checker gets
  deliberate negative tests — feed it a known-wrong number and confirm it
  fails — before its clean run is believed.
- **Do not trust a fact map you did not just rebuild.** Last session three of
  nine per-fact actions were stale by the time they were executed. The phase-1
  inventory is input to the checker, not a substitute for it.
- **Recheck the defect quartet.** Every defect across two sessions appeared in
  §1, §4.1, §8.1 or §8.2 — summary constructs, never evidence sections. Any
  §7 correction must be traced into those four.
- Environment pinned and unchanged: DuckDB.jl 1.5.2 / DuckDB_jll 1.5.4+0,
  julia 1.12.6, driver source `~/.julia/packages/DuckDB/2J7sd/src/`.
- Tooling: plain `python3`, positional args, matching the eight existing
  `tools/*.py` in invocation style. If it grows past a few flags it moves to
  the uv-script + typer tier.
- **Checker location — decided (user, 2026-07-27): option 3.** It is written in
  this session's `tools/`, matching the precedent of the eight tools in the
  closed `20260727-0924-dedup-…/tools/`. Promoting all nine to
  `research/duckdb-driver-jl/tools/` — next to the document they audit, instead
  of scattered across closed session dirs — is a **recorded follow-up**, not
  this session's work. Rationale: keeps scope honest and makes the promotion a
  deliberate decision rather than a side effect.
- **A prose summary is a summary construct.** All five defects found last
  session were in summary constructs — the executive summary, the tier table, a
  guard count, a list label — and none in an evidence section; the same held
  across the session before it. Criterion 7 exists because review is not a
  sufficient guard for this class; machine-checkability is.
- Context budget: don't start a phase at ≥25%.

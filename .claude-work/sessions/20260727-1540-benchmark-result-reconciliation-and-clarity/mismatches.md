# §7 verification results

## Part 1 — against the ORIGINAL data (pre-sweep), 2026-07-28

The session's founding question was whether `reference.md` §7, hand-transcribed
from `results.md` and never machine-checked, actually matches the measurements.

**It does. Completely.**

```
claims parsed:   138
  cell       93     table values in §7.2, §7.3, §7.4
  count       5     §7.1 coverage tallies
  derived    16     computed ratios, incl. restatements in §1, §8.1, appendix A
  marker     24     ❌ / n/a / excluded cells asserting a path was not measured
claims failed:   0

mutation self-test
  claims mutated:    138
  survived mutation:   0
```

Zero transcription errors across 138 claims, and every one of the 138 is
genuinely *compared* — perturbing any of them produces a failure, so the clean
result is not an artefact of claims being parsed and then ignored.

That is the answer to "is §7 faithful to `raw/*.json`": yes, it was already.
The previous session's hand-transcription was accurate. This session's value
therefore shifts to what the review exposed — that §7 was faithfully describing
a measurement taken under two undisclosed confounds — plus the clarity work.

> The transcription being correct is a real result, not an anticlimax. It was
> unknown before, it was asserted without evidence by two prior sessions, and
> a wrong number in §8.1's tier rationale would have propagated into codegen.

### two checker bugs found by running it

Both would have reported a correct document as wrong:

1. **Wrong percentage denominator.** "64 threads 7% *faster*" means
   `(t1 − t64)/t1` = 7.06%, not `(t1 − t64)/t64` = 7.60%. The checker used the
   latter and flagged a correct claim. Fixed.
2. **A memory figure in the allocations column.** §7.2's header says
   "Median · rows/s · allocations", but `struct/1M/literal` (L1297) puts
   `1.705 GiB` third — a *memory* value — to support the prose claim at L1315.
   The checker now detects a byte-unit suffix and verifies it against
   `memory_bytes`. See the document defect below.

### document defect found (not a transcription error)

| Where | What | Disposition |
|---|---|---|
| L1297 | `struct/1M/literal` renders memory (`1.705 GiB`) in a column the header calls *allocations*. Every other cell in the column is an allocation count | fix in phase 5/6 clarity work — either label the column honestly or move the figure into prose |

## Part 2 — against the RE-SWEPT data, 2026-07-29 (second repair)

```
claims verified: 142   (real comparisons)
vacuous:           0
claims failed:    87
```

**These 87 are not defects.** They are the transcription being deliberately
invalidated: the harness was repaired, the sweep re-run, and §7 still describes
the old measurement. Phase 4 re-transcribes against the new
`raw/*.json`. Read the phase 4 diff with that distinction in mind — nobody made
a mistake here.

The 55 that still pass are the 24 not-measured markers (which paths are
unavailable did not change), the §7.1 coverage counts (84 cells per run × 4
runs, 60 measured, 24 skipped, 0 failed — identical), and cells that landed
within tolerance of their old values.

### what phase 4 must change beyond the numbers

| Where | Change | Why |
|---|---|---|
| §7.5 read tally | **22 of 24 → 20 of 24** | three 64-thread cells became unstable; the one 1-thread instability became stable |
| §7.5 second flip | rewrite, not renumber | in the new sweep both repeats of `64t read flat 10k` put `streaming` first and the disagreement is between `materialized` and `stream_first`, so §7.5's "this is a **latency** instability" no longer describes it |
| §7.5 | new: all instability is now at 64 threads | and two repeats cannot separate "the fix revealed 64-thread noise" from "the fix added it" — state the limit |
| §7.3 list/100k and struct/10k@64t | the two moved orderings | `materialized` ↔ `streaming` swap; confirms §7.3's existing "wash for throughput" prose |
| §7.2 L1297 | `1.705 GiB` sits in the allocations column | pre-existing defect, unrelated to the re-sweep |
| §7.1 methodology | disclose the deterministic close | **all three** read modes now include a bounded `duckdb_destroy_result` inside the timed region — the symmetry is the point, since the modes are ranked against each other |
| §7.1 methodology | disclose per-cell fixture drops | every cell is now measured without other cells' tables resident |
| §7.1 methodology | disclose the fresh read database | and that it made no measurable difference — a null result worth stating |
| §8.1, §7.6 | **no change needed** | zero write orderings moved; the tier selection is untouched |

Full analysis in `ordering-delta.md`.

## Part 3 — against the 12-RUN sweep, 2026-07-30 (authoritative)

**Part 2 above is superseded.** It was measured against the second-repair sweep
at 2 repeats per config; this is 6 repeats at both thread counts, 12 runs total,
`raw/` cleared beforehand. Where Part 2 and Part 3 disagree, Part 3 wins.

```
claims verified: 142   (real comparisons)   ← unchanged from Parts 1 and 2
  cell 93 · count 5 · derived 16 · marker 24 · order 4
vacuous:           0
claims failed:    91                        ← 51 still pass

mutation self-test
  claims mutated:     51   (the passing set)
  survived mutation:   0
```

Coverage held at 142, which is phase 4's verify criterion. The 91 failures are
again **not defects** — the harness was repaired, the sweep re-run, and §7 still
described the old measurement.

### failures by section

| Section | Failures | Nature |
|---|---|---|
| §7.2 write table | 45 | medians + rows/s |
| §7.4 thread table | 21 | both values per row + stated change |
| §7.3 read table | 18 | medians |
| prose ratios | 5 | 2 distinct claims, one restated at 4 sites |
| §7.5 | 1 | read tally |
| §7.1 | 1 | `runs: 4 → 12` |

### what still passes, and why it matters

**Zero failures in the allocations and memory columns**, and 11 of the 16 derived
ratios hold: `538×`, `328×`, `~8 allocs/row`, `~20 allocs/row`, `1.705 GiB`,
`58.541 vs 59.143 MiB`, `≤7%`. Allocation counts and byte totals are properties
of *what the code does*; the confounds were about *what contended for the
machine*. Timing moved, work did not — independent corroboration of
`orderings MOVED: 0`.

### Part 2 rows now falsified

| Part 2 row | Status |
|---|---|
| "§7.5 read tally 22 → **20** of 24" | **wrong** — it is **17** of 24 at n=6 |
| "§7.3 list/100k and struct/10k@64t — the two moved orderings" | **wrong** — `orderings MOVED: 0`; these are repeat-disagreement, not moves |
| "new: all instability is now at 64 threads" | **wrong** — `1t·read·list·100k` and `1t·read·struct·1M` are both dominant 5/6 |
| "two repeats cannot separate revealed-vs-added noise" | **resolved** — 6 repeats at both counts; the tie reproduces independently |
| "§7.5 second flip: both repeats put `streaming` first, disagreement is materialized-vs-stream_first" | **wrong** — at n=6 `64t·flat·10k` has 5 orderings and 3 different winners |
| "§8.1, §7.6 — no change needed" | **holds** — 0 write orderings moved |
| "§7.2 L1297 `1.705 GiB` in the allocations column" | **holds** — pre-existing, phase 5/6 |
| "§7.1 methodology disclosures (×3)" | **holds** — all three still required |

### what phase 4 must change beyond the numbers

| Where | Change | Why |
|---|---|---|
| §7.1 repeats | 2 → 6 per configuration, **and** the concurrency note | the `-t 1` repeats now run two at a time in three sequential pairs (`PARALLEL_1T=2`), not all concurrently |
| §7.5 flip table | 2 rows → **7**, drop the "latency instability" note | the note describes a distribution that no longer exists |
| §7.5 split reporting | **defer to phase 6** | `extract_stability` matches two fixed sentence forms; a restructure breaks parsing and drops coverage below 142. Additive prose + new checker coverage is phase 6's remit |
| §7.3 "one of the two non-reproducing orderings sits here" | rewrite | there are 7 unstable cells and 6 of them are exactly this swap — the prose is now *understating* its own evidence |
| §7.3 `59.143 → 59.137 MiB` | correct it | see checker gap below — the tool will not force this one |
| §7.1 methodology | 3 disclosures: symmetric bounded result close, per-cell fixture drops, fresh read DB (with its null result) | §7 otherwise still describes the pre-repair experiment |

### two tooling gaps found while doing this

1. **`impl.md:155` overstates the checker.** It says §7.5's "two named
   non-reproducing cells, and the one cross-config write ordering difference"
   are verified. `extract_stability` (`tools/numbers.py:377-414`) emits only the
   four count claims — the `order 4` in the breakdown is exactly those. §7.5's
   tables are hand-verified against `stability.py`. Correct `impl.md`.
2. **Memory-figure tolerance is coarser than last-displayed-digit.** §7.3's
   `59.143 MiB` passes against a true `59.137 MiB` — a 6,293-byte gap, where
   last-displayed-digit on a 3-decimal MiB value would be ±524 bytes. Mutation
   still catches the claim (perturbation is large), so it is not the
   parsed-but-never-compared failure mode; it is a tolerance that permits a
   wrong third decimal. Recorded as a follow-up, not fixed in phase 4.

### Part 4 — a third tooling gap, found by phase 4's own verify criterion

**`numbers.py`'s derived-ratio patterns hardcoded the claimed values.** The
original list was:

```python
(r"\*\*3\.4×\*\*|3\.4×", speedup, ...),
(r"304×",                 litratio, ...),
```

So the checker located those claims by searching for the literal string `3.4×`.
Correcting the document to `3.6×` did not make the claim re-check — it made the
claim **vanish**. The run then reported:

```
claims verified: 137        ← was 142
  derived  11               ← was 16
claims failed:   0
OK — every parsed claim in §7 agrees with raw/*.json
```

A clean pass, with five claims silently no longer checked, including the
`3.4×`/`3.6×` ratio restated at all four sites — the single most-restated number
in the document and the one §8.1's tier rationale rests on.

**`--selftest` cannot catch this.** Mutation perturbs claims the checker *found*
and asserts the comparison fails. It is silent about claims that disappeared.
This is a distinct failure mode from the parsed-but-never-compared one that
motivated mutation testing in phase 3, and it needs a different guard.

**What caught it:** phase 4's verify criterion — *"coverage count unchanged from
phase 2 (a drop means claims went missing rather than getting fixed)"*. Written
before anyone knew this bug existed. Keep that criterion on every future phase
that edits a number.

**Fix applied** (`tools/numbers.py:361-379`): the numeric slot is matched
generically and the claim is identified by the words around it —
`N× faster`/`N× the appender`, `N× fewer allocations`/`N× less (`,
`N× less memory`, `N× slower than`. Verified to match exactly the four speedup
sites, three allocation sites, one memory site and one literal-ratio site, and
nothing else. After the fix: 142 verified, 16 derived, 0 failed, and
`--selftest` mutates **142 of 142** with 0 surviving.

### remaining follow-ups (not fixed in phase 4)

| # | Item |
|---|---|
| 1 | **Memory-figure tolerance is coarser than last-displayed-digit.** §7.3's `59.143 MiB` passed against a true `59.137 MiB` — a 6,293-byte gap where 3-decimal MiB implies ±524 bytes. Corrected the digit by hand; the tolerance is unchanged and would still admit a wrong third decimal |
| 2 | **`impl.md:155` overstated the checker** — claimed §7.5's named non-reproducing cells and the cross-config write ordering difference were verified. They are not; only the four counts are. Corrected in `impl.md`; §7.5's tables remain hand-verified against `stability.py` |
| 3 | **Second instance of the allocations-column mislabel.** §7.2's `1.705 GiB` cell was already recorded. §7.3's "the allocation columns are near-identical (flat/1M: 58.541 vs 59.137 MiB)" is the same confusion in prose — MiB figures described as allocation counts. Both belong to the phase 5/6 clarity work |
| 4 | **No checker coverage for the fastest-path claim.** §7.5 reports full-ordering reproduction (17 of 24) because that is the sentence form `extract_stability` parses. The stronger and more useful claim — the fastest path is stable in 23 of 24 cells — is deliberately absent rather than stated unchecked. Phase 6 adds the prose *and* the coverage together |

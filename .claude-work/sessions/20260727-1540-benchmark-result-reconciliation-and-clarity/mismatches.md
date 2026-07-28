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

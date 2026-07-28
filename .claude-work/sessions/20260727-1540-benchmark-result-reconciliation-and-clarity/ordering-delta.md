# ordering delta: original sweep vs repaired sweep

Required by `goal.md` criterion 12. The orderings, not the absolute times, are
what §7.5 calls the deliverable, and §7.6 feeds them into §8.1's writer tiers —
the codegen contract. So the question after repairing the harness is not "did
the numbers move" (they always do) but "did any *ordering* move, and does it
reach a tier".

Produced by `tools/orderings.py`, which reproduces `run_all.jl:155-160`'s rule.
Old data recovered from git (`HEAD:research/duckdb-driver-jl/raw/`); new data
from the 2026-07-29 sweep.

> **There were two repaired sweeps; this reports the second.** A code review
> found the first repair was partial — only `read_first_chunk` closed its
> `QueryResult`, so `stream_first` paid a deterministic destroy inside its timed
> window while `materialized` and `streaming` still leaked to finalizers whose
> GC landed in the next mode's window. The three modes are *ranked against each
> other*, so a bias they all share largely cancels while a bias one carries
> alone does not: the half-fix was worse than no fix. All three now close, and
> fixtures are dropped between cells so no cell is measured with another's data
> resident. The first repaired sweep's "3 unstable" was an artefact of that
> asymmetry and is not reported as a result.

```
cells compared:            48        (24 write + 24 read)
orderings unchanged:       41
orderings MOVED:            2
unstable in old sweep:      2        (repeats disagree)
unstable in new sweep:      4        (repeats disagree)
insufficient data:          0        (fewer than two runs — none)
```

| Kind | Cells | Unchanged | Moved | Unstable |
|---|---|---|---|---|
| **write** | 24 | **24** | **0** | **0** |
| read | 24 | 17 | 2 | 4 |

## the headline: no write ordering moved

**All 24 write orderings are identical between the sweeps**, and all 24
reproduced across repeats within each. §8.1's writer tier selection rests
entirely on write orderings, so **the codegen contract is unchanged**. The risk
flagged when scope was widened — that repairing the harness could move a tier —
did not materialise, under either repair.

## the two moved orderings

| Cell | Was | Now |
|---|---|---|
| 1t · read · list · 100,000 | `stream_first < materialized < streaming` | `stream_first < streaming < materialized` |
| 64t · read · struct · 10,000 | `stream_first < materialized < streaming` | `stream_first < streaming < materialized` |

Both are `materialized` ↔ `streaming` swaps in 2nd and 3rd place, and both move
in the same direction. §7.3 already states "**Materialized vs streaming is a
wash for throughput.** Each wins some cells, the gaps are small… Do not choose
between them on throughput." These moves confirm that prose. `stream_first`
remains first in both, as it is in every read cell.

## instability: 2 → 4, and it relocated

| Cell | Old | New |
|---|---|---|
| 1t · read · struct · 1M | unstable | **now stable** |
| 64t · read · flat · 10k | unstable | unstable |
| 64t · read · rich · 10k | stable | **newly unstable** |
| 64t · read · list · 10k | stable | **newly unstable** |
| 64t · read · struct · 1M | stable | **newly unstable** |

The relocation is the informative part: **every instability is now at 64
threads**, and the one 1-thread instability the original sweep had is gone.
That is the shape you would predict if the finalizer noise the close removed
was inflating variance at low thread counts, while 64-thread reads stay
inherently noisy — which §7.4 independently establishes ("the registered scan…
degrades sharply, worst at small scales"). Three of the four are at the 10,000
scale.

Two repeats cannot separate "the fix revealed 64-thread noise" from "the fix
added it". That limitation belongs in §7.5 rather than being papered over.

Consequence for §7.5's tallies, to restate in phase 4:

| Claim | Old value | New value |
|---|---|---|
| write orderings reproduced | all 24 | all 24 (unchanged) |
| read orderings reproduced | 22 of 24 | **20 of 24** |

§7.5's note that the `64t read flat 10k` case is "a **latency** instability, in
the metric §7.3 calls the actual result" no longer describes it: in the new
sweep both repeats put `streaming` first and the disagreement is between
`materialized` and `stream_first`. That sentence needs rewriting, not
renumbering.

## what the fixes actually did

Measured on `t1-a`, original vs first (asymmetric) repair — the cleanest read on
the close, because only `stream_first` changed there:

| Fix | Effect |
|---|---|
| **close the `QueryResult`** | `stream_first` got faster everywhere: flat/1M 0.420 → 0.369 ms (−12%), rich/1M 0.583 → 0.536 ms (−8%), list/1M 0.537 → 0.488 ms (−9%). The old figure was partly finalizer backlog, as predicted, and removing it moves the number in the direction that confirms the mechanism |
| **fresh database for reads** | **No measurable effect.** `materialized` and `streaming` moved 0.97–1.05×, within noise. Gigabytes of resident write tables in an in-memory DuckDB on a 503 GB machine cost essentially nothing |
| **drop fixtures between cells** | Folded into the second sweep; not separately measured. Same class as the above, and the above was immaterial |

Baseline for reading those deltas: write paths, which no fix touched, drifted
uniformly **1.01–1.07× slower** between sweeps. That is day-to-day machine
variation, and it is *larger* than the fresh-database "effect" — the strongest
available evidence that that confound was immaterial rather than merely small.

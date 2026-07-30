# ordering delta: original sweep vs repaired sweep

Required by `goal.md` criterion 12. The orderings, not the absolute times, are
what §7.5 calls the deliverable, and §7.6 feeds them into §8.1's writer tiers —
the codegen contract. So the question after repairing the harness is not "did
the numbers move" (they always do) but "did any *ordering* move, and does it
reach a tier".

Produced by `tools/orderings.py`, which reproduces `run_all.jl:155-160`'s rule.
Old data recovered from git (`HEAD:research/duckdb-driver-jl/raw/`).

> **READ THE LAST SECTION FIRST.** Three sweeps happened. The tallies in the
> body below describe the **second** (2 repeats per config) and are superseded
> by *six repeats at 64 threads* at the end of this file, which is authoritative
> — including for §7.5's numbers. The body is kept because the old-vs-new
> ordering comparison and the per-fix effect measurements were only possible
> against the 2-repeat data, and because the sequence of three sweeps is itself
> the record of how the harness was wrong twice.

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


---

# six repeats at 64 threads — 2026-07-30

The 2-repeat sweep left a question it could not answer: are the 64-thread
instabilities real noise, or an artefact of the harness repair? Re-swept with
**2 repeats at 1 thread and 6 at 64**, clearing `raw/` so provenance stays
coherent. Analysis by `tools/stability.py`, which reports the ordering
*distribution* per cell instead of a binary flag.

At n=6, a cell that were a true 50/50 tie would still look unanimous only 6.2%
of the time, so unanimity is now evidence rather than an artefact of small n.
At n=2 it carried no weight at all.

## writes: nothing moves, at all

```
24 cells · 24 unanimous · 0 dominant · 0 split · winner stable 24/24
```

Every write ordering is identical across all six 64-thread repeats. §8.1's
writer tier selection rests entirely on these, so **the codegen contract is
confirmed, not merely un-contradicted**. This is a materially stronger
statement than the old sweep could make.

## reads: the winner is stable in 23 of 24 cells

```
24 cells · 18 unanimous · 4 dominant · 2 split · winner stable 23/24
```

The separation that matters: §7.3's actual claim is that `stream_first` is
fastest. It wins **every run of every read cell except one**. The churn the
binary rule flagged as "did not reproduce" is almost entirely `materialized`
vs `streaming` trading 2nd and 3rd place — which §7.3 already tells readers to
ignore ("a wash for throughput… do not choose between them on throughput").

| Cell | Distribution | Winner |
|---|---|---|
| 64t · read · flat · 10k | **4 distinct orderings in 6 runs**; `streaming` 3/6, `stream_first` 3/6 | **moves** |
| 64t · read · rich · 10k | dominant 5/6 | `stream_first` all 6 |
| 64t · read · list · 10k | dominant 4/6 | `stream_first` all 6 |
| 64t · read · rich · 100k | dominant 4/6 | `stream_first` all 6 |
| 64t · read · struct · 10k | dominant 4/6 | `stream_first` all 6 |
| 1t · read · struct · 10k | split 1/2 — **only 2 repeats, uninformative** | `stream_first` both |

## the one genuine tie

`64t · read · flat · 10,000` produced **four different orderings in six runs**,
with `streaming` and `stream_first` each winning three. That is not a rare
excursion and not an artefact — it is a real tie, at the smallest table under
the thread count §7.4 already identifies as harmful ("the registered scan…
degrades sharply, worst at small scales").

So the question the extra repeats were run to settle is answered: **the
64-thread instability is real, it is concentrated at the 10k scale, and in
exactly one cell it reaches the winner.** The harness repair did not
manufacture it.

## what §7.5 should now say

Not "22 of 24 read orderings reproduced", which conflates two different
claims. Instead:

- writes: **24 of 24 orderings unanimous across 6 repeats**
- reads: **the fastest path is unanimous in 23 of 24 cells**; the full ordering
  is unanimous in 18, dominant in 4, and genuinely split in 2
- the single cell where the fastest path is not stable is
  `64t · read · flat · 10k`, a real tie between `streaming` and `stream_first`

## remaining resolution gap

**1-thread now has the weakest evidence in the sweep** — 2 repeats, against 6
at 64 threads — and it is the configuration §7.2 and §7.3 actually report. The
`1t · read · struct · 10k` split cannot be interpreted at n=2.

Raising it is cheaper than it looks: the 1-thread runs execute *concurrently*
(each uses one thread on a 64-core box), so more repeats cost little wall
clock. The caveat is memory-bandwidth contention — the harness comment claims
"no measurable contention" for two concurrent runs, which has not been
re-verified for four or six. Recorded as a decision, not assumed either way.

---

# six repeats at BOTH thread counts — 2026-07-30T13:57:13+12:00

**Read this section, not the ones above it.** Four sweeps are now recorded here.
This is the only one with n=6 at both thread counts, and it supersedes every
count in the earlier sections. `raw/` was cleared again, so provenance is
coherent: 12 runs, `results-t1-{a..f}` and `results-tauto-{a..f}`, all from
11:07–12:35 on 2026-07-30.

## the headline: no ordering moved, at all

`tools/orderings.py` against the **original pre-repair snapshot** (4 runs,
2026-07-28, preserved at `/home/pjc/.claude/jobs/3702f96b/tmp/raw-old`, and
recoverable via `git show 048cfc2^:research/duckdb-driver-jl/raw/<f>.json`):

```
cells compared:            48
orderings unchanged:       41
orderings MOVED:            0
unstable in old sweep:      2   (2 repeats per config — weak detection)
unstable in new sweep:      7
insufficient data:          0
```

**Zero orderings moved.** Both confound repairs changed every absolute time in
§7 and left every ranking intact.

> This supersedes the "two moved orderings" row in `mismatches.md` Part 2 and
> the `## the two moved orderings` section above. Those were measured against
> the *second-repair* sweep at n=2 per config; at n=6 they are not moves, they
> are cells whose repeats disagree. The distinction matters: a move means the
> document's ranking is wrong, whereas disagreement between repeats means the
> ranking is unstable. §8.1's writer tiers are untouched either way.

Corroborating evidence that this was a measurement fix and not a result change:
**every allocation count and every memory figure in §7 still verifies.** Allocs
and bytes are properties of what the code does; the confounds were about what
contended for the machine. Timing moved, work did not.

## writes: still perfectly rigid

24 of 24 cells unanimous, 0 dominant, 0 split, winner moves in 0 — now from an
independent set of 6 runs at each thread count. Winners: `flat`→`register`
(except `64t·10k`→`appender`), `list`→`literal`, `rich`→`appender`,
`struct`→`register_flat`. The one cross-config difference §7.5 reports
(`write · flat · 10k`) reproduces exactly.

## reads: the 1-thread question is answered

| | Jul 29 (6×64t, **2**×1t) | Jul 30 (6×64t, **6**×1t) |
|---|---|---|
| 24 cells | 18 unanimous · 4 dominant · 2 split | 17 unanimous · **6** dominant · **1** split |
| winner stable | 23/24 | **23/24** |

**`1t · read · struct · 10k` is unanimous at n=6** (`stream_first < streaming <
materialized`, 6/6). The split recorded above at n=2 was uninformative exactly
as suspected. That question is closed.

Two 1-thread instabilities that n=2 could not see did appear, both
`materialized` ↔ `streaming` with `stream_first` first in all 6 runs:

| Cell | Distribution |
|---|---|
| `1t · read · list · 100k` | dominant 5/6 |
| `1t · read · struct · 1M` | dominant 5/6 |

> `1t · read · struct · 1M` was labelled "unstable → **now stable**" in the
> `## instability: 2 → 4` section above. At n=6 it is dominant 5/6 again. That
> cell is genuinely marginal; it should not be given a stable/unstable label a
> third time. Report the distribution, not a verdict.

**So the claim "all instability is now at 64 threads" is false** — another
`mismatches.md` Part 2 row superseded. What *is* true, and is the stronger
statement: at 1 thread the fastest path is `stream_first` in **every run of
every cell**. The 1-thread config, which is what §7.2 and §7.3 report, has no
fastest-path instability whatsoever.

## the one genuine tie, independently reproduced

`64t · read · flat · 10k` now shows **five distinct orderings in six runs**:

| Winner | Runs |
|---|---|
| `streaming` | 3/6 (tauto-b, tauto-e, tauto-f) |
| `materialized` | 2/6 (tauto-c, tauto-d) |
| `stream_first` | 1/6 (tauto-a) |

Still the only cell in the entire sweep where the fastest path moves. A second
independent set of 6 runs reproducing it settles that it is a real tie at the
smallest table under the thread count §7.4 already identifies as harmful — not
an artefact of either repair.

## what §7.5 can and cannot say after this

The checker's `extract_stability` (`tools/numbers.py:377-414`) emits **only four
claims** — write total, write reproduced, read reproduced, read total — matched
off two fixed sentence forms:

```
**Writes: all N orderings reproduced
**Reads: N of M reproduced
```

`impl.md:155` states the checker also verifies "the two named non-reproducing
cells, and the one cross-config write ordering difference". **It does not.** The
claim-kind breakdown confirms it: `order 4`, which is exactly those four counts.
§7.5's tables are therefore hand-verified against `stability.py`, not
machine-verified, and `impl.md` should be corrected to say so.

Consequence for phase 4: the two count sentences must keep their exact shape or
the coverage count drops from 142. So the fastest-path-vs-full-ordering split
that `## what §7.5 should now say` above calls for is **additive prose plus new
checker coverage — phase 6's remit, not phase 4's**. Phase 4 renumbers
`22 → 17`, replaces the now-false 2-row flip table with the real 7, and drops
the "latency instability" note. It does not introduce an unchecked `23 of 24`.

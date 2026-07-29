---
created: 2026-07-30T11:11:03+12:00
title: repeat counts change what a benchmark can claim
tags: [benchmarking, verification, duckdb, mental-model]
source: /state save (via /ws pause)
---

## Repeat count determines which questions the data can answer

With 2 repeats, "the ordering did not reproduce" is the *only* statement
available, and it is nearly uninformative: a genuine 50/50 tie and a single
rare excursion look identical. The arithmetic is the reason — if a cell were a
true coin-toss between two orderings, the chance all n runs agree is
`2 * 0.5**(n-1)`: 100% at n=2, 12.5% at n=4, 3.1% at n=6.

So at n=2 unanimity carries *no* evidential weight, and only becomes evidence
as n grows. Going to 6 repeats turned "4 cells did not reproduce" into "18
unanimous, 4 dominant, 2 genuinely split", and identified exactly one cell
(`64t read flat 10k`, four distinct orderings in six runs) as a real tie rather
than noise.

Report the distribution, not a binary flag, whenever more than two repeats
exist — and print how much weight unanimity carries at that n, so a reader
cannot over-read a small sample.

## Separate "the winner is stable" from "the ordering is stable"

A ranking benchmark usually makes one claim that matters — here, §7.3's claim
that `stream_first` is fastest — while the full ordering carries claims the
document explicitly disclaims (§7.3 says materialized vs streaming is "a wash
for throughput… do not choose between them on throughput").

Collapsing both into one stability flag understates reliability badly. Measured
across 6 repeats: the *fastest path* was unanimous in 23 of 24 read cells,
while the *full ordering* was unanimous in only 18. Reporting "18 of 24
reproduced" would have implied the document's actual claim was shakier than it
is, and reporting "23 of 24" alone would have hidden real churn.

Report both, and say which one the document's claims depend on.

## Concurrency width is a measured property, not a free parameter

The harness ran two 1-thread benchmark processes concurrently on a 64-core box
with a comment asserting "no measurable contention". Scaling to six repeats
tempted the obvious move — run all six at once, since 64 cores are idle.

But the contended resource is memory bandwidth, not cores, and idle cores do
not help. Worse, it would not contend *evenly*: `materialized` builds a whole
DataFrame while `stream_first` touches one chunk, so bandwidth pressure would
land differently on the two paths being compared — distorting the exact
comparison the benchmark exists to make.

The verified claim covered two. So six repeats run as three sequential batches
of two, and the width is an explicit `PARALLEL_1T` knob documented as
requiring a measurement before it is raised. ~20 minutes of wall clock to avoid
assuming something that was never tested.

Generalisation: when a comment says a resource is uncontended, check what N it
was established for before scaling N.

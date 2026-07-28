---
created: 2026-07-29T08:59:04+12:00
title: a partial fix to a benchmark is worse than none
tags: [benchmarking, verification, duckdb, julia, adversarial-review, gotcha]
source: /ws done
---

## A partial fix to a ranked benchmark is worse than no fix

Three read modes (`materialized`, `streaming`, `stream_first`) were all
abandoning their DuckDB `QueryResult`s to finalizers, so thousands of handles
piled up per cell and their GC landed inside later timing windows. I fixed
`read_first_chunk` only. That made `stream_first` pay a deterministic
`duckdb_destroy_result` inside its timed region while the other two kept
leaking into whichever window ran next.

The deliverable is the *ordering* of the three modes. A bias all three share
largely cancels in a ranking; a bias one carries alone does not. So the
half-fix converted a uniform error into a differential one and made the
comparison less trustworthy than before I touched it.

Evidence it was my artifact: the asymmetric sweep reported instability rising
2 → 3. After fixing all three symmetrically, the honest figure is 4 — and the
distribution changed meaningfully: the single 1-thread instability *became
stable*, while three new ones appeared, all at 64 threads. That is the
signature of removing finalizer noise at low thread counts, not of adding
noise.

**Rule:** when the output is a comparison, never fix one arm. Either fix every
arm or leave the shared bias in place and disclose it.

## Verify a transcription before assuming it is the problem

The session existed to reconcile `reference.md` §7 against `raw/*.json`,
on the premise that hand-transcribed numbers never machine-checked were
probably wrong somewhere. They were not: **142 of 142 claims verified, zero
failures**, with every claim confirmed genuinely compared by mutation testing.

The real defect was one level up — the numbers were a faithful transcription
of a measurement taken under two undisclosed confounds. Auditing the copy
would never have found that; it took a code review of the *harness*.

Cheap check first: prove or disprove the stated premise mechanically before
building on it. A clean result reframes the work rather than ending it.

## Coverage totals need a breakdown, and mutation testing cannot see vacuous checks

`bench.py` reported "648 values compared". 24 of those were `None` vs `None` —
`stream_first` has no `rows_per_sec`, so the document renders `—` against a
missing JSON field. The comparison agrees, truthfully, and verifies nothing.

Mutation testing cannot catch this class: there is no value to perturb, so no
perturbation can force a failure. The only defence is structural — report
`real / both-absent / status` separately and never a single total. Same bug
was later found in `numbers.py`, which had inherited the pattern rather than
the fix.

## The same vacuous-agreement bug, three times in one session

`all(o == seen[0] for o in seen)` is vacuously true for a one-element list.
This appeared in `run_all.jl`'s stability table (a single-run thread group
printed "all orderings reproduced" having compared nothing), and then again in
`orderings.py`, a tool written *in the same session that had just fixed it*.

Whenever "do these agree?" is asked of a collection, the count-guard is part
of the question. A shared helper would have been better than three
independent implementations of the same rule.

## Reviews can be right about the defect and wrong about the fix

A review correctly found that `anchors.py` computed `one_only` — links
resolving under exactly one anchor convention — printed it as a bare count,
listed nothing, and gated nothing, contradicting its own docstring. The
implied fix was to make it fatal.

That would have failed a correct document. Every heading in `reference.md` is
numbered, so `### 3.4 Streaming reads` slugs to `34-streaming-reads` under
GitHub's dot-stripping and `3.4-streaming-reads` under the dot-preserving
convention. A link can only be spelled one way: for numbered headings the two
conventions are *mutually exclusive*, and 44 of 46 links were correctly in
that state.

The useful distinction was direction, not count — resolving under
dot-preserving *only* is broken on GitHub and worth failing on; the reverse is
simply correct. Verify a finding's premise, not just its observation.

## Unicode homoglyphs make a checker report clean while checking nothing

`results.md` writes microseconds with U+03BC (Greek mu, what
`BenchmarkTools.prettytime` emits); `reference.md` uses U+00B5 (micro sign,
what a human types). They render identically and compare unequal.

The danger is not a false failure — it is a false *pass*. A checker scanning
for `μs` finds zero microsecond claims in `reference.md`, verifies nothing,
and reports a plausible-looking coverage count. Any parser spanning
machine-generated and hand-written text must accept both spellings, and the
coverage number must be broken down far enough that "zero claims of this kind"
is visible rather than absorbed.

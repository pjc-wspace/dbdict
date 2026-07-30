---
created: 2026-07-30T17:15:19+12:00
title: coverage-delta and mutation catch different tool bugs
tags: [verification, benchmarking, testing, gotcha, reproducibility]
source: /ws done
---

## clear-and-resweep, and why 1-thread repeats batch in pairs

The sweep clearing `raw/` before writing is why the deletions show in
`git status` as a scary-looking wall of `D` lines — that's the
**clear-and-resweep** decision from phase 2, chosen deliberately over appending
repeats, because mixed provenance in `raw/` is precisely what the new
mtime-spread guard flags as dangerous. The cost is a window where the repo has
no ground truth at all; git is the backstop
(`git show 048cfc2^:…`).

The 1-thread batching (2 at a time, not 6) is the other non-obvious constraint:
the harness comment's "no measurable contention" claim was only ever established
for two concurrent 1-thread runs, and `materialized` builds a DataFrame while
`stream_first` pulls one chunk — they wouldn't contend evenly. Raising the cap
needs a measurement, not an assumption, so 6 repeats cost 3 sequential batches.

## a confound can move every number and no ranking

The `0 orderings MOVED` line is the result that retroactively justifies the whole
phase-2 detour. The confounds were real — reads ran against 1M-row leftovers, and
`stream_first` was measuring finalizer backlog — so the *numbers* were describing
the wrong experiment. But rankings are ratio-invariant to a confound that hits
all three read paths roughly proportionally. That's why §7's conclusions held
while its figures didn't, and it's the cleanest possible argument that the repair
was a measurement fix rather than a result change.

The `both-absent: 24` bucket in `bench.py`'s output is the other quiet win.
That's the vacuous-agreement class mutation testing provably *cannot* catch — a
check where neither side has a value and the comparison trivially passes.
Splitting it out of the coverage count is what makes "576 real comparisons" mean
something; the two audit tools that burned the previous session both inflated
coverage exactly this way.

Corroborating signal, discovered while transcribing: **every allocation count and
memory figure still verified** while 91 timing claims failed. Allocs and bytes are
properties of what the code does; the confounds were about what contended for the
machine. When a repair changes timing but not work, that split is the signature to
look for.

## a checker that finds restatements by value has no blind spot

This is phase 3 paying for itself. A hand-audit of the `3.4×` correction would
very plausibly have fixed §1, §7.2, and §8.1 — the three places anyone would
think to look — and missed the Driver study appendix, reproducing the exact
defect class that burned the last two sessions. The checker finds restatements by
*value*, so it has no blind spot where the author's mental model does.

Note also what the 91-vs-51 split tells you about tolerance design: comparing
numerically within last-displayed-digit tolerance means a claim fails only when
the *displayed* value would change. That's why `1.653` passes as `1.7` while
`3.58` fails as `3.4` — the tolerance is doing real work separating "the document
is now wrong" from "the underlying value drifted a hair." A stricter equality
check would have produced 142 failures and told you nothing.

## mutation testing cannot catch a claim that disappeared

A checker that locates claims by searching for the **literal claimed value**
stops finding a claim the moment you correct it. `numbers.py` had
`(r"\*\*3\.4×\*\*|3\.4×", speedup, ...)`. Correcting the document to `3.6×`
didn't re-check the claim — it deleted it from coverage:

```
claims verified: 137        ← was 142
  derived  11               ← was 16
claims failed:   0
OK — every parsed claim agrees with raw/*.json
```

A clean pass, five claims silently unchecked, including the most-restated number
in the document and the one the tier rationale rests on.

This is a genuinely different failure mode from the one mutation testing was
built to defeat, and **`--selftest` cannot catch it by construction**. Mutation
perturbs claims the checker *found* and asserts the comparison fails. It has
nothing to say about claims that vanished from the search — there is no claim
left to perturb. Every signal the tool emits says "clean."

What caught it was a verify criterion written during planning, before anyone knew
the bug existed: *"coverage count unchanged from phase 2 — a drop means claims
went missing rather than getting fixed."*

**The transferable rule:** a verification tool needs two orthogonal guards, each
blind to what the other sees.

| Guard | Catches |
|---|---|
| mutation / perturbation | a claim parsed and counted but never *compared* |
| coverage-count delta | a claim that stopped being *found* |

Neither alone is sufficient. Any audit tool whose patterns embed the expected
value has this bug latent in it, and it surfaces exactly when the tool is doing
its job — at the moment of correction. Prefer patterns that match the value slot
generically and identify the claim by surrounding context.

---
created: 2026-07-31T06:51:38+12:00
title: notation should be as precise as the measurement
tags: [documentation, verification, benchmarking, testing, pattern]
source: /ws done
---

## braces for what the data does not order

This was the design decision the whole phase turned on. The obvious ranking line
— `stream_first < streaming < materialized` — is what the collapsed table appears
to show, and it would have been **false**: six of the seven unstable read cells
are exactly `materialized` and `streaming` trading places. A summary that
asserted a three-way order would have manufactured a claim the data contradicts,
in a section written to make the data clearer. Braces
(`stream_first < {materialized, streaming}`) let the prose be exactly as precise
as the measurement.

**Generalisation:** when summarising a ranking, the notation needs a way to say
"these are not ordered". Without one, every summary is pushed into overclaiming
by the shape of its own syntax — a total order is the only thing `a < b < c` can
express. The collapsed/reported view will always *look* totally ordered, because
collapsing picked one repeat; the instability lives in the repeats you dropped.

## make the claimed value a string, then test the half mutation cannot reach

Each ranking row asserts *two* things — that the named paths are exactly the ok
paths measured, and that the strict order holds in every repeat. The
set-equality half is what stops a row quietly omitting a measured path, and it is
also what makes the claim mutation-testable for free: `mutate()` appends
`_mutated` to strings, producing a path name that was never measured. Making the
claimed value the ordering **string** rather than a parsed structure meant zero
changes to the mutation machinery.

But string mutation only exercises set-equality — it cannot reach the ordering
comparison. So I ran three separate negative tests on scratch copies:

| Test | What it isolates |
|---|---|
| permute an ordering (`register < appender` → `appender < register`) | the strict-order check, with the set held identical |
| invert a braced group (`a < {b, c}` → `{b, c} < a`) | brace-group semantics |
| omit a measured path from a row | the set-equality check |

Each failed on exactly one claim, the right one, with a diagnostic naming the run
and scale. Without the permutation test the ordering half of every ranking claim
could have been dead code reporting clean — the same
parsed-but-never-compared failure this project already hit once.

**The rule:** when a claim asserts multiple properties, check that your automated
mutation actually reaches each one. A generic mutator perturbs the value in *one*
way; properties it cannot disturb are unverified no matter how green the selftest
looks. Enumerate the properties, then write one targeted negative test per
property that mutation cannot reach.

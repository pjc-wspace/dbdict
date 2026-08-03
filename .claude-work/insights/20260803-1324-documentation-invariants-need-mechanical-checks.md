---
created: 2026-08-03T13:24:42+12:00
title: documentation invariants need mechanical checks
tags: [documentation, verification, spec-design, sourcing, gotcha]
source: /ws done
---

## impl.md carrying both the plan and the record is what makes resumption cheap

The impl.md here is doing double duty as plan *and* record — the `- also:`
entries under phases 1 and 2 are what makes resumption cheap. Reading it tells
you not just what was planned but what the plan got wrong (e.g. the `min()`
reducer that would have declared HOLDS on the strength of the most compressible
column alone).

## "no claim lives in two files" only holds if it is mechanically checked

Phase 3's verify block includes a check most doc edits skip: *no sentence
appears in both `README.md` and the direction document*. That's the "no claim
lives in two files" invariant made mechanical — it's what stops a repositioning
from creating a second source of truth that drifts.

## a repositioning must be true twice — of the code and of the scope

Phase 3's hard constraint isn't the rewrite, it's the *conjunction*: every claim
must be true of the repo **and** of V1's scope. Those pull opposite ways —
`dummy` ships today but is out of V1. The only way to satisfy both is to make
tense and scope explicit per claim ("ships today; not in 0.3.0"), rather than
choosing one timeline and quietly lying about the other.

"No claim lives in two files" is why the README gets *pointers plus status*, not
a summary of the type vocabulary. A summary is a copy that drifts; a link can't.

## link anchors are an external claim that fails silently

I dropped the `#anchor` fragments I'd first written into the direction-doc
links. GitHub's heading→anchor slugification is a claim about an external tool
I'd have been asserting from memory, and a wrong slug fails *silently* — the
link still works, it just lands at the top of the page. Section numbers in the
link text (`[§10](…)`) carry the same information and are verifiable by grep
against the target file.

## a doc invariant check needs the right exclusions, and a poison test

The "no shared sentence" check strips fenced code and table rows before
comparing. Without that it would flag the CLI `Usage:` block or a shared matrix
row as a duplicated claim — but those aren't claims in two files, they're the
same *data* quoted in two places. Getting the exclusion right is what keeps the
check from being noise you learn to ignore.

The check was poison-tested before being believed: pasting one sentence from the
direction document into a copy of the README made it fail, and it matched across
the two files' different line-wrapping. This is the same discipline as
[20260803-0925-verify-scripts-encode-assumptions] — a verify function that
passes tells you nothing until you have seen it fail for the right reason.

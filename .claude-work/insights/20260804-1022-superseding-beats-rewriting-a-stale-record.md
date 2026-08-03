---
created: 2026-08-04T10:22:34+12:00
title: superseding beats rewriting a stale record
tags: [documentation, workflow, ws-mid-session, verification, gotcha]
source: /ws done
---

## a held session is a contract plus a plan — check whether either survives

A held session is a *contract plus a plan*. When the contract's premises are
gone and `/ws plan` rebuilds the plan on resume anyway, what's actually being
held is an empty container — the value has already migrated to durable artifacts
(`spike/`, `research/duckdb-driver-jl/`, `review-decisions.md`), all committed
and reachable without the session.

## rewriting a historical record is a category change

Rewriting a held session's `goal.md` mutates a historical record into a
forward-looking one. That's a category change, and it's why the plan felt like
it needed the byte-identical preservation step — the preservation is a hint that
the operation is fighting the artifact's nature.

The decisive argument came from the maintainer: *"even my goals were wrong."* A
rewrite would have laundered a mistaken design into a fresh-looking document and
destroyed the evidence it was tried. Staleness invites amendment; **wrongness
invites supersession**, because the record of the error is itself the value.

Supporting finding worth keeping: the staleness was in three layers (decided
review findings never batch-edited in, five findings never decided, then the V1
re-baseline), and a rewrite addressed only the newest — producing a fourth
document state matching none of the three existing records. When a document is
stale against more than one authority, "bring it up to date" is under-specified.

## diff against history beats copy-then-compare

`git diff --numstat` against the pre-edit blob is a better byte-identity check
than "copy the file first, then verify against the copy". A copy proves the copy
matches; the diff proves *the file in history* is unchanged — and it needs no
second file to exist, which is why the awkward `goal-v0.2.0.md` preservation
copy (and its misleading name) simply evaporated once the check changed.

`40 insertions, 0 deletions` is the whole proof that a banner was added and
nothing was edited.

## a supersession banner should name what died, not just that something did

The banner deliberately names *which* premises died and why — the companion
mapping file, the compound types, the single-driver assumption — not just
"superseded". A bare supersession marker tells a future reader to ignore the
document; a specific one tells them which parts were wrong, which leaves the
adversarial-review ledger and the capability spike still usable. Supersession
isn't deletion if you say what failed.

Same reasoning as [20260803-1324-documentation-invariants-need-mechanical-checks]:
the useful artifact is the one that says what it is and what it is not.

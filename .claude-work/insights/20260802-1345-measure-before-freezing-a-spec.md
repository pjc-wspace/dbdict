---
created: 2026-08-02T13:45:05+12:00
title: measure before freezing a spec
tags: [verification, spec-design, workflow, benchmarking, sourcing]
source: /ws done
---

## supersede chains and settled-vs-reopenable

- This state directory uses an explicit **supersede chain** — the 11:03 file
  names the 10:47 file it replaces and says why (SHAs weren't known yet during
  the close). That's cheaper than deleting: the earlier file stays valid as a
  record of what was known *at that moment*, which matters when you're auditing
  why a decision was made.
- The checkpoint separates **settled** from **open-but-could-reopen**.
  `hdf5-temporal-compression` is flagged not as leftover work but as the one
  unrun probe with authority to invalidate a frozen decision — a useful
  distinction to carry into any spec freeze.

## hold vs close preserve different things

- Phase 5 of the closed v0.3.0 session is literally **"held codegen goal
  rewrite"** — i.e. rewriting the `goal.md` of the held Julia session. The
  type-system redesign changed the premises that goal was written under, so
  resuming the held session *first* means editing a document that phase 5
  intends to rewrite anyway.
- `hold` vs `close` is doing real work: `hold` preserves an open workflow
  position (`__on-hold__.md` + archive on resume), while `close` writes
  `summary.md` and discards the position. That's why the incomplete-but-closed
  session needs a fresh `/ws new`, and the incomplete-but-held one doesn't.

## which document absorbs a surprise

- The probe-first ordering isn't just context hygiene — it's about **which
  document absorbs a surprise**. If the probe shows compression *doesn't* close
  the gap, the decisions note gets an amendment (cheap, internal, already
  versioned). If the same surprise lands after the direction doc is written,
  you're amending a public-facing positioning document.
- Note the asymmetry in verify blocks: some verify with `diff` and
  `git rev-parse` (mechanical, binary), while others are `grep` for headings
  plus "every external claim has a link or an `Inferred:` marker". The second
  kind can't be fully automated — a reason to want the phase small enough that
  a human can actually read the output at the boundary.

## a spec that exempts itself from its own evidence rule

- The hedge was the interesting failure. `goal-draft.md` sets an evidence
  standard in its own constraints section — every external claim cited or
  marked `Inferred:` — and then two sections later said "presumably". A spec
  that exempts itself from its own rule is the cheapest place for a wrong
  assumption to survive, because nobody re-reads the goal doc once
  implementation starts. The grep took ten seconds and changed the claim from a
  guess into a number that now constrains two later phases.
- What the scope line is really doing: it's not saying the doc/code divergence
  doesn't matter, it's choosing *which artifact absorbs it*. Documenting a debt
  in a roadmap is a different commitment from fixing it, and being explicit
  about that beats a scope line that silently implies the problem doesn't
  exist.

## pre-register the failure branch

- Writing the falsification test *before* measuring is what makes a probe worth
  running. "Does compression help?" always answers yes. "Do compressed lexical
  temporals land under 8 bytes/row — the raw size of the encoding we rejected?"
  can answer no, and the plan says in advance what happens if it does. A probe
  with no pre-registered failure branch tends to produce a number that gets
  narrated as supporting whatever was already decided.
- The ordering constraint does load-bearing work in the plan, not just the
  goal: phase 2's verify says the HDF5 figures must match *phase 1's note*.
  That's what converts "measure first" from a good intention into something a
  verify step can actually catch.

## no claim lives in two files — applied to planning artifacts

- Worth noticing what the goal doc *doesn't* do: it never restates the type
  system. It names the decisions note as the authority and points at it. That's
  the same "no claim lives in two files" rule the session imposes on
  `README.md` and `CLAUDE.md` — applied to its own planning artifacts.
  Duplicating the 10 types into `goal.md` would have created a third copy to
  keep in sync across a five-phase session.
- The five phases are ordered by *what absorbs a surprise*, not by size or
  convenience. Both orderings are written into the constraints section as
  fixed, so a future reader knows they're load-bearing rather than incidental.

## available ≠ applicable, and the reducer is the test design

- `filter_avail()` answering **True** for szip while `H5Dcreate` rejects the
  same dtype is the general shape of a capability-detection trap: the API tells
  you a feature is *present*, not that it is *applicable to your data*. Any
  capability matrix built by asking "is X available?" will overstate support.
  The only reliable probe is to attempt the real operation on the real type.
  (HDF5 documents this precisely: the szip/datatype conflict *"can only be
  detected when the property list is used"*.)
- The first verdict function took `min()` across all lexical encodings and
  reported "claim HOLDS" — true, but driven entirely by `date` (S10), the most
  compressible column. Aggregate-best is the wrong reducer for a claim that
  must hold for *every* case; the binding constraint was `timestamp`, 370×
  worse. When a test summarises many cells into one verdict, **the reducer
  choice is the test design**.

## the baseline you compare against decides the answer

- The original `Inferred:` claim compared *compressed* lexical against *raw*
  `int64` — 8 bytes/row. Measured against **compressed** `int64`, lexical costs
  1.14–1.27× the disk rather than beating it. Both framings are arithmetically
  correct; only one is a fair test. When a claim is of the form "X is cheaper
  than Y", check whether Y was given the same optimisations X was.
- And the cost turned out not to be where anyone was looking: disk was
  1.14–1.27×, but **read time was 6.6–15.8×**. The decisions note had asked for
  read throughput almost as an afterthought, and that is where the real answer
  lived.

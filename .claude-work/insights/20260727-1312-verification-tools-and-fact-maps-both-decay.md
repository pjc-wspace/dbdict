---
created: 2026-07-27T13:12:25+12:00
title: verification tools and fact maps both decay
tags: [verification, documentation, refactor, gotcha, testing]
source: /ws done
---

## a verification tool that inflates its own valid-set can only hide failures

My anchor checker parsed every line matching `^#{1,6}\s+` as a markdown heading —
including `# WRONG — the appender's blob method throws...` inside julia code fences.
It reported 101 headings in a document that has 56. Every julia comment was being
added to the set of anchors a link could legitimately resolve to.

Note the direction of the error. Inflating the valid-set cannot cause a false
*failure* — it can only cause a false *pass*, by letting a genuinely broken link
match a comment-derived slug. For a tool whose entire job is to fail when something
is wrong, that is the worse direction, and it is the silent one: the check had been
reporting "0 unresolved" all along and looked healthy.

**How it surfaced:** I deleted two comment lines from a code block, and the heading
count dropped from 101 to 99. Deleting comments cannot change a heading count. A
number that moves when it has no business moving is worth chasing even when the
headline result looks fine — especially then, because a passing check gives you no
other reason to look at it.

General form: for any checker, ask which direction its bugs fail in. A checker biased
toward false alarms is annoying and self-announcing. A checker biased toward false
passes is quiet, and you will trust it right up until it matters.

## a fact map decays before the next phase reads it

Phase 1 built a per-fact map of every mention site and the action to take on each.
Executing it two phases later, **three of the nine entries were wrong** — the flagged
"duplication" was a different fact, or a site that already conformed, or content the
map's pattern had simply missed.

Two independent causes, both structural:

- **Earlier phases move the ground.** The map was built before a phase that
  deliberately relocated content. Any map not rebuilt after that is describing a
  document that no longer exists.
- **Broad patterns conflate facts that share vocabulary.** "finalizer" appears in
  both a GC-leak fact and an unrelated segfault hypothesis; a pattern matching it
  reports one fact's canonical home as the other's duplicate. Conversely `empty vec`
  missed "empty *Julia* vector" and reported a section as having lost its own content.

Rebuilding the map cost one script run. Acting on the stale one would have deleted a
hypothesis section, "fixed" a section that was already correct, and left a real
duplicate in place. **Treat a fact map as a cache with no invalidation, and rebuild
it at the start of the phase that consumes it** — not at the end of the phase that
produced it.

## a summary table loses per-column constraints when it compresses a matrix

Found in the driver reference: a capability matrix correctly records that prepared
bind cannot write DECIMAL or UUID. A downstream "tier selection" table compresses
that matrix into a per-table rule — *use prepared bind when the table has a BLOB
column* — and in compressing it, drops the constraint that **every other column must
also clear that tier's ceiling**. A BLOB+DECIMAL table selects a tier that cannot
write it.

This is the second instance of the same defect class in two sessions on the same
document, which is what makes it worth recording. The shape:

> A per-*entity* rule derived from per-*attribute* capabilities must be a conjunction
> across all attributes. Deriving it from the attribute that triggered the rule is
> the bug, and it reads as correct because the triggering attribute genuinely is
> handled.

Applies well beyond docs — dispatch tables, capability negotiation, feature gating,
schema-driven codegen. Wherever a summary exists to spare the reader the matrix, the
summary must encode the matrix's quantifier, not just its headline.

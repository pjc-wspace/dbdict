---
created: 2026-07-27T12:14:15+12:00
title: choose the comparison unit before trusting the score
tags: [verification, documentation, refactor, gap-analysis, testing]
source: /ws done
---

## a similarity score is only as meaningful as its unit of comparison

Deduplicating two documents, I compared them claim-by-claim at **line** level and
got 113 "unique" lines — apparently a third of the source with no counterpart.
Nearly all were false. The two files state identical facts with different sentence
breaks, so a true duplicate scores as unique purely because no single line pairs up.
The metric was measuring **line wrapping**, not content, and it looked like a
result.

What worked was comparing **distinctive tokens**: `file.jl:NNN` citations,
backticked identifiers, verbatim error strings, measured numbers. Those survive
rewrapping and rewording, so "does this anchor appear anywhere in the other
document" answers the actual question. 256 tokens, 39 genuinely absent, and the
absences were reviewable by hand in minutes.

**Why:** prose similarity is a proxy. When two documents are related by *rewriting*
rather than copying, the proxy fails in the exact case you care about. Pick the
invariant that survives the transformation you expect — here, rewording — and
measure that instead.

**How to apply:** before trusting any similarity/diff metric, ask what
transformation the two artifacts have undergone relative to each other, and whether
the metric is invariant to it. Sanity-check the metric against a case you already
know the answer to: one glance at a "unique" line whose content I knew was in the
target would have caught this immediately, and did.

The token approach needed a fix of its own for the same class of reason — a token
wrapped across a line break in the target read as absent, until whitespace was
collapsed on both sides before the substring check.

## an inventory used as a safety net must favour recall

The extractor that builds the claim inventory initially counted a paragraph line
only when it carried bold emphasis, on the theory that connective prose would flood
the output. That heuristic silently dropped **459 claims** — including two real
findings stated in plain prose.

The asymmetry is the point: an inventory whose job is to prove *nothing was lost*
has a fatal failure mode (a claim it never saw, which nothing then protects) and a
trivial one (noise you filter by `kind` at review time). Those are not comparable
costs, so the default must be to capture everything and filter later.

**Why:** the value of a safety net is bounded by its worst hole, not its average
density. Precision improves the reviewing experience; recall determines whether the
guarantee is real at all.

**How to apply:** whenever a tool exists to prove a negative — nothing lost, nothing
missed, nothing regressed — bias every judgement call toward over-collection, and
verify coverage explicitly (every section accounted for) rather than assuming the
extractor saw what you'd have seen.

## a process constraint pays for itself once, and once is enough

The plan required that content existing *only* in the file being reduced must move
to the surviving file **before** any cutting. That looked like ceremony when
written. On the first phase that could test it, it caught a six-row evidence table
that my own earlier rewrite had already silently dropped — asserting a conclusion
("adding digits does not help") whose supporting evidence no longer existed
anywhere in the surviving document.

**Why:** deletion is the one operation with no cheap undo in a review workflow.
Ordering constraints around it are not pedantry; they are the only thing standing
between "reworded" and "lost".

**How to apply:** in any consolidation, never let the last copy of a fact be the one
you are deleting. Prove the destination has it first, mechanically. See
[[adversarial-review-with-execution-rights]] — same lesson, different surface: the
verification has to be executed, not intended.

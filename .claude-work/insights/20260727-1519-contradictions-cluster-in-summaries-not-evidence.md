---
created: 2026-07-27T15:19:52+12:00
title: contradictions cluster in summaries, not evidence
tags: [verification, documentation, testing, gotcha, sourcing]
source: /ws done
---

## every contradiction was in a summary; none were in the evidence

A consistency sweep over a 1600-line technical reference found five contradictions.
All five were in **summary constructs**. None were in the sections holding the
measurements and citations.

- an executive summary claiming "no single path covers the type matrix" and, in the
  very next clause, "only literal SQL covers everything"
- a tier-selection table whose precondition tested one column where the capability
  matrix it summarizes is per-column
- a capability claim that dropped a qualifier: "the only working path" for what the
  matrix records as the only working **bulk** path
- a guard count stated as four where the referenced list has six
- a nine-item list labelled "**The** never-emit list" where the authority has sixteen

The pattern is not carelessness in the summaries. It is that **compression is lossy
in a way that stays fluent**. Drop a quantifier, a qualifier, or a count and you do
not get a garbled sentence — you get a shorter, more confident, more readable one.
Every one of these read better than the correct version. The evidence sections are
verbose, hedged and full of citations, and that verbosity is what keeps them honest.

Practical consequence: when auditing a document, **weight the summaries**. The
executive summary, the decision table, the quick-reference card, the "rules" list —
these are simultaneously the most-read parts, the most likely to be wrong, and the
least likely to look wrong. The detailed sections mostly take care of themselves.

Mechanically: grep the absolutes (`never`, `every`, `always`, `only`, `all`, `no`)
outside code fences and check each against the source table. Three of the five turned
up that way. Careful reading had already missed them across a full rewrite and an
adversarial review.

## resolving a citation converts a claim into something you can see

The document cited `value.jl:51` for "non-ASCII strings in lists are truncated" and
`statement.jl:65` for "scalar string bind is correct". Resolving both against the
installed source:

```
value.jl:51      create_value(...) = Value(duckdb_create_varchar_length(val, length(val)))
statement.jl:65  duckdb_bind_varchar_length(stmt.handle, i, val, ncodeunits(val));
```

`length` counts characters; `ncodeunits` counts bytes. The documented bug *is* that
contrast, and one command made it visible rather than merely asserted.

Worth building the resolver even for a one-off audit: 160 citations resolved in
under a second, and printing each cited line makes spot-checking the load-bearing
ones cheap. Citations rot silently — a package upgrade shifts line numbers and every
one of them still *looks* authoritative. A citation nobody can cheaply re-resolve is
decoration.

## a snippet that reads as runnable but is not is a defect in executable docs

One code block was introduced as "reproduced in full so this section stands alone".
It did not run: it quoted two other blocks and omitted their imports and setup.

Nothing false was claimed — the block had no documented output, so no promise about
its behaviour was broken. But a reader copying it gets an error, and an audit that
executes every block cannot tell it apart from a genuine failure.

The fix is not to make every snippet standalone; excerpts are legitimate and often
clearer. The fix is to **mark them**, in-band, naming what they assume. That serves
the reader and the harness at once — mine now skips blocks whose first line says
`# fragment` and reports them as skipped rather than passing or failing them
silently. An exception that is invisible to your tooling gets rediscovered every
audit.

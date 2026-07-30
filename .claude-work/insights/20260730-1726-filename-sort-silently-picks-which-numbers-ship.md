---
created: 2026-07-30T17:26:49+12:00
title: filename sort silently picks which numbers ship
tags: [documentation, benchmarking, reproducibility, gotcha]
source: /ws done
---

## disclosing the same fact twice without duplicating prose

The `vruns.py` gate is doing something subtle here and it's worth naming. I added
a disclosure of the *same fact* to two files, which is exactly how duplicated
prose gets into a document set — and `vruns.py` exists to catch verbatim overlap
between `reference.md` and `results.md`. It still reports 0 shared runs ≥120
chars because the two versions are written for different readers: the generated
one names `raw/*.json` and the tag sort, the document one talks about §7.2–§7.4
and run-to-run spread. That's why `impl.md` specified "phrased for a reader who
will never open `run_all.jl`" rather than "same sentence in both places" — the
constraint was load-bearing, not stylistic.

The other thing worth recording: `a` sorting first is a naming coincidence
carrying real weight. Rename the tags to `1`/`2`/… or `alpha`/`beta`/… and every
absolute figure in `results.md` changes with no measurement changing at all.
That's the kind of dependency that's invisible until someone reorganises file
naming for unrelated reasons, which is precisely why it now says so in the
generated output rather than only in a comment.

**Generalisation:** when a pipeline collapses N inputs to one reported value, the
selection rule is part of the result and belongs in the output, not just in the
code. "First by filename" is the most common such rule and the least likely to be
documented, because it never looks like a decision — it falls out of
`sort(readdir(...))`. Interpolating the input count into the disclosure
(`over the $(length(runs)) runs merged here`) keeps the statement true when the
sweep size changes, instead of decaying into a stale hardcoded number.

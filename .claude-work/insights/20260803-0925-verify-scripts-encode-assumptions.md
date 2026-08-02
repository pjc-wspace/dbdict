---
created: 2026-08-03T09:25:23+12:00
title: verify scripts encode assumptions
tags: [verification, workflow, gotcha, documentation, sourcing]
source: /ws done
---

## a verify that cries wolf gets skimmed

- The mechanical "unsourced quote" check flagged **8 lines; 7 were false
  positives**, caused by a ±2-line context window — citations usually sit at
  the top of a paragraph, several lines above the quote they license. Widening
  to ±5 left exactly one real defect (an unsourced PostgreSQL quote about
  `timestamp with time zone` storage).
- A verify that cries wolf gets skimmed, and a skimmed verify is worse than
  none. The useful framing for this class of check is that it produces a
  **triage list for reading**, not a verdict. That matches how the phase was
  sized in the first place — small enough that a human can actually read the
  output at the boundary.

## a verify script reports on its own assumptions

- The criterion-7 check "does the dangling link resolve" initially reported
  **failure** — because the extractor assumed markdown `[](…)` syntax, while
  the archive note actually references the path in backticks
  (`` `docs/vision-direction-0.3.0.md` ``). The reference was correct all
  along; the check was wrong about what it was looking at.
- Generalisation: **a verify script encodes assumptions about the artifact it
  checks.** When those assumptions are wrong it reports on itself rather than
  on the artifact — and it can fail in either direction. A false *failure*
  wastes time; a false *pass* is the dangerous one, because nothing prompts you
  to look again.
- Practical consequence: when a mechanical check fails, the first question is
  "is the artifact wrong, or is the check wrong?" — not "how do I fix the
  artifact?"

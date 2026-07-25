---
name: no-unprompted-next-step-nudges
description: "Don't end responses with \"X next?\" prompts — user directs the pace; only suggest next steps when asked"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 589d0a7b-b11a-490d-8ff9-0ccbb3a989a3
  modified: 2026-07-24T23:14:19.574Z
---

Do not end responses with unprompted next-step nudges ("Finding 8 next?",
"Shall we move on to X?", "Ready for Y?"). The user called this "too
pushy" (2026-07-25, during the julia-codegen plan review).

**Why:** the user directs the working rhythm — especially in
discuss-and-decide sessions where they deliberately take items one at a
time, reorder, and interject questions. Repeated "next?" prompts pressure
the pace and crowd their steering.

**How to apply:** answer what was asked and stop. This includes ALL
trailing variants: "X next?", "shall we...", "if you want, I can...",
"want me to...". End on the substance of the answer — no closing offer,
suggestion, or question of any kind unless the content genuinely
requires a decision from the user to proceed. Provide "what's next"
guidance only when the user asks (e.g. "what's next", "where were we",
`/ws status`). Workflow-mandated boundary asks (e.g. /ws done requires
asking permission) are the exception and still apply.

Reinforced 2026-07-25: user repeated the correction ("you are still
prompting along ... knock it off") after the first save — trailing
offers count as prompting too. Zero tolerance on this.

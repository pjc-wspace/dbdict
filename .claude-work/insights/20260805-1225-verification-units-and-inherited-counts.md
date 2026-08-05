---
created: 2026-08-05T12:25:56+12:00
title: verification units and inherited counts
tags: [verification, testing, documentation, workflow, gotcha]
source: "/ws done"
---

## a check that passes is not the same as a check that works

The documentation-overlap checker passed on a *deliberately contaminated*
file — twice. Its unit of comparison was the sentence, and sentence boundaries
in markdown are derived from formatting: a `.**` before the next word suppresses
the split, a `---` rule or a `- ` list marker glues onto the following text. Any
of those hides a duplicated claim from a checker that looks correct and reports
PASS. The fix wasn't a better regex, it was removing the assumption: 12-word
shingles have no notion of where a claim starts or ends, so re-wrapping,
re-punctuating, or re-indenting can't defeat them. It then found a real
violation on the first run. Phase 3 believed this invariant was enforced; it was
only being asserted.

## counts copied between planning documents drift, and the drift is silent

Three inherited numbers were wrong in phase 5 — six follow-ups that are seven,
four probes that are six, five pending findings that are seven. Each came from a
*previous plan's summary of an artifact* rather than the artifact. Following the
plan literally would have dropped two live follow-ups and two probes with no
error anywhere. The rule that falls out: when a count is about to become an
action ("triage all N"), re-derive it from the source at that moment — a plan is
a claim about the world, not the world.

## closing a work session is a status correction, not an erasure

The hold marker was the only record of the resumption gate being satisfied;
deleting it would have satisfied the letter of the plan while destroying
evidence two other documents cite. `git mv` to `hold-archive/` clears the held
status — which was the actual goal — and keeps the record.

## scratch-directory durability is about the next session, not this one

`$CLAUDE_JOB_DIR/tmp` outlives a pause/resume within the same background job,
but not a new job. The phase 4 state file was right to flag the verify script as
at-risk — it just happened to survive this time. Anything a future phase's
`verify:` block depends on belongs in the repo; the durability question is "will
a different session need this?", not "is it still there?".

## write the roadmap item before the summary that cites it

Phase 5 had an ordering dependency its checklist did not spell out: the codegen
roadmap item and the closed session's `summary.md` must agree on *why* it
closed. Writing the roadmap item first gives the summary something to cite,
which keeps the "no claim lives in two files" invariant intact rather than
fighting it at verify time.

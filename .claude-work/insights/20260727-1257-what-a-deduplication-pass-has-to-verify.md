---
created: 2026-07-27T12:57:22+12:00
title: what a deduplication pass has to verify
tags: [verification, documentation, refactor, gotcha, testing]
source: /ws done
---

## a "keep this, the other file omits it" decision is a claim, and needs checking

The dedup plan classified a block of content as *keep in the source file, because
the target deliberately omits it*. Acting on that in the next phase, I checked the
target — and it carried the content in full, near-verbatim, including the two
distinctive phrases the plan cited as unique. The premise was simply wrong.

Following it would have produced the exact duplication the whole session existed to
remove, and it would have looked like plan compliance the entire way.

The asymmetry is what makes this easy to miss. A *cut* decision gets verified hard,
because everyone can see that cutting wrongly destroys something. A *keep* decision
feels conservative, so it gets waved through — but "keep, because it's unique" is a
claim about the other document, exactly as falsifiable as "cut, because it's
duplicated", and nothing checks it unless you do.

Worse, the error had propagated upstream: the session's `goal.md` named the same
content as a keeper, on the same unverified premise. A wrong classification that gets
restated in a higher-level document acquires the authority of that document. When you
find one, check whether it has parents.

## a loss check must compare the OLD state to the UNION of the new

The test for "did the restructure lose anything" is not source-after vs target-after.
Both current files are the *output* of the edit, so anything deleted from both scores
as consistent — the check passes precisely because content is gone from everywhere.

The direction that answers the question: take the **pre-edit** source as ground
truth, and check it against the **concatenation** of every file that now exists.
Deletion is then visible as absence, which is what you were trying to detect.

Same trap shape as diffing a migration against its own output. Ground truth has to
come from before the change, and the comparison target has to be the whole of after.

## the threshold you inherited is a floor, not a target

The plan specified "no verbatim run over 120 characters", a number carried over from
an earlier measurement of the same two files. The rewrite passed it clean: zero runs.

Re-running at 60 found one — a 78-character sentence that *I had introduced during
the rewrite*, by restating a line from the target while writing the source's new
pointer to it. Passing at 120 was true and told me nothing, because a hand-written
duplicate is usually one sentence, and one sentence is usually under 120 characters.

Cheap habit: once a check passes, tighten it until it fails, and look at what falls
out. A threshold that never fails is not evidence of quality — it is an untested
instrument.

## hash the artifacts your edit claimed not to touch

The reference document's correctness contract is that its 14 embedded examples all
run. My edits were prose-only, so the examples were fine by construction — a claim I
was about to write down as fact.

Extracting every code block and comparing sha256 against `HEAD` cost one command and
converted "I didn't touch them" from an assertion into a check. It also covers the
edit you forgot you made, which is the only case where it matters.

Generalizes to anything with an invariant an edit is *supposed* to preserve:
generated files, fixtures, snapshots, public API signatures. If the reason you're
confident is "I didn't go near it", that reason is worth thirty seconds of proof.

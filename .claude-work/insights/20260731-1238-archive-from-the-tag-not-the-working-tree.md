---
created: 2026-07-31T12:38:45+12:00
title: archive from the tag, not the working tree
tags: [git, verification, documentation, gotcha, workflow]
source: /ws done
---

## the archive's meaning is "what the tag said", not "what was in the tree"

The plan's phase-1 verify steps use
`diff <(git show ab468fa:README.md) docs/v0.2.0/README.md` rather than diffing
against the working-tree file. That's the right choice: it pins the archive to
the *tagged commit's* content, so if the root files had drifted since `ab468fa`
the archive would still capture the true 0.2.0 state — the archive's meaning is
"what v0.2.0 said", not "what was lying around when I ran cp".

Note the plan says *copy, not move*. Phases 4–5 rewrite the root files in
place, so the archive has to be an independent copy for the rewrite to be
non-destructive — and git's history alone isn't a substitute, because the point
is a browsable `docs/v0.2.0/` for a reader who never runs `git show`.

## staleness attribution needs the tag, not today's tree

Checking those claims *at the tag* rather than *now* matters more than it
looks. If I'd only run `ls site/` I'd have learned "site/ is absent today" —
which is consistent with two very different stories: the README was wrong when
written, or `site/` was deleted afterwards. `git ls-tree ab468fa site/`
distinguishes them, and only the first justifies the wording "already
inaccurate at the time of the tag." An archive note that misattributes
staleness is worse than one that omits it.

The related trap in this phase is the *provenance of the copy*.
`cp README.md docs/v0.2.0/` copies the working tree; the verify diffs against
`git show ab468fa:README.md`. Those agree only because the files hadn't drifted
— which I checked first with `git diff --quiet ab468fa -- <file>`. Had they
drifted, `cp` would have quietly archived the wrong content and the verify
would have caught it *after* the fact. The robust form is to source the archive
from the tag directly (`git show ab468fa:README.md > docs/v0.2.0/README.md`),
making the verify a confirmation rather than a discovery.

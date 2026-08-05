---
created: 2026-08-05T12:42:44+12:00
title: ws close cannot leave a clean tree
tags: [workflow, ws-close, claude-code, gotcha, git]
source: "/state save"
---

## `/ws close` structurally cannot leave a clean tree

Its step 6 commits, then step 7 removes `.claude-work/.active` — so the deletion
of a *tracked* file always lands after the last commit. Goal criterion 8
(`git status --short` empty) passed at commit time and the tree was dirty sixty
seconds later.

This isn't a slip in following the skill; it's the skill's own ordering, and it
will recur at every close until either the removal moves before the commit or
the close verifies the tree *after* step 7. Worth knowing because the dirty tree
then gets swept into whatever the next session commits, attributing a workflow
artifact to unrelated work.

Observed closing session `20260801-1257-v0.3.0-direction-doc-and-repositioning`
on 2026-08-05: commit `8189eb2` reported a clean tree, and the following
`/state save` found ` D .claude-work/.active` outstanding.

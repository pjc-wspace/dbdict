---
name: parallelize-long-independent-work
description: "Run independent long-running jobs concurrently by default; if a reason to serialize exists, ask rather than silently serializing"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 34290466-09e6-4747-be73-04d1b7b032bd
  modified: 2026-07-26T00:39:44.755Z
---

When there are N independent long-running jobs (benchmark runs, test matrices,
builds), launch them **concurrently by default**. Do not silently serialize.

**Why:** on 2026-07-26 I ran a 4-run benchmark sweep serially — ~10 min each,
~40 min total — on a machine with **64 cores** sitting at load ~14. The user's
words: "it is a waste of everyone's time to run serially. you should ask me if
you are concerned about machine cores or something." The cost was invisible to
them until they asked whether I was still running.

**How to apply:**
- Default to parallel for independent work. Check `nproc` before assuming
  resources are scarce — this machine has 64 cores.
- If there IS a genuine reason to serialize, say it and ask. The real one here:
  concurrent processes contend for CPU and distort *benchmark timings*, so
  `-t auto` runs that each claim all cores must not overlap. But single-threaded
  runs on a 64-core box could have overlapped freely, and I never said any of
  this — that was the actual failure, not the choice itself.
- State the expected wall-clock up front for anything multi-minute, so the user
  can redirect before it is spent rather than after.

Related: [[no-unprompted-next-step-nudges]] — the user directs pace, which means
they need the cost information to direct it with.

---
created: 2026-08-05T12:42:44+12:00
title: post-close checkpoint, next is roadmap R1
tags: [workflow, ws-close, spec-design, documentation, gotcha]
summary: Post-close checkpoint after session 20260801-1257 finished all five phases. No active session, no held sessions, roadmap is now the ordering authority and its first item is schema-0.3.yaml. Two decisions are waiting on the maintainer.
---

## Goal

**No active work session.** This is a post-close checkpoint taken minutes after
`20260801-1257-v0.3.0-direction-doc-and-repositioning` closed, to leave a clean
resumption point for whatever starts next.

The 0.3.0 re-baseline's *documents* phase is finished. The next work is the
first that touches `crates/` since the re-baseline began.

## Current State

**All five phases done, all nine goal criteria met, no held sessions.**

```
8189eb2  Close session: v0.3.0 direction document and repositioning
9f35690  Phase 5: the 0.3.0 roadmap, and close the held codegen session
b088398  Replan phase 5: close the held codegen session, codegen gets a fresh one
2c211ec  Phase 4: supersede the held codegen goal instead of rewriting it
8d283d0  Phase 3: reposition README, invert CLAUDE.md's backend stance
65bb47e  Phase 2: the 0.3.0 direction document
094eb14  Phase 1: measure hdf5-temporal-compression — claim holds
```

`.claude-work/.active` is removed. `find .claude-work/sessions -name
'__on-hold__.md'` returns 0 — nothing is waiting to be resumed anywhere in the
project.

**The documents now in force:**

- `docs/vision-direction-0.3.0.md` — canonical scope. `CLAUDE.md` instructs
  reading it before design work
- `docs/roadmap-0.3.0.md` — **the ordering authority**, R1–R20 in dependency
  order, each item naming what it waits on
- `README.md` / `CLAUDE.md` — repositioned; cross-backend portability is now a
  goal, not a non-goal

`crates/` is **unchanged** and still implements the 0.2.0 type system. That is
the recorded debt (direction §11, roadmap R3), not a bug to fix on sight.

## Key Decisions

**The re-baseline was documents-only, deliberately.** A session that also writes
code tends to have its conclusions bent by whatever turned out to be easy to
build. Five phases produced documents and one measurement; nothing in `crates/`
was touched, and the scope line held for four days.

**Correct the record in place, three times over.** Reposition (not repair) the
README; supersede (not rewrite) the stale codegen goal; close (not hold) the
session whose "will resume" had become false. Each keeps the evidence of what was
tried rather than producing a clean-looking document that destroys it.

**Codegen restarts fresh, as roadmap R14** — not a resumption. Its inputs are
named: `spike/`, `research/duckdb-driver-jl/reference.md`,
`review-decisions.md`, and four V1-agnostic undecided findings (8, 10, 13, 15).

**Verification is part of the work.** Three of five phases had their own verify
step fail before the work was believed. The strongest lesson: a documentation
invariant that passes is not the same as one that is enforced — the overlap
checker passed on a poisoned file twice before being rebuilt on 12-word
shingles, then found a real violation immediately.

## Next Steps

**Start a fresh session for the next piece of work** — the roadmap orders it, so
`/ws new` should scope against a roadmap item rather than re-deriving priorities.

**Roadmap R1 — write `schema-0.3.yaml`.** It gates every other code item;
nothing in `crates/` can move until the dataspec format for the dbdict type
vocabulary, `attrdef:` and `languages:` is settled. Blocked by nothing. Direction
§5–§7 is the design, so this is largely transcription into a schema.

Then R2 (`$version` bump plus the 0.2.0 migration story) and R3 (reconcile
`decimal`/`timestamptz`, 121 hits across 19 files).

**Cheapest useful alternative:** R4, probe `sqlite-comment-durability`. It needs
nothing installed, and direction §10 names it the one open probe whose result
could still change a design. R5–R7 all wait on packages that are not present
(SQLite.jl, JLD2, the `ducklake` extension).

### two decisions waiting on the maintainer

1. **`CLAUDE.md` shares one 12-word span with direction §10** — the in-process
   `PATH` guarantee. It was never inside phase 3's overlap check, which compared
   `README.md` against the direction document only. Either it is a violation of
   "no claim lives in two files" and should become a link, or restating it in
   the file agents read first is deliberate. **Not changed pending a ruling.**
2. **Context budget for the next session** — the close asked for a `/context`
   reading and it has not been given. Project convention is to start a phase
   below 25% and stay under 30%, so this matters before R1 rather than after.

### a workflow gotcha worth knowing

`/ws close` commits at step 6 and removes `.claude-work/.active` at step 7, so
**the deletion of `.active` is always left uncommitted** by the close itself.
That is why goal criterion 8 (`git status --short` empty) passed at commit time
and the tree was dirty a minute later. This checkpoint's commit carries it.

## Relevant Files

- `docs/roadmap-0.3.0.md` — **read first**; the ordering authority
- `docs/vision-direction-0.3.0.md` — canonical scope, cited by section number
- `.claude-work/sessions/20260801-1257-v0.3.0-direction-doc-and-repositioning/summary.md`
  — what the closed session produced *and* what it cost
- `.claude-work/state/20260805-1231-v0.3.0-direction-session-closed-all-five-phases.md`
  — the close-time state dump; this file supersedes it only on next steps
- `.claude-work/notes/20260731-1552-dbdict-type-system-decisions.md` — authority
  on types, needed for R1
- `.claude-work/sessions/20260723-1109-julia-read-write-codegen/` — **closed**;
  mine `spike/` and `review-decisions.md` when R14 comes up
- `.claude-work/insights/20260805-1225-verification-units-and-inherited-counts.md`
  — read before writing any verify block

## Environment notes

Bundled DuckDB **1.5.4** (`duckdb` crate `1.10504.0` in `Cargo.lock`). Seven
crates, none for `sqlite`/`hdf5`/`ducklake`. Julia 1.12.6 present; SQLite.jl and
JLD2 are **not**. h5py 3.16.0 / HDF5 2.0.0 via ephemeral `uv` env on Python 3.14.
`ducklake` extension not installed. `git tag v0.2.0` → `ab468fa`.

`$CLAUDE_JOB_DIR/tmp/verify_phase5.py` is **ephemeral and will not survive this
job** — roadmap R16 covers promoting it alongside the 13 stranded audit scripts.

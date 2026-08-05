---
created: 2026-08-05T11:52:53+12:00
title: phases 1-4 done, paused before phase 5
tags: [spec-design, documentation, workflow, ws-mid-session, verification]
summary: Session 20260801-1257 is active and paused at a clean phase boundary with 4 of 5 phases done and committed. Phase 4 was replanned mid-session from "rewrite the held codegen goal" to "supersede it", and phase 5 was then replanned again to close that session outright — codegen gets a fresh session.
---

## Goal

Session `20260801-1257-v0.3.0-direction-doc-and-repositioning` — **active,
paused at a phase boundary, not mid-phase.** Direct continuation of the closed
`20260731-0930-…`, whose phases 3–6 carry forward here as phases 2–5.

Produce the public-facing direction document for the 0.3.0 re-baseline,
reposition the repo's own documents around it, and leave an ordered roadmap —
with the one load-bearing inferred claim measured first.

## Current State

**Working tree clean. Four of five phases done and committed.**

```
b088398  Replan phase 5: close the held codegen session, codegen gets a fresh one
2c211ec  Phase 4: supersede the held codegen goal instead of rewriting it
8d283d0  Phase 3: reposition README, invert CLAUDE.md's backend stance
65bb47e  Phase 2: the 0.3.0 direction document
094eb14  Phase 1: measure hdf5-temporal-compression — claim holds
```

| # | phase | state |
|---|---|---|
| 1 | `hdf5-temporal-compression` probe | **DONE** 2026-08-02T13:45 |
| 2 | direction document | **DONE** 2026-08-03T09:25 |
| 3 | reposition README, invert CLAUDE.md | **DONE** 2026-08-03T13:24 |
| 4 | supersede held codegen goal | **DONE** 2026-08-04T10:22 |
| 5 | roadmap + triage + close held session + clean tree | not started |

Goal criteria met: 0, 1, 2, 3, 4, 5, 7. Outstanding: **6 and 8, both phase 5.**

## Key Decisions

**Phase 3 — repositioned, not repaired.** The binding constraint was goal
criterion 3's *conjunction*: every claim true of the repo **and** of V1's scope.
Those pull opposite ways (`dummy` ships today, is out of V1), so the README
states tense and scope per claim instead of picking one timeline — a status
banner, *what V1 of 0.3.0 covers* (links only), and *what runs today*.
`CLAUDE.md` inverts the cross-backend stance and qualifies the in-process
guarantee per target. Anchor fragments were written then **removed**: GitHub's
heading→anchor slugification would have been an unsourced external claim, and a
wrong slug fails silently. Section numbers live in the link text instead.

**Phase 4 — replanned before starting, on the maintainer's assessment.** The
plan was to rewrite the held codegen session's `goal.md` against V1 scope,
preserving the original as `goal-v0.2.0.md`. Maintainer: *"even my goals were
wrong."* That makes rewriting the wrong operation — it would launder a mistaken
design into a fresh-looking document and destroy the evidence it was tried.
Instead `goal.md` is **superseded in place**: body byte-identical (40
insertions, 0 deletions), banner names which premises died — chiefly the
per-language companion mapping file that direction §7 deletes outright.

Two supporting findings worth keeping:
- the file was stale in **three layers** (decided review findings never
  batch-edited in, five findings never decided, then V1), so a rewrite would
  have produced a fourth state matching none of the three records
- **the held session's resumption gate is satisfied** — all four driver items
  closed by `20260725-1252`, `20260727-0924`, `20260727-1540`, which produced
  `research/duckdb-driver-jl/reference.md`. What blocks it is scope, not
  knowledge

**Post-phase-4 — codegen gets a fresh session, so the held one closes.**
Maintainer: *"codegen gets its own session, needs a fresh new look."* A hold
asserts "will resume", now known false; the banner and hold note are already
truthful, so the **status** is the last inaccurate thing about that session.
This is option (c) from the phase 4 discussion, arriving one step after it was
proposed — (b) preserved the record, (c) corrects the status. Goal criterion 5
now carries three states, with each superseded wording struck rather than
deleted.

**Standing decisions, unchanged:** roadmap is a **sibling** file, not a section
of the direction doc; hard scope line — `crates/`, `schema*.yaml`, `$version`
are **out**, the `decimal`/`timestamptz` divergence is documented not closed.

## Next Steps

**Phase 5 — roadmap, triage, close, clean tree.** Replanned; read `impl.md`
phase 5 first, it is current.

1. Write `docs/roadmap-0.3.0.md` — ordered, every item naming its blocking
   dependency. Folds in: the six benchmark follow-ups (item 6, "resume the held
   codegen session", is **struck and superseded**), the four open probes
   (`sqlitejl-temporal`, `pg-type-oracle` → V2, `sqlite-comment-durability`,
   `jld2-h5-crosscheck`), and the `decimal`/`timestamptz` code-vs-docs
   divergence as its own item.
2. The codegen roadmap item says **fresh session** and names its inputs: the
   artifacts worth mining (`spike/`, `research/duckdb-driver-jl/reference.md`,
   `review-decisions.md`) **and the four still-undecided review findings** —
   8 identifier safety, 10 output model, 13 verify wording, 15 pk phrasing.
   V1-agnostic, and useless to a fresh session if left buried in a July ledger.
3. **Close** `20260723-1109-julia-read-write-codegen`: write its `summary.md`
   (phase 1 spike complete though its `/ws done` never ran; gate satisfied;
   goal superseded 2026-08-04; ledger part-decided), remove `__on-hold__.md`.
   Nothing else in that directory changes.
4. Re-verify the three research dirs are dispositioned (done in `410a44a` —
   re-verify rather than assume), then clean tree.

**Live forward reference closes here:** `docs/vision-direction-0.3.0.md` links
`docs/roadmap-0.3.0.md` from §10 and §11; that file does not exist until
phase 5.

**Tooling gap for phase 5:** the sentence-overlap checker
(`verify_phase3.py` — the "no claim lives in two files" invariant) lives in the
**job tmp dir and is not committed**. Phase 5's verify block requires the same
check against `docs/roadmap-0.3.0.md`, so it must be promoted somewhere durable
or re-written. It strips fenced code and table rows before comparing, and it was
poison-tested — a planted sentence made it fail across differing line-wrapping.

To resume: `/ws resume` (no argument — `.active` is set, session is paused).

## Relevant Files

- `.claude-work/sessions/20260801-1257-v0.3.0-direction-doc-and-repositioning/impl.md`
  — plan **and** record. Phases 1–4 carry `- also:` entries; phase 5 was
  amended 2026-08-05. **Start here on resume.**
- `…/goal.md` — criterion 5 carries two struck amendments; read it before
  touching the held session
- `docs/vision-direction-0.3.0.md` — the canonical scope statement; phases 3
  and 5 cite it rather than restate it
- `README.md`, `CLAUDE.md` — repositioned in phase 3
- `.claude-work/sessions/20260723-1109-julia-read-write-codegen/` — `goal.md`
  (banner, body verbatim), `__on-hold__.md` (dated 2026-08-04 section);
  `impl.md`, `review-decisions.md`, `driver-reference-handoff.md`, `spike/`
  all untouched
- `.claude-work/notes/20260802-1146-hdf5-temporal-compression.md` — probe result
- `.claude-work/notes/20260731-1552-dbdict-type-system-decisions.md` — authority
  on types
- `.claude-work/insights/20260803-1324-documentation-invariants-need-mechanical-checks.md`
- `.claude-work/insights/20260804-1022-superseding-beats-rewriting-a-stale-record.md`

## Environment notes

Bundled DuckDB is **1.5.4** (`duckdb` crate `1.10504.0` in `Cargo.lock`; also
the highest version string in `target/release/dbdict`). Seven crates. No `site/`
directory. h5py 3.16.0 / HDF5 2.0.0 reachable via ephemeral `uv` env on Python
3.14; Julia 1.12.6 present, SQLite.jl and JLD2 are not.

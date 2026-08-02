---
created: 2026-08-03T09:35:35+12:00
title: phases 1-2 done, paused before phase 3
tags: [spec-design, documentation, verification, storage, ws-mid-session]
summary: Session 20260801-1257 is active and paused at a clean phase boundary with 2 of 5 phases done and committed. The HDF5 probe closed the last open Inferred: claim and the direction document is written; phase 3 (README + CLAUDE.md) is next and is mechanical.
---

## Goal

Session `20260801-1257-v0.3.0-direction-doc-and-repositioning` — **active,
paused at a phase boundary, not mid-phase.** Direct continuation of the closed
`20260731-0930-…`, whose phases 3–6 carry forward here as phases 2–5.

Produce the public-facing direction document for the 0.3.0 re-baseline,
reposition the repo's own documents around it, and leave an ordered roadmap —
with the one load-bearing inferred claim measured first.

## Current State

**Working tree clean. Two of five phases done and committed.**

```
65bb47e  Phase 2: the 0.3.0 direction document
094eb14  Phase 1: measure hdf5-temporal-compression — claim holds, decision stands
3337de5  State: post-close checkpoint with commit SHAs   ← parent session
```

| # | phase | state |
|---|---|---|
| 1 | `hdf5-temporal-compression` probe | **DONE** 2026-08-02T13:45 |
| 2 | direction document | **DONE** 2026-08-03T09:25 |
| 3 | reposition README, invert CLAUDE.md | not started |
| 4 | rewrite held codegen `goal.md` | not started |
| 5 | roadmap + triage + clean tree | not started |

Goal criteria met so far: 0, 1, 2, 7. Outstanding: 3, 4 (phase 3), 5 (phase 4),
6, 8 (phase 5).

## Key Decisions

**Phase 1 — the probe held, and changed the wording anyway.** Lexical temporals
compress to **4.52–4.63 bytes/row sorted, 7.43–7.51 shuffled** with
`shuffle+gzip(9)`, clearing the 8.0 bytes/row raw `int64` threshold in every
case. *Canonical ≠ physical* stands; nothing reopened. But three findings the
plan did not anticipate now shape the documents:

- **szip is inapplicable to lexical temporals.** `filter_avail()` reports it
  present; `H5Dcreate` rejects fixed-width strings — *"SZIP compression can only
  be used with atomic datatypes that are integer, float, or char"*, and the
  conflict *"can only be detected when the property list is used"*. Availability
  ≠ applicability. New capability-matrix row.
- **The fair baseline is *compressed* `int64`, not raw.** Against it, lexical
  costs **1.14–1.27×** — far better than the 3.4–7.6× the uncompressed figures
  implied. The original claim compared against the wrong baseline in the
  direction that flattered it.
- **Size was never the real cost — read time is**, at 6.6× (`S27`) to 15.8×
  (`S61`). The decisions note asked for read throughput almost in passing.

Also: *"well under"* is true of **sorted** data only — shuffled clears by 6–7%.
The direction document does not reuse the old phrasing.

**Phase 2 — the direction document is written and is the single source.** 11
sections, 16 external links across 6 official domains, 12 `[measured]` · 12
`[cited]` · 10 `Inferred:`, 0 placeholders. Three unsourced quotes were caught
*during verify* and fixed by fetching the source first (SQLite type affinity,
SQLite `"TEXT as ISO8601 strings"`, PostgreSQL `"stored internally as UTC"`)
rather than by guessing plausible URLs. One claim (HDF5 variable-length strings)
is cited by internal cross-reference because its original URL could not be
placed — an honest pointer beat a tidy-looking fabricated link.

**Standing decisions from planning, unchanged:**
- roadmap goes in a **sibling** `docs/roadmap-0.3.0.md`, not inside the
  direction doc — it churns on a different clock than a positioning statement
- phase 4 rewrites the held session's `goal.md` **only**; `impl.md` and
  `review-decisions.md` stay untouched, with `__on-hold__.md` merely *flagging*
  that the 15-finding ledger is partly moot under V1
- hard scope line: `crates/`, `schema*.yaml`, `$version` are **out**. The
  divergence is documented, not closed

## Next Steps

1. **Phase 3 — reposition `README.md`, invert `CLAUDE.md`.** Mechanical
   compared to phase 2. Facts already confirmed and waiting:
   - **seven crates, not four** — `dbdict`, `dbdict-cli`, `dbdict-ddl`,
     `dbdict-duckdb`, `dbdict-dummy-data`, `dbdict-dummy-data-duckdb`,
     `dbdict-parquet`. `CLAUDE.md` currently lists four
   - **no `site/` directory** — its links were already dead at the `v0.2.0` tag
   - `CLAUDE.md`'s *"not aiming for cross-backend portability"* stance is
     **inverted**, not tweaked; the in-process guarantee becomes per-target
   - both files **link** `docs/vision-direction-0.3.0.md` rather than restating
     it — no claim in two files
2. **Phase 4** — rewrite the held codegen `goal.md` (preserve `goal-v0.2.0.md`
   byte-identical; update `__on-hold__.md`; session stays held).
3. **Phase 5** — `docs/roadmap-0.3.0.md`: the six benchmark follow-ups, the four
   remaining open probes, and the `decimal`/`timestamptz` code-vs-docs
   divergence, each ordered with its blocking dependency. Then clean tree.

**Live forward reference:** `docs/vision-direction-0.3.0.md` links
`docs/roadmap-0.3.0.md` in §10 and §11, which does not exist until phase 5.
Same pattern the archive note had; it closes inside this session.

To resume: `/ws resume` (no argument — `.active` is set and the session is
paused, not held).

## Relevant Files

- `.claude-work/sessions/20260801-1257-v0.3.0-direction-doc-and-repositioning/impl.md`
  — plan **and** record; phases 1–2 carry `- also:` entries for everything that
  deviated from plan. **Start here on resume.**
- `docs/vision-direction-0.3.0.md` — the deliverable so far; phases 3 and 5 cite
  it rather than restating it
- `.claude-work/notes/20260802-1146-hdf5-temporal-compression.md` — the probe
  result, full matrix and verdict
- `research/hdf5-temporal-compression/` — `probe.py` (uv inline metadata,
  re-runnable) + `README.md` with 11 quoted-and-linked API citations
- `.claude-work/notes/20260731-1552-dbdict-type-system-decisions.md` — authority
  on types; §8 now `[measured]`, open-probe list updated
- `.claude-work/insights/20260802-1345-measure-before-freezing-a-spec.md`
- `.claude-work/insights/20260803-0925-verify-scripts-encode-assumptions.md`

## Environment notes

h5py **3.16.0**, HDF5 library **2.0.0**, numpy 2.5.1, via ephemeral `uv` env on
Python 3.14 (system Python is 3.10.12). All four filters present —
gzip/shuffle/szip/lzf — though szip is unusable on string columns. `uv` 0.9.26.
Julia 1.12.6 present; SQLite.jl and JLD2 are not. h5py is now reachable, which
partially unblocks the `jld2-h5-crosscheck` probe.

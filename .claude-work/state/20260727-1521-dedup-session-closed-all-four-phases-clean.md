---
created: 2026-07-27T15:21:34+12:00
title: dedup session closed — all four phases done, audit clean
tags: [documentation, refactor, verification, duckdb, ws-close]
summary: Session 20260727-0924-dedup-findings-and-reference closed. findings.md is now a provenance record (404 → 139 lines), every driver fact has one home in reference.md, and the four-pass audit is clean. Five internal contradictions were found and fixed. reference.md is ready as the codegen session's resumption gate.
---

## Where things stand

Session `20260727-0924-dedup-findings-and-reference` is **CLOSED**. All four phases
done, summary at the session dir. Working tree clean apart from two untracked
research dirs that are not mine (`research/parquet2-as-alternative-backend/`,
`research/quackio-driver-jl/`).

Commits: `1c6b07b` phase 1 · `9c41371` phase 2 · `7bfa3a5` goal amendment ·
`a4943de` phase 3 · `d6f947e` contradiction fixes · `3da2b32` phase 4 audit ·
`5e97d95` phase 4 marked done.

## The deliverable

`research/duckdb-driver-jl/reference.md` (1617 lines) is the single source of truth
and is **audit-clean**: 14/14 julia blocks run with 12/12 documented outputs matching,
160/160 citations resolve against the installed driver source, 46/46 anchors resolve,
0 claims lost against the pre-session state.

`findings.md` (139 lines, down from 404) is now a probe notebook only — no verdicts,
no tables, no code. Each section gives the question the probe answered, the confound
it had to get past, and a pointer to its `reference.md` home.

## What a future session most needs to know

**The reference doc's audit is re-runnable.** Eight tools in the session's `tools/`.
The four that matter after any future edit:

```
python3 tools/runblocks.py reference.md . -j 6      # executes all julia examples
python3 tools/citations.py reference.md ~/.julia/packages/DuckDB/2J7sd/src .
python3 tools/anchors.py reference.md
python3 tools/vruns.py findings.md reference.md 120
```

**Five contradictions were found this session, all in summary constructs** — the
executive summary, the tier table, a guard count, a list label. None in the sections
holding evidence. If you edit this document, re-check §1, §4.1, §8.1 and §8.2 against
each other; that quartet is where every defect has appeared across two sessions.

**Do not trust a fact map you did not just rebuild.** Three of phase 1's nine
per-fact actions were wrong by the time phase 3 executed them.

**Two of my own verification tools were broken in opposite directions** and both had
been reporting clean. Check which direction a checker's bugs fail in.

## Scope decision that changed mid-session

`goal.md` excluded rewriting `reference.md`'s substance. The user directed fixing the
found contradictions in-session, so the exclusion was **narrowed, not ignored**:
correcting a statement that contradicts §4.1 is in scope because it needs no new
facts. Anything requiring a fact the document does not already hold remains a
recorded follow-up. The annotation is inline in `goal.md`.

## Open follow-ups

- `results.md` / `results.json` / `raw/results-*.json` — a third layer of the same
  benchmark numbers, never reconciled against `reference.md` §7. Out of scope twice
  now; still outstanding
- the held codegen session `20260723-1109-julia-read-write-codegen` — `reference.md`
  was its resumption gate and is now clean, so it is unblocked. Its handoff is
  `sessions/20260723-1109-julia-read-write-codegen/driver-reference-handoff.md`
- §8.1's tier rules now correctly fall mixed-type tables through to tier 5, but the
  *strategy* for such tables (literal-only, or split writes) is a codegen decision
  nobody has made — see `notes/20260727-1306-…` options 1-3

## Standing context

- upstream bug filing: **not doing it** (user, 2026-07-27) — §5.4 records the five
  candidates with reproducers so filing stays available at no re-investigation cost
- environment pinned and unchanged: DuckDB.jl 1.5.2 / DuckDB_jll 1.5.4+0, julia
  1.12.6, driver source `~/.julia/packages/DuckDB/2J7sd/src/`
- no unprompted next-step nudges; user triggers all workflow commands
- context budget: don't start a phase at ≥25%; this session ran 4 phases in one
  context and finished around 19-25%, because the heavy reading was delegated to
  scripts rather than done by reading files into context

---
created: 2026-08-01T11:03:43+12:00
title: post-close checkpoint, type system settled
tags: [spec-design, storage, serialization, duckdb, ws-close]
summary: Session 20260731-0930 is closed and committed at 56d5b3c with phases 1-2 done and 3-6 untouched. The dbdict type system is settled (10 types, RFC-profiled temporals, canonical separate from physical storage); the next work is phase 3, the direction document.
---

## Goal

v0.3.0 re-baseline: record a direction that had already shifted, and repair
documents describing a repo that no longer exists. dbdict stops being a
DuckDB-native *data dictionary* and becomes a **dataspec** that drives
generation across storage targets, in both directions.

## Current State

**Session closed and fully committed. Working tree clean, `.active` removed.**

```
56d5b3c  Close session: remove .active tracker
1257171  Phase 2 + close: capability research becomes a type-system redesign
0f05670  Phase 1: archive the 0.2.0 documents
```

- **phase 1 done** — `docs/v0.2.0/` holds byte-identical copies of the 0.2.0
  `README.md` and `CLAUDE.md` plus an archive note
- **phase 2 done** — grew from "fill a capability matrix" into a full
  type-system redesign, because the research falsified three `goal.md` claims
- **phases 3–6 not started** — direction document, README/CLAUDE.md reposition,
  held codegen goal rewrite, roadmap + triage

This supersedes `.claude-work/state/20260801-1047-…md`, which was written
during the close before the commits landed. Content is the same; this one has
the SHAs.

## Key Decisions

**The type system — 10 "dbdict types"** (*lingua franca* / *LF* retired and
swept from every file):

```
bool  int8  int16  int32  int64  float32  float64  string  date  timestamp
```

- numerics and `bool` defined by **bit layout**; temporals by **pinned RFC
  profile**. `date` = RFC 3339 `full-date`; `timestamp` = RFC 3339 `date-time`
  µs + optional RFC 9557 `[Zone]`
- **canonical ≠ physical** — native type where one exists (DuckDB, DuckLake,
  Postgres), lexical form where none does (SQLite, HDF5). *Why:* what must be
  shared is the value space, not the bytes; imposing one encoding would have
  broken every stock SQLite driver, since Python and rusqlite both write ISO
  text
- removed: `decimal(p,s)` → V2+ · `timestamptz` removed · `datestamp` never
  introduced (no compliant spelling exists, and a zoned date is provenance,
  not a distinct value)
- zones: in-value per RFC 9557, **plus** `timezone:` / `timezone_from:` as the
  required spillover where a native type discards the zone. *Why:* measured —
  DuckDB's `TIMESTAMPTZ` renders one stored value as `+00`, `+12` or `-04` by
  session setting alone
- SQLite emission **non-STRICT**. *Why:* dbdict already establishes correctness
  by querying after load, not by constraining at insert; and STRICT rejects
  `BIGINT`/`BOOLEAN`/`DATE` outright, which would push every type into the
  sidecar and break brown-field `draft`
- `string` unbounded; `max_chars:` / `max_bytes:` optional constraints, the
  latter doubling as HDF5's compression switch — variable-length HDF5 strings
  get no chunking and no filters
- **V1 targets: `duckdb` `ducklake` `sqlite` `hdf5`. `postgres` → V2** (breaks
  the in-process guarantee, no 1-byte integer, unprobeable here)

**What phase 2 falsified in `goal.md`** (corrected in-phase, struck through
rather than deleted): the flat-cost curve across SQL targets; "8 of 12 types
free everywhere" (three, against V1 targets); "SQLite comment support
unverified" (no `COMMENT ON`, but DDL comments survive verbatim in
`sqlite_schema.sql`).

## Next Steps

1. **Phase 3 — `docs/vision-direction-0.3.0.md`.** The largest remaining
   phase. Start on a **fresh context**. Its `impl.md` entry carries a banner
   directing the reader to the 1552 decisions note *before* `goal.md`.
2. Phases 4–6: README/CLAUDE.md reposition · held codegen goal rewrite ·
   roadmap, triage of the six benchmark follow-ups, clean tree.
3. **Fix the dangling link**: `docs/v0.2.0/README-archive-note.md` references
   `docs/vision-direction-0.3.0.md`, which phase 3 creates. It is live in a
   committed file now.
4. Optional before phase 3 freezes the spec:
   - **`hdf5-temporal-compression`** — the only open probe that could reopen a
     settled decision. Lexical temporals cost 27–61 bytes/row vs 8 for
     integers; "compression closes the gap" is `Inferred:`, not measured.
     Needs `h5py` (not installed).
   - **`sqlitejl-temporal`** — the one unresolved driver row. Julia 1.12.6 is
     installed, SQLite.jl is not. Matters because Julia is the first codegen
     target and SQLite.jl may serialize to `BLOB`.
   - also open: `pg-type-oracle` (deferred with Postgres) ·
     `sqlite-comment-durability` · `jld2-h5-crosscheck`

To resume: `/ws list`, then start a new session for phase 3 — the old one is
closed, so `/ws resume` will not pick it up.

## Relevant Files

- `.claude-work/notes/20260731-1552-dbdict-type-system-decisions.md` —
  **start here**; authority on types, 15 decisions, 16 cited sources
- `.claude-work/notes/20260731-1253-capability-matrix.md` — per-target
  capability research; **partly superseded**, banner says which parts
- `.claude-work/sessions/20260731-0930-…/summary.md` — what was and wasn't done
- `.claude-work/sessions/20260731-0930-…/impl.md` — phases 3–6 plan text
  updated to the new decisions so it is not stale on resume
- `.claude-work/sessions/20260731-0930-…/goal.md` — brainstorm record,
  corrected in place
- `docs/v0.2.0/` — frozen 0.2.0 README + CLAUDE.md + archive note
- `.claude-work/insights/20260801-1047-canonical-form-can-outrun-its-physical-layers.md`

## Environment notes

Probes ran against DuckDB CLI **v1.5.4** and SQLite **3.37.2** (Python 3.10.12
stdlib `sqlite3`). Julia **1.12.6** present. Not available: `sqlite3` CLI,
`psql`, `h5dump`, `h5py`, SQLite.jl.

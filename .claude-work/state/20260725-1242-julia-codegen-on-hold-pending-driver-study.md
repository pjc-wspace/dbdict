---
created: 2026-07-25T12:42:43+12:00
title: julia codegen on hold pending driver study
tags: [julia, duckdb, rust, adversarial-review, ws-mid-session]
summary: Session julia-read-write-codegen goes on hold after phase 1 (spike) and a 15-finding adversarial plan review, 12 findings decided. User wants the DuckDB.jl driver fully understood, benchmarked, and documented before codegen work resumes.
---

## Goal

Session `20260723-1109-julia-read-write-codegen`: a `crates/dbdict-julia`
generator crate emitting Julia read/write code from the dict, with
companion mapping files (`DBNAME.dbdict-jlmap.yaml`), the
`DBNAME.dbdict.yaml` naming convention, a `dbdict gen julia` subcommand,
and round-trip verification. ON HOLD: the user wants the DuckDB.jl
driver fully understood, benchmarked, and documented first.

## Current State

- **Phase 1 (capability spike): work complete, `/ws done` NEVER RUN** —
  no phase commit, no `— DONE` mark in impl.md. Spike scripts live in
  the session dir `spike/` (untracked), findings in
  `notes/20260723-1530-duckdb-jl-capability-spike.md` (+ §2b addendum).
- **Goal and plan were adversarially reviewed** (independent agent):
  15 findings (3 blocker, 8 major, 4 minor). Worked through one at a
  time with the user; **decided: 1-7, 11, 14 (via driver study), plus
  the supported/unsupported type lists. Still open: 8 (identifier
  safety), 10 (gen julia output model / --out), 12 (companion pairing
  for legacy no-stem filenames), 13 (trivial: `validate` →
  `validate-spec` in phase 2 verify), 15 (pk phrasing + pk-on-compound
  edge).** Full ledger: session dir `review-decisions.md`.
- **The batch edit of goal.md + impl.md applying all decided findings
  has NOT been done yet** — goal.md and impl.md still carry pre-review
  text (defaults-as-data-file, three-sibling-scope companion structure,
  "dep on core only", old type promises). review-decisions.md is the
  source of truth until the batch edit lands.
- Driver study complete: `notes/20260725-1007-duckdb-jl-driver-study.md`
  (agent-written, file:line-cited against installed DuckDB.jl 1.5.2 —
  latest registered release, verified). Key: reads columnar for all
  types (except ARRAY: throws); only columnar write route is
  registered-table scan + INSERT..SELECT, flat scalars minus UUID only;
  direct chunk-append exists in C API, unexposed; appender errors
  silent; empty-vector→NULL, list non-ASCII truncation bugs;
  bind ⊂ appender coverage.
- Uncommitted: review-decisions.md, state files, notes, spike/ dir,
  impl.md edits (phase 5/6 annotations + gen julia + phases 7/8 from
  rescope). Last commit `9c74ca5` (session open).

## Key Decisions

(full rationale in review-decisions.md — headlines only)
- Type structure: hoist DuckType/parse_type from dbdict-dummy-data-duckdb
  into dbdict-duckdb; +4 parser arms (TIMESTAMP_S/MS/NS, TIMETZ);
  generators depend on dbdict + dbdict-duckdb (not "core only")
- Hard two-list type split, error at both intake points (dict + mapping
  file). Supported: bool, all ints, floats, decimal, varchar, blob,
  date, time(µs), timestamp(ms), timestamptz/timetz (UTC contract),
  uuid, enum, list, struct, map + nestings. Unsupported: array, union,
  interval, bit, geometry, json, timestamp_s/ms/ns. Promotion only via
  round-trip harness.
- Companion file: LHS = typedef name | base keyword | DECIMAL(w,s) only
  (nested overrides must be typedef-named, 1:1); RHS = verbatim julia
  type or type_declarations handle; type_declarations = pure references
  {type?, using?} — NO embedded julia code; defaults are rust code
  recursing over DuckType, not a data file; read contract RHS(v)
  constructor, write contract structural serialization
- Writer tiers (driver-study-revised): appender for scalar-only tables
  (+ row-count verification — appender errors are silent); flatten +
  register + SQL reassembly for struct columns with flat leaves; SQL
  literals for the rest. LIST always via literals (empty-vec→NULL +
  non-ASCII bugs). Never emit per-row prepared INSERTs, load!,
  lastrowid.
- Case: ASCII-case-insensitive companion matching + uniqueness; readers
  emit AS-alias per column; engine (not dbdict) rejects typedef names
  shadowing builtins — measured
- dbdict core engine NOT switchable; generator crates CANNOT carry a
  second engine (libduckdb-sys `links = "duckdb"` — verified locally);
  target-engine purity via routing fixtures through the target driver
  itself; version stamp in generated headers
- Live-execution smoke tests from phase 5 (skip if no julia, FAIL with
  instructions if packages missing; committed harness Project.toml)
- User feedback (memory saved): NO unprompted next-step nudges/offers

## Next Steps

**Resume gate (the reason for the hold):** fully understand, benchmark,
and document the DuckDB.jl driver. Concretely, the unfinished pieces:
1. **Benchmark** (study did docs+code only, no measurements): appender
   vs registered-scan+INSERT..SELECT vs literal SQL for bulk loads at
   realistic sizes; streaming vs materialized reads. New spike scripts
   in the session spike/ dir or a fresh notes doc.
2. Settle the spike/study discrepancy: appender blob (spike measured
   ERR, code has duckdb_append_blob wired — one measurement is
   confounded).
3. Verify inferred items: appender VARCHAR→ENUM cast; appender flush
   inside transactions; StructArray through register_table.
4. Document: consolidate driver study + benchmarks + spike findings
   into one driver reference doc (the user wants documentation as a
   deliverable, likely .claude-work/notes/ or site/).
Then, on resume: finish review findings 8, 10, 12, 13, 15 → batch-edit
goal.md + impl.md against review-decisions.md → run overdue `/ws done`
for phase 1 (includes committing spike/ + notes).

## Relevant Files

- .claude-work/sessions/20260723-1109-julia-read-write-codegen/
  goal.md, impl.md (STALE vs decisions), review-decisions.md (source of
  truth), spike/*.jl (8 scripts + Project.toml/Manifest)
- .claude-work/notes/20260723-1530-duckdb-jl-capability-spike.md
- .claude-work/notes/20260725-1007-duckdb-jl-driver-study.md
- ~/.julia/packages/DuckDB/2J7sd/src/ — installed driver source (1.5.2)
- crates/dbdict-dummy-data-duckdb/src/types.rs — DuckType parser to hoist
- crates/dbdict-cli/src/main.rs:242-260 — discovery to change (phase 2)
- memory: no-unprompted-next-step-nudges.md (new this session)

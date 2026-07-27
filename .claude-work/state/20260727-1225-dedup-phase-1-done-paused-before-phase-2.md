---
created: 2026-07-27T12:25:03+12:00
title: dedup session — phase 1 done, paused before phase 2
tags: [documentation, refactor, verification, duckdb, ws-mid-session]
summary: Session 20260727-0924-dedup-findings-and-reference paused at a clean phase boundary. Phase 1 (inventory + decision table) is committed at 1c6b07b. dedup-plan.md is a complete, self-contained instruction set for phases 2-4 — a fresh context needs that file and nothing else.
---

## Goal

Session `20260727-0924-dedup-findings-and-reference` (ACTIVE, paused at a phase
boundary — not mid-phase). Deduplicate `research/duckdb-driver-jl/findings.md`
and `reference.md`: reduce findings.md to a provenance record, and give every
driver fact exactly one authoritative home in reference.md.

Why it matters: this is the same defect class that produced the worst bug of the
previous session — writer-tier guidance lived in two places, drifted, and the
summary table ended up routing BLOB columns to a path the same document said never
to use. Single-sourcing is the structural fix.

## Current state

**Phase 1 DONE** (`1c6b07b`) — inventory and decision table. **Nothing deleted
yet**; phase 1 was inventory-only by design.

**Phase 2 NOT STARTED** — reduce findings.md to a provenance record.

Working tree clean apart from two untracked research dirs that are not mine
(`research/parquet2-as-alternative-backend/`, `research/quackio-driver-jl/`).

## THE ONE FILE A FRESH CONTEXT NEEDS

`.claude-work/sessions/20260727-0924-dedup-findings-and-reference/dedup-plan.md`

It is a complete instruction set: §A the six unique-substantive items to move,
§B what stays in findings.md as provenance, §C what to cut, §D the per-fact
intra-reference.md single-sourcing table, §E phase 4's verification contract.
Read it and `impl.md`; you do not need to re-derive anything.

## What phase 1 found

Baseline `inventory-before.tsv`: **1021 claims** (findings.md 256, reference.md
765), 59 heading contexts, coverage verified complete.

**The unique-substantive list is NOT empty — 6 items.** The important one:

> **A1 — reference.md §5.2.1 lost findings §6's six-row literal-form table in the
> phase-3b rewrite.** It now asserts "adding digits does not help" with **no
> evidence**, and names the quoted-string fix (`'0.119…'::DOUBLE`) without ever
> showing it. The proof that `%.17g` + `::DOUBLE` is *still* 1 ULP low exists only
> in findings.md. **Move it back before cutting anything.**

The other five: `table_scan.jl:201` (the precise line behind the zero-copy
registration claim), three C error strings that are the observable evidence of
silent appender failure (`Invalid unicode…`, `Call to EndRow…`, `Failed to cast
value: Unimplemented type for cast (INTEGER -> ENUM(…))`), and the concrete
over-precision decimal case (`FixedDecimal{Int64,4}(12.3456)` → `DECIMAL(18,2)` →
`12.35`).

Worst internal duplication in reference.md: **LIST-segfault, 15 mentions across
12 sections**. Full map in dedup-plan.md §D.

## Two methodology traps — recorded so they are not re-run

1. **Line-level similarity is the wrong unit.** `crossmatch.py` returned 113
   "unique" lines, nearly all false: the two files state identical facts with
   different sentence breaks, so a true duplicate scores unique because no single
   line pairs up. It measures line wrapping. `matched-findings.tsv` is kept as
   evidence, not as input.
2. **Use `tools/tokencov.py`** — distinctive tokens (`file.jl:NNN`, backticked
   identifiers, C error strings, numbers) survive rewrapping. It already has the
   necessary fix: whitespace collapsed on both sides, or a token wrapped across a
   line break in the target reads as absent.

Also: `tools/inventory.py` captures **all** non-fence lines by design. An earlier
version counted only bold-carrying paragraph lines and silently dropped 459
claims. Do not "optimize" that back — recall loss is unprotected claims.

## Next steps (phase 2)

Per `impl.md` phase 2, in this order:

1. **Move the six §A items into reference.md FIRST.** findings.md must not be
   reduced while it is still the sole home of any fact.
2. Cut everything in dedup-plan.md §C from findings.md — verdict lines, probe
   result tables, mechanism prose, the `ccall` recipe (superseded, and its comment
   is *wrong*), the phase-1 summary table, the corrections list.
3. Keep and sharpen the §B provenance layer.
4. Rewrite findings.md's header so its role is unmistakable — a lab notebook, not
   a source of truth.
5. **verify:** no verdict/table/code block survives that reference.md also
   carries; every cut line is accounted for; the two files share no verbatim run
   over 120 chars.

Then phase 3 (single-source within reference.md) and phase 4 (four-pass audit).

## Relevant files

- session: `.claude-work/sessions/20260727-0924-dedup-findings-and-reference/`
  — goal.md, impl.md (phase 1 marked DONE with the actual record), dedup-plan.md,
  inventory-before.tsv, matched-findings.tsv, tokencov-findings.txt, tools/
- targets: `research/duckdb-driver-jl/findings.md`, `reference.md` (1527 lines,
  14 executed julia examples — **any edit must keep them running**)
- out of scope this session: the two notes files, results.md, the raw JSON, the
  held codegen session

## Standing context

- prior session closed at `545f07d`; its handoff to the held codegen session is
  `.claude-work/sessions/20260723-1109-julia-read-write-codegen/driver-reference-handoff.md`
- upstream bug filing: **not doing it** (user, 2026-07-27)
- no unprompted next-step nudges; user triggers all workflow commands
- context budget: don't start a phase at ≥25%; this pause was taken at the phase
  1/2 boundary for exactly that reason

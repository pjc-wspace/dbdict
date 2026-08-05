# summary: julia read/write codegen

started: 2026-07-23T11:09
held: 2026-07-25T12:42:43+12:00
closed: 2026-08-05T12:09:03+12:00

> **Closed without completing its plan, and closed deliberately rather than
> resumed.** One of eight phases was executed. The session was put on hold after
> phase 1 pending a driver study; that gate was satisfied a week later, but by
> then the 0.3.0 re-baseline had removed most of the premises the plan rested
> on. `goal.md` was superseded in place on 2026-08-04 and this session closed on
> 2026-08-05, by session
> `20260801-1257-v0.3.0-direction-doc-and-repositioning` (phases 4 and 5).
>
> **Codegen is not abandoned — it restarts as a fresh session.** It is item R14
> in [`docs/roadmap-0.3.0.md`](../../../docs/roadmap-0.3.0.md), which names what
> to mine from here.

## goal

Make dbdict generate Julia code, as the first language target: a
`crates/dbdict-julia` generator consuming the resolved model, emitting readers
and writers for dict-described DuckDB tables so a Julia user gets correctly
typed data without hand-writing boilerplate or re-deriving the schema.

The design turned on a **per-language companion mapping file**
(`DBNAME.dbdict-jlmap.yaml`) carrying `type_declarations:` and scoped
`type_mappings:` under a closed-world rule, so that the dataspec itself stayed a
pure database description and each target language brought its own mapping.

**That premise is gone.** Direction §7 deletes the companion file outright — the
type mapping follows from the (target database, driver) pair, so naming the
driver suffices. Compound types, which the plan treated as a core deliverable,
are out of V1. `goal.md` carries a supersession banner listing each removed
premise; its body is preserved verbatim and uncorrected, as the record of what
was tried.

## what was accomplished

**Phase 1 — capability spike.** The only phase executed. Eight Julia scripts in
`spike/` plus a pinned environment, measuring what DuckDB.jl actually does
across the read path, the three write paths, StructArrays, and storage-format
compatibility. Findings went to
[`.claude-work/notes/20260723-1530-duckdb-jl-capability-spike.md`](../../notes/20260723-1530-duckdb-jl-capability-spike.md).

> The phase's `/ws done` was never run — no insight capture, no `impl.md`
> marking, no phase commit. The hold commit carried the artifacts instead, which
> is why `impl.md` still shows phase 1 unchecked. That is an accurate record of
> the workflow, not a bookkeeping slip to repair now.

**Adversarial plan review.** A 15-finding review of the plan itself, with the
ledger in `review-decisions.md`. **Eight are settled** — 1–6 and 11 decided,
14 resolved — along with the supported/unsupported type lists. **Seven remain
`PENDING`:** 7, 8, 9, 10, 12, 13, 15.

> The hold marker records these as "decided 1-7, 11, 14 … open: 8, 10, 12, 13,
> 15". The ledger disagrees on two: finding 7 is `PENDING`, and finding 9 is
> `PENDING` but appears in neither list. The counts above are read from
> `review-decisions.md`, which that same note names as the source of truth.

**A gate that was met.** The hold named four driver-knowledge items. All four
were closed by three later sessions — `20260725-1252`, `20260727-0924`,
`20260727-1540` — which produced
[`research/duckdb-driver-jl/reference.md`](../../../research/duckdb-driver-jl/reference.md).
The spike note above is superseded by that document, which corrected six of its
claims by measurement.

## what was not accomplished

Phases 2–8 were never started: file naming and discovery, the companion-file
model in core, the `dbdict-julia` crate skeleton, primitive and nested-type
emission, the row-level API, and the round-trip integration test. No production
code was written in any crate. `impl.md` is the plan as drafted on 2026-07-23
and was never updated against the decided review findings.

## key decisions

**Hold rather than push on (2026-07-25).** User direction: understand,
benchmark and document the DuckDB.jl driver before building on it. Vindicated —
the driver work found appender failure modes and benchmark confounds that would
have been designed around silently.

**Supersede `goal.md`, do not rewrite it (2026-08-04).** Maintainer assessment:
*"even my goals were wrong."* A rewrite would have laundered a mistaken design
into a fresh-looking document and destroyed the evidence it was tried. It was
also stale in three layers already — decided findings never batch-edited in,
five findings never decided, then the re-baseline — so a rewrite would have
produced a fourth state matching none of the three records. The banner names
which premises died; the body is byte-identical.

**Close rather than stay held (2026-08-05).** A hold asserts "will resume".
Maintainer: *"codegen gets its own session, needs a fresh new look."* Since the
banner and the hold note were already truthful, the session's *status* was the
last inaccurate thing about it. Closing is what makes `/ws list` agree with the
documents.

## open items carried forward

All of these live in [`docs/roadmap-0.3.0.md`](../../../docs/roadmap-0.3.0.md)
R14 — this session's ledger is not the place to look for them.

- **Four V1-agnostic findings, still undecided:** 8 (identifier safety),
  10 (`dbdict gen julia` output model), 13 (a verify step naming a `dbdict
  validate` subcommand that did not then exist), 15 (primary-key phrasing).
- **Two dissolved by V1:** 7 and 12, both companion-file questions. No companion
  file exists in V1, so there is nothing left to decide.
- **One unclassified:** finding 9. Its StructArrays half is moot with compound
  types out of V1; its mixed-table tier-logic half is not.
- **`review-decisions.md` is partly moot and was not reconciled.** Findings
  resting on `TIMESTAMPTZ`, "all dict-expressible types" and companion pairing
  rest on premises V1 removed. Flagged, deliberately unresolved — reconciling it
  belongs to whoever authors the new goal.

## insights captured

- [`.claude-work/insights/20260725-1242-julia-codegen-and-duckdb-driver-insights.md`](../../insights/20260725-1242-julia-codegen-and-duckdb-driver-insights.md)
  — planning-stage sourcing for external-tool facts, and the DuckDB.jl findings
  that survived into the driver work

Captured at the hold, via `/state save`. Because phase 1's `/ws done` never ran,
this is the session's only insight file; the driver sessions that followed it
produced their own.

## state dumps

- [`.claude-work/state/20260725-1242-julia-codegen-on-hold-pending-driver-study.md`](../../state/20260725-1242-julia-codegen-on-hold-pending-driver-study.md)

## a note on this directory

`__on-hold__.md` was **archived, not deleted** — it is
[`hold-archive/20260805-1209-on-hold.md`](hold-archive/20260805-1209-on-hold.md).
The close plan said to remove it, but its 2026-08-04 section is the only record
of the gate being satisfied and the review ledger being split by cause, and both
this file and the roadmap cite it. Moving it clears the held status, which is
what closing had to achieve, without discarding the evidence.

Nothing else here changed on close. `goal.md` (banner plus verbatim July body),
`impl.md`, `review-decisions.md`, `driver-reference-handoff.md` and `spike/` are
exactly as they were.

# summary: v0.3.0 direction document and repositioning

started: 2026-08-01T12:57
closed: 2026-08-05T12:30:14+12:00

Documents-only session plus one measurement. No crate code, no schema change.
Direct continuation of `20260731-0930-revisit-app-objectives-and-goals-for-v0.3.0`,
which closed early at 2 of 6 phases; its phases 3–6 became phases 2–5 here.

## goal

Produce the public-facing direction document for the 0.3.0 re-baseline,
reposition the repo's own documents around it, and leave an ordered roadmap —
with the one load-bearing inferred claim measured first.

**All nine success criteria met** (0–8).

## what was accomplished

| # | phase | done | commit |
|---|---|---|---|
| 1 | measure `hdf5-temporal-compression` | 2026-08-02T13:45 | `094eb14` |
| 2 | the direction document | 2026-08-03T09:25 | `65bb47e` |
| 3 | reposition README, invert `CLAUDE.md` | 2026-08-03T13:24 | `8d283d0` |
| 4 | supersede the held codegen goal | 2026-08-04T10:22 | `2c211ec` |
| 5 | roadmap, triage, close, clean tree | 2026-08-05T12:23 | `9f35690` |

**Artifacts created:**

- `docs/vision-direction-0.3.0.md` — 12 sections, 16 external links across 6
  domains, 12 `[measured]` · 12 `[cited]` · 10 `Inferred:` markers, 0
  placeholders. The canonical statement of what dbdict is and what V1 covers
- `docs/roadmap-0.3.0.md` — 20 items in dependency order, each naming what it
  waits on, plus a deferred-to-V2 section and one recorded open question
- `research/hdf5-temporal-compression/` — committed probe (`probe.py` + README
  with 11 quoted-and-linked h5py API citations), so the measurement re-runs
- `.claude-work/notes/20260802-1146-hdf5-temporal-compression.md` — the result
- `README.md` and `CLAUDE.md` — repositioned; `CLAUDE.md`'s cross-backend stance
  inverted
- A closed codegen session: `20260723-1109-julia-read-write-codegen/summary.md`,
  with its `goal.md` superseded in place and its hold marker archived

## key decisions

**Measure before the document freezes the inference (phase 1).** The
*canonical ≠ physical* type decision rested on an `Inferred:` claim that HDF5
compression closes the lexical-vs-integer temporal gap. The probe ran first, with
a falsification test stated before measuring (< 8 bytes/row). **The claim held**
— 4.52–4.63 sorted, 7.43–7.51 shuffled — so nothing reopened, but three
unanticipated findings changed how §5 was written: szip cannot apply to
fixed-width string columns at all; the fair comparison is against *compressed*
`int64` (1.14–1.27×, not the raw 3.4–7.6×); and **read time, not size, is the
real cost** at 6.6–15.8×. The pre-probe phrasing appears nowhere in the document.

**Reposition, not repair (phase 3).** Goal criterion 3 demanded every claim be
true of the repo *and* of V1's scope — a conjunction that pulls opposite ways,
since `dummy` ships today but is out of V1. Resolved by making tense and scope
explicit per claim: a status banner, *what V1 covers* (links only), and *what
runs today*.

**Supersede, don't rewrite (phase 4).** The held codegen `goal.md` rested on
premises V1 removed, chiefly a per-language companion mapping file that direction
§7 deletes outright. Maintainer assessment: *"even my goals were wrong."*
Rewriting would have laundered a mistaken design into a fresh-looking document
and destroyed the evidence it was tried — and the file was already stale in three
layers, so a rewrite would have produced a fourth state matching none of the
records. Banner added, body byte-identical (40 insertions, 0 deletions).

**Close, don't hold (phase 5).** A hold asserts "will resume", now known false.
Since the banner and hold note were already truthful, the session's *status* was
the last inaccurate thing about it. Codegen returns as roadmap item R14 — a fresh
session, not a resumption.

**Standing scope line, never crossed.** `crates/`, `schema*.yaml` and `$version`
stayed out. The `decimal`/`timestamptz` divergence — 121 hits across 19 files —
is **documented as a recorded debt** in direction §11 and scheduled as roadmap
R3, not silently fixed.

**The roadmap is a sibling file, not a section.** A roadmap is re-prioritised
often; a positioning statement should not churn every time it is.

## what verification cost, and what it caught

Three of five phases had their verification *itself* fail before the work was
believed:

- Phase 1's first verdict function reduced with `min()` across all lexical
  encodings, reporting HOLDS on the strength of `date` alone — the most
  compressible column and 370× better than the binding case. **The reducer
  choice was the test design.**
- Phase 2's verify found **three unsourced quotes** by mechanical check, not by
  eye — two SQLite, one PostgreSQL — each then fetched and confirmed before a
  link was attached.
- Phase 5's overlap checker **passed on a deliberately contaminated file, twice**.
  Sentence-unit comparison is fragile at markdown boundaries. Replaced with
  12-word shingle overlap, which then found a real violation on its first run.
  Phase 3's identical invariant had been asserted, not enforced.

Three counts inherited from earlier planning documents were also wrong (six
follow-ups that are seven, four probes that are six, five pending findings that
are seven) — each a summary of an artifact rather than the artifact.

## insights captured

- [`20260802-1345-measure-before-freezing-a-spec.md`](../../insights/20260802-1345-measure-before-freezing-a-spec.md)
- [`20260803-0925-verify-scripts-encode-assumptions.md`](../../insights/20260803-0925-verify-scripts-encode-assumptions.md)
- [`20260803-1324-documentation-invariants-need-mechanical-checks.md`](../../insights/20260803-1324-documentation-invariants-need-mechanical-checks.md)
- [`20260804-1022-superseding-beats-rewriting-a-stale-record.md`](../../insights/20260804-1022-superseding-beats-rewriting-a-stale-record.md)
- [`20260805-1152-decisions-belong-in-the-plan-not-the-conversation.md`](../../insights/20260805-1152-decisions-belong-in-the-plan-not-the-conversation.md)
- [`20260805-1225-verification-units-and-inherited-counts.md`](../../insights/20260805-1225-verification-units-and-inherited-counts.md)

## known loose ends

- **`verify_phase5.py` is not committed** — it lives in a job scratch directory
  and will be lost with it. Scheduled as roadmap R16, alongside the 13 stranded
  audit scripts, rather than left as a forgotten gap.
- **`CLAUDE.md` shares one 12-word span with direction §10** (the in-process
  `PATH` guarantee). It was never inside phase 3's overlap check, which compared
  README against the direction document only. Reported and left for the
  maintainer: there is a real argument that the file agents read first should
  state that guarantee rather than link it.
- **The codegen review ledger's finding 9 is unclassified** — its StructArrays
  half is moot under V1, its mixed-table tier-logic half is not. R14 records it.

## next

Roadmap R1 — write `schema-0.3.yaml`. It gates every other code item, and
nothing in `crates/` can move until the file format is settled.

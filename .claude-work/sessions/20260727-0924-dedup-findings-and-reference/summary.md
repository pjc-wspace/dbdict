# summary: dedup findings.md and reference.md

started: 2026-07-27 09:24
closed: 2026-07-27T15:21:34+12:00

## goal

`research/duckdb-driver-jl/` carried the same driver facts in two documents, and
`reference.md` restated several internally. Reduce `findings.md` to a provenance
record, and give every driver fact exactly one authoritative home in `reference.md`
— without losing a single claim, proved mechanically rather than by reading.

This was not tidiness. It is the defect class that produced the worst bug of the
previous session: writer-tier guidance lived in two places, drifted, and the summary
table routed BLOB columns to a path the same document said never to use.

## what was accomplished

**Phase 1 — claim inventory and duplication map** (`1c6b07b`). Baseline of **1021
claims** across 59 heading contexts, coverage verified. Per-fact map of every mention
site, the `dedup-plan.md` decision table, and the enumerated unique-substantive list.

**Phase 2 — findings.md reduced to a provenance record** (`9c41371`). All six
unique-substantive items moved into `reference.md` *before* any cut. findings.md
**404 → 139 lines**: no verdicts, no tables, no code, every section pointing at its
script and its `reference.md` home.

**Phase 3 — single-sourcing within reference.md** (`a4943de`). Mention map rebuilt
rather than reused. LIST-segfault reduced from 7 prose sites to 5, `§4.4`'s example
comment cut from a three-line mechanism restatement to a pointer, `§1`'s performance
paragraphs reduced from full absolute figures to one clause plus a pointer.

**Phase 3 addendum — five internal contradictions fixed** (`d6f947e`), after the user
overrode the out-of-scope call. See key decisions.

**Phase 4 — four-pass audit, all clean** (`3da2b32`, `5e97d95`). Executable: 14 julia
blocks run, **12/12 documented outputs match exactly**. Citations: **160/160** resolve
against the installed driver source, **46/46** anchors. Consistency: the fifth
contradiction found. Inventory: **0 error strings lost**; 1 citation, 6 identifiers
and 6 numbers absent, every one enumerated.

### delta against the phase-1 baseline

| | before | after |
|---|---|---|
| findings.md | 404 lines / 256 claims | **139 lines / 94 claims** |
| reference.md | 1549 lines / 765 claims | 1617 lines / 819 claims |
| cross-file verbatim runs ≥ 120 chars | 10 | **0** |

## key decisions

**Move before cut, and it earned its place immediately.** `reference.md` §5.2.1 had
already lost findings §6's six-row literal-form table in an earlier rewrite — it
asserted "adding digits does not help" with no evidence and named the quoted-string
fix without showing it. Cutting findings.md first would have destroyed the proof
permanently.

**A phase-1 keep-decision was wrong, and was corrected rather than followed.**
`dedup-plan.md` §B kept the §5b hypotheses because "reference.md omits them". It does
not — §5.1.4 carries both in full. `goal.md` had inherited the same wrong premise and
was amended (`7bfa3a5`). The general rule now recorded: *"the other document omits
this"* is a falsifiable claim, not a conservative default.

**Scope narrowed mid-session on user direction.** `goal.md` excluded substance
rewrites, so the §8.1 tier gap was first recorded as a follow-up. The user directed
fixing it in-session. The exclusion was narrowed rather than ignored: correcting a
statement that contradicts §4.1 is in scope because it needs **no new facts** — the
matrix already held them, and the summary had merely lost a quantifier, a qualifier
or a count. New measurement stays out.

**Five contradictions, all in summary constructs.** §8.1's tier preconditions testing
one column instead of all; §1 contradicting itself in a single sentence pair; §4.4's
"only working path" for what is the only working *bulk* path; §8.1 undercounting tier
4's guards as four not six; §1 labelling a 9-item list "**The** never-emit list" where
§8.2 carries 16. None were in the sections holding evidence.

**Two of the session's own verification tools were broken, in opposite directions.**
`anchors.py` counted julia `#` comments as headings (101 against 56 real), inflating
the anchor set — a bug that can only produce a false *pass*, and it had been reporting
clean for three phases. `runblocks.py` did not strip ANSI, producing false *alarms* on
every DataFrame example. Both fixed and now in `tools/`.

## artifacts

- `dedup-plan.md` — the decision table, with §D2 (phase 3 record), §F (phase 2 cuts,
  each accounted for) and §G (the full four-pass audit results)
- `tools/` — `inventory.py`, `tokencov.py`, `crossmatch.py` (kept as evidence of a
  false trail, not for reuse), `vruns.py`, `mentions.py`, `anchors.py`,
  `citations.py`, `runblocks.py`. The audit is re-runnable against any future edit
- `notes/20260727-1306-tier-3-precondition-omits-the-bind-type-gaps.md` — **RESOLVED**

## open follow-ups

- `results.md` / `results.json` / `raw/results-*.json` remain a third layer of the
  same numbers — out of scope this session, still unreconciled
- `crossmatch.py`'s line-level approach is recorded as a false trail; do not re-run it

## insights captured

- `insights/20260727-1214-choose-the-comparison-unit-before-trusting-the-score.md`
- `insights/20260727-1257-what-a-deduplication-pass-has-to-verify.md`
- `insights/20260727-1312-verification-tools-and-fact-maps-both-decay.md`
- `insights/20260727-1519-contradictions-cluster-in-summaries-not-evidence.md`

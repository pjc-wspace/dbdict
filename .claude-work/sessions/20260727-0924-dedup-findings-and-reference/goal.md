# dedup findings.md and reference.md

## problem

`research/duckdb-driver-jl/` carries the same driver facts in two documents, and
`reference.md` also restates several of them internally.

**Cross-file.** `findings.md` (the phase-1/2 raw record) and `reference.md` (the
consolidated reference) were written one from the other. Verbatim overlap is now
only **6.4%** of `findings.md` — 7 runs over 120 characters — because the phase-3b
rewrite reworded `reference.md` wholesale. But the *conceptual* overlap is
near-total: `reference.md` §5.1.2 / §5.1.3 / §5.1.4 / §5.2.1 restate `findings.md`
§2b / §3b / §5 / §6, including the same tables, the same console transcripts and
the same conclusions in different words. Reworded duplication is the worse kind —
a text search for the duplicate will not find it, so an edit to one will silently
not reach the other.

> The recorded follow-up says "~24% of findings.md is verbatim-duplicated". That
> figure was measured against the pre-rewrite `reference.md` and is stale. The
> hazard is unchanged; only its visibility got worse.

**Intra-file.** The LIST-segfault fact appears in 12 places in `reference.md`,
about 5 of them independent prose restatements rather than cross-references.
`register_flat` appears 12 times, "1 ULP" 6 times, "3.4×" 6 times.

This is not a tidiness concern. It is the exact defect class that produced the
worst bug in the last session: writer-tier guidance lived in two places, they
drifted, and the summary table ended up routing BLOB columns to a path the same
document said never to use. Single-sourcing is the structural fix.

## success criteria

1. **`findings.md` is a provenance record and nothing else.** It keeps only what
   `reference.md` genuinely omits — the question each probe set out to answer, the
   confounds hit along the way, how far each boundary was actually pushed, and the
   harness internals a re-runner needs. It states no verdict, carries no capability
   table, and duplicates no code. A reader cannot mistake it for a source of truth.

   > **Amended 2026-07-27T12:57, phase 2.** This criterion originally also named
   > "the §5b hypotheses tested-and-rejected" as a keeper, inherited from
   > `dedup-plan.md` §B. The premise was wrong: `reference.md` §5.1.4 carries H1
   > and H2 in full, including the exact phrasing the plan cited as unique to
   > `findings.md`. Keeping them would have rebuilt the duplication this session
   > exists to remove. `findings.md` points at ref §5.1.4 instead.
   >
   > The general form, now the test for every keep decision: *"the other document
   > omits this"* is a falsifiable claim about the other document, not a
   > conservative default. Verify it the same way a cut is verified.
2. **Every driver fact has exactly one authoritative home in `reference.md`**, with
   all other mentions reduced to a cross-reference.
3. **The actionable sections still stand alone.** §1 (executive summary) and §8
   (codegen rules) may restate a fact in one clause plus a pointer — a generator
   author must not have to page back to §5 to act. Single-sourcing applies to the
   *explanation* of a fact, not to its one-line statement in an action list.
4. **No claim is lost.** A claim inventory taken before and after proves it, with
   every dropped line either present elsewhere or explicitly recorded as cut.
5. **The document is still correct and still executable**: all 14 Julia examples
   run and their documented output matches, every internal anchor resolves, and
   the four-pass audit from last session (citations · internal consistency ·
   evidence provenance · derived numbers) passes.

## scope

- **in:** `research/duckdb-driver-jl/findings.md` and
  `research/duckdb-driver-jl/reference.md` — restructuring only
- **out:**
  - the two notes files (`20260723-1530` spike, `20260725-1007` study) — already
    superseded with banners; they are historical and stay untouched
  - `results.md`, `results.json`, `raw/results-*.json` — a third layer of the same
    numbers, but out of scope this session
  - the held codegen session and any codegen work
  - **any new measurement or new driver investigation.** If a gap or a wrong claim
    surfaces, record it as a follow-up; do not go and measure it
  - rewriting `reference.md`'s substance — this is a restructuring pass, not a
    second rewrite

    > **Narrowed 2026-07-27T13:32, after phase 3 (user direction).** Phase 3's
    > consistency check found four internal contradictions, and the user directed
    > that they be fixed in-session rather than deferred. The exclusion now reads:
    > out of scope is *new substance* — new measurement, new investigation, or new
    > guidance. Correcting a statement that contradicts §4.1 is **in** scope, because
    > it needs no new facts: §4.1 already holds them, and the summary had merely lost
    > a quantifier or a qualifier in compressing them. Anything requiring a fact the
    > document does not already contain remains a recorded follow-up.

## constraints

- **Nothing may be lost silently.** Every deletion is either provably duplicated
  elsewhere or recorded in the session as a deliberate cut. This is verified
  mechanically, not by reading.
- **Verification is mechanical, not editorial.** Extract-and-run the examples,
  hash them against what was executed, resolve every anchor under both
  anchor-generation conventions, and diff the claim inventory. The last session
  demonstrated that reading a document carefully does not find its contradictions.
- Deduplication must not create a document that answers a question only by
  redirection. If following two cross-references is needed to learn one fact, the
  fact is in the wrong place.
- `reference.md` is the resumption gate for the held codegen session. It must be
  correct and usable at every commit, not just at the end.
- Environment is unchanged and pinned: DuckDB.jl 1.5.2 / DuckDB_jll 1.5.4+0,
  julia 1.12.6. No driver upgrade during this session.

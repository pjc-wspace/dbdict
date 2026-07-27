# implementation: dedup findings.md and reference.md

> workflow notes:
> - context budget rule: don't start a phase at ≥25% context — `/ws pause`,
>   fresh session, `/state load`
> - `/code-review` mandate does not apply: markdown only, no rust/production code
>   changes planned. It reapplies if any `.jl` in the research dir gets touched
> - **restructuring only.** `goal.md` puts new measurement and new investigation
>   out of scope. A gap found is a recorded follow-up, not a detour
> - the two files: `research/duckdb-driver-jl/findings.md` (19,445 chars),
>   `research/duckdb-driver-jl/reference.md` (78,029 chars, 14 julia examples)

## phases

### phase 1: claim inventory and duplication map — DONE 2026-07-27T12:14:15+12:00

Build the mechanical baseline everything else is verified against. Nothing is
deleted in this phase.

- [x] `tools/inventory.py` in the session dir — extract an atomic-claim list from
      both files: every table row, every bullet, every bolded assertion, keyed by
      `file:line` and owning heading. Output `inventory-before.tsv`
  - **also: the extractor had to be widened mid-phase.** It first counted a
    paragraph line only when it carried bold, to stop connective prose flooding
    the output. That silently dropped **459 claims** (562 → 1021), including
    findings.md §4d's path-E result and reference.md §4.3's list-field boundary,
    both stated in plain prose. An inventory used to prove *nothing was lost* must
    favour recall — precision loss is noise filtered by `kind`, recall loss is a
    claim nothing protects. Final: **1021 claims** (findings 256, reference 765)
  - also: heading coverage verified explicitly — 0 uncovered in findings.md; the
    5 uncovered in reference.md confirmed to be section containers with zero body
    lines, not extraction failures
- [x] build the **fact map**: for each distinct driver fact, its canonical home
      and every current mention site
  - result in `dedup-plan.md` §D. Worst offender LIST-segfault: **15 mentions
    across 12 sections**. Also mapped: blob `Ref{Cvoid}` (11/7), GC leak (11/7),
    misalignment (10/7), threads (10/5), `%.17e` (9/6), empty-vec (7/5),
    chunk `columnnames` (6/4), the 3.4×/538× ratios (6/4)
- [x] classify every mention as canonical / action-restatement / cross-reference
      / redundant
- [x] classify `findings.md` content against `reference.md` as duplicated /
      provenance / unique-substantive
  - **also: two comparison methods tried; the first was wrong and is recorded so
    it is not re-run.** `crossmatch.py` compared line-by-line and returned 113
    "unique" lines, nearly all false — the two files state identical facts with
    different sentence breaks, so a true duplicate scores unique because no single
    line pairs up. It was measuring line wrapping. `tokencov.py` (distinctive
    tokens: `file.jl:NNN`, backticked identifiers, C error strings, numbers)
    survives rewrapping and gave the real answer: 256 tokens, **39 absent**. It
    needed one fix — collapse whitespace both sides, or a token wrapped across a
    line break in the target reads as absent
  - **also: the unique-substantive list is NOT empty — 6 items**, and A1 is a
    real loss the phase-3b rewrite already caused: reference.md §5.2.1 dropped
    findings §6's six-row literal-form table, so it now asserts "adding digits
    does not help" with no evidence and names the quoted-string fix without
    showing it. Cutting findings.md first would have destroyed it permanently —
    the plan's move-before-cut ordering earned its place on the first phase that
    could test it
- [x] write `dedup-plan.md` — the per-fact decision table phases 2-3 execute,
      with §E as phase 4's verification contract
- **verify:** `inventory-before.tsv` covers both files with no section unaccounted
  for; every fact in the map has exactly one nominated canonical home; the
  unique-substantive list is explicitly empty or explicitly enumerated. Spot-check
  10 random claims from the inventory back to their `file:line`
  - PASSED: coverage complete (5 uncovered headings proven empty); every mapped
    fact has one nominated home; unique-substantive enumerated as 6 items;
    **10/10 spot-checks exact, 0 mismatched**

### phase 2: reduce findings.md to a provenance record — DONE 2026-07-27T12:57:22+12:00

- [x] move any **unique-substantive** content identified in phase 1 into
      `reference.md` first — findings.md must not be reduced while it is still the
      sole home of any fact
  - all six §A items landed before a single line was cut: A1 → §5.2.1 (the six-row
    literal-form table, plus a note that "reads back as" is the *Julia* type since
    the executed example prints the SQL type), A2 → §4.2, A3 → §5.1.1, A4 and A5 →
    §5.1.2, A6 → §4.5
- [x] cut everything classified **duplicated**: verdict lines, capability and
      probe result tables, mechanism explanations, the `ccall` recipe, console
      transcripts that `reference.md` reproduces, the phase-1 summary table, the
      "corrections to the driver study" list (now `reference.md` Appendix A)
- [x] keep and sharpen the provenance layer: what each probe set out to settle,
      what confounded it (the three blob payload classes; why the ENUM probe
      needed a multi-column table), and ~~§5b's two rejected hypotheses with why
      each arm was uninformative~~
  - **also: the §5b hypotheses were dropped from the keep-list — the plan's
    premise for keeping them was wrong.** `dedup-plan.md` §B claimed
    `reference.md` omits H1/H2; it does not. §5.1.4 carries both in full,
    including the "both arms were uninformative" and "underpowered, not a
    refutation" phrasing the plan cited as unique to findings.md. Keeping them
    would have rebuilt the duplication this session exists to remove, while
    looking like plan compliance. findings.md now points at ref §5.1.4.
    Recorded as a struck-through correction in `dedup-plan.md` §B —
    **note `goal.md` success-criterion 1 names them on the same wrong premise**
- [x] rewrite the header so the file's role is unmistakable — a lab notebook for
      how the findings were arrived at, explicitly not a source of truth, pointing
      at `reference.md` for every verdict
- [x] every retained section keeps its script attribution, so a reader can still
      get from "why was this probed" to the script that probed it
  - each of the six sections now opens `**Script:** <file> → **ref §N**`, so the
    hop from "why was this probed" to both the script and the verdict is one step
- **verify:** no verdict, capability table, or code block survives in
  `findings.md` that `reference.md` also carries; `inventory-after` shows every
  cut line either present in `reference.md` or listed in `dedup-plan.md` as a
  deliberate cut; the two files share no verbatim run over 120 chars
  - PASSED. findings.md: **0 code fences, 0 table rows, 0 verdict lines**.
    Verbatim runs: **0 at ≥120 chars**. Loss check: **39 → 7** absent tokens, all
    seven accounted for in `dedup-plan.md` §F. Sizes: findings.md 404 → 139 lines
    (256 → 94 claims), reference.md 1549 → 1593 lines (765 → 800 claims)
- also: **`tools/vruns.py` added** — exact shared-substring search over
  whitespace-normalized text, which is what "no verbatim run over N chars"
  literally asks; no similarity threshold to argue about. Phase 4's contract needs
  it too. Tightening it past the planned 120 to 60 caught a **78-char run this
  rewrite had itself introduced** (an out-of-scope sentence restated from §5.1.4
  while writing findings §5), now cut — final state is 0 runs at ≥60
- also: the loss check was run in the only direction that answers the question —
  **pre-cut findings.md vs `findings.md + reference.md` concatenated**. Comparing
  the two current files would score a claim deleted from both as consistent
- also: one gap acted on rather than merely recorded, since it was a citation fix
  inside scope — reference.md §5.2.1 identified `sqllit(::AbstractFloat)` only as
  "the `%.17e` method at line 32"; now named and cited as `bench_common.jl:32`
- also: guards confirming the edits stayed inside their blast radius —
  reference.md's **14 julia blocks are byte-for-byte unchanged** (sha256 per block
  diffed against `HEAD`), and **45/45 internal anchors resolve** against 101
  headings, including the two cross-references added by the moves

### phase 3: single-source facts within reference.md

- [ ] for each fact in the map: keep the canonical explanation, reduce every
      **redundant** site to a cross-reference
- [ ] preserve the standalone contract from `goal.md` §3 — §1 and §8 keep a
      one-clause statement plus a pointer. A generator author must still be able
      to act from §8.2 alone without paging back to §5
- [ ] check the reverse failure mode the goal warns about: no fact should now
      require following two hops to reach. If a cross-reference points at a
      cross-reference, the canonical home is in the wrong section
- [ ] re-check the sections most likely to drift apart — the §4.1 capability
      matrix, §8.1 tiers, §8.2 rules — since that trio is where the BLOB
      contradiction came from. They must agree row for row after the pass
- **verify:** each mapped fact has exactly one full explanation; every remaining
  mention is a pointer or an allowed action-restatement; §4.1 / §8.1 / §8.2 agree;
  no two-hop lookups

### phase 4: verification and close-out

The four-pass audit from last session, run over the combined result. This phase
exists because the last session proved that reading a document carefully does not
find its contradictions.

- [ ] **pass 1 — executable**: extract all julia blocks, run every one, diff
      actual output against documented output, hash the blocks against what ran
- [ ] **pass 2 — citations**: re-resolve every `file:line` against the installed
      driver source; re-resolve every internal anchor under both anchor-generation
      conventions
- [ ] **pass 3 — internal consistency**: §4.1 vs §8.1 vs §8.2 vs §1's never-emit
      list; grep every absolute (`never`, `every`, `always`, `only`, `no cell`)
      and check it against the data
- [ ] **pass 4 — inventory diff**: `inventory-before.tsv` vs `inventory-after.tsv`
      — prove no claim was lost. Every delta is accounted for in `dedup-plan.md`
- [ ] record any gap found as a follow-up rather than fixing by measurement
      (`goal.md` scope)
- **verify:** all four passes clean; both files committed; line-count and
  duplication delta reported against the phase-1 baseline

> optional, user's call at phase 4: dispatch an adversarial reviewer over the
> result, as in the last session. Not planned in — it is a user decision, and the
> last one cost real time. Worth it only if phase 3 turns out to have moved a lot
> of text.

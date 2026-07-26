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

### phase 1: claim inventory and duplication map

Build the mechanical baseline everything else is verified against. Nothing is
deleted in this phase.

- [ ] `tools/inventory.py` in the session dir — extract an atomic-claim list from
      both files: every table row, every bullet, every bolded assertion, keyed by
      `file:line` and owning heading. Output `inventory-before.tsv`
- [ ] build the **fact map**: for each distinct driver fact, its canonical home
      and every current mention site. Seed from the known repeat offenders —
      LIST-segfault (12 sites), `register_flat` (12), "1 ULP" (6), "3.4×" (6),
      `Ref{Cvoid}`, column-misalignment, GC-leak, `columnnames` `(:tbl,)` — then
      sweep for others rather than assuming that list is complete
- [ ] classify every mention as one of: **canonical** (the one full explanation),
      **action-restatement** (allowed in §1/§8 — one clause plus a pointer),
      **cross-reference** (already just a pointer), or **redundant** (to cut)
- [ ] classify `findings.md` content against `reference.md`: **duplicated**
      (conclusion already stated there), **provenance** (probe question, confound,
      rejected hypothesis — to keep), or **unique-substantive** (a fact that
      exists *only* in findings.md — flag loudly; it must move to reference.md
      before findings.md is reduced)
- [ ] write `dedup-plan.md` in the session dir: the per-fact decision table the
      next two phases execute
- **verify:** `inventory-before.tsv` covers both files with no section unaccounted
  for; every fact in the map has exactly one nominated canonical home; the
  unique-substantive list is explicitly empty or explicitly enumerated. Spot-check
  10 random claims from the inventory back to their `file:line`

### phase 2: reduce findings.md to a provenance record

- [ ] move any **unique-substantive** content identified in phase 1 into
      `reference.md` first — findings.md must not be reduced while it is still the
      sole home of any fact
- [ ] cut everything classified **duplicated**: verdict lines, capability and
      probe result tables, mechanism explanations, the `ccall` recipe, console
      transcripts that `reference.md` reproduces, the phase-1 summary table, the
      "corrections to the driver study" list (now `reference.md` Appendix A)
- [ ] keep and sharpen the provenance layer: what each probe set out to settle,
      what confounded it (the three blob payload classes; why the ENUM probe
      needed a multi-column table), and §5b's two rejected hypotheses with why
      each arm was uninformative
- [ ] rewrite the header so the file's role is unmistakable — a lab notebook for
      how the findings were arrived at, explicitly not a source of truth, pointing
      at `reference.md` for every verdict
- [ ] every retained section keeps its script attribution, so a reader can still
      get from "why was this probed" to the script that probed it
- **verify:** no verdict, capability table, or code block survives in
  `findings.md` that `reference.md` also carries; `inventory-after` shows every
  cut line either present in `reference.md` or listed in `dedup-plan.md` as a
  deliberate cut; the two files share no verbatim run over 120 chars

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

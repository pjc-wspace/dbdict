# summary: benchmark result reconciliation and clarity

started: 2026-07-27T15:40
closed: 2026-07-31T07:03:20+12:00

## goal

Verify that `reference.md` §7 — the one section of a document declared
"audit-clean" that no audit actually covered — matches the measurements in
`raw/*.json`, and make §7 readable as an *answer* rather than four dense tables.

**Scope was widened twice by code review.** A review found two *measurement
confounds* rather than transcription errors: reads were benchmarked with every
1M-row write table still resident, and `stream_first` abandoned thousands of
DuckDB result handles per cell. §7 could have been made perfectly faithful to
`raw/*.json` and still have described the wrong experiment. The user directed
fixing the confounds and re-running, so "reconciliation" became *transcribing a
fresh measurement* rather than correcting an old one.

## the headline result, and it is not the one the session set out to find

**§7's hand-transcription was already correct.** 142 of 142 claims verified
against the original data, every one proven genuinely compared by mutation
testing. The founding suspicion was wrong.

**The defect was one level up, in the measurement.** And when the harness was
repaired and re-swept:

```
cells compared:            48
orderings unchanged:       41
orderings MOVED:            0
```

**Every absolute number in §7 changed; no ranking did.** Rankings are
ratio-invariant to a confound that hits all three read paths proportionally.
§8.1's writer tiers — and therefore the held codegen session's contract — were
never at risk. Independent corroboration: every allocation count and memory
figure survived the re-sweep untouched, because allocs and bytes are properties
of what the code *does*, while the confounds were about what contended for the
machine.

## what was accomplished

| Phase | Outcome |
|---|---|
| 1 | ground-truth loader (`bench.py`) + §7 claim inventory; every §7 line containing a digit accounted for |
| 2 | *(added by amendment)* two confounds fixed, twelve harness bugs fixed, sweep re-run — **three times**, because the first repair was applied to only one of three read modes |
| 3 | `numbers.py` checker, proved by mutation; found two bugs **in itself** that would have reported a correct document as wrong |
| 4 | §7 re-transcribed against the 12-run sweep; 91 claims corrected; a third checker bug found by the phase's own verify criterion |
| 5 | repeat-collapse disclosed in `run_all.jl`'s generated header and in §7.1 |
| 6 | §7.0 plain-language summary with 17 new machine-verified ranking claims |

Coverage went **138 → 142 → 159** and never silently dropped. The once it did,
the criterion caught it.

## success criteria

All thirteen met. Three were exceeded rather than merely met:

- **#4** promised the two restatements outside §7 would agree. The checker found
  **four** sites, not two — §1, §7.2, §8.1, and the Driver study appendix. The
  plan had guessed §1/§4.1/§8.1/§8.2 and was wrong about half of them.
- **#10** asked for four runs present with no crashed probe and no cell
  unchecked. Delivered **twelve** runs — 6 repeats at *both* thread counts —
  with 0 crashed probes and 0 unchecked.
- **#12** asked that any moved ordering be traced into §8.1, since a tier change
  is a codegen-contract change. **Zero moved**, which is the strongest possible
  form of that criterion being satisfied.

**#13** — the pre-existing raw JSON remains recoverable at
`git show 048cfc2^:research/duckdb-driver-jl/raw/<f>.json`, and this summary
records explicitly that **§7 now describes a different experiment from the one
the previous session certified**: same code paths, same profiles and scales, but
measured on a clean database with symmetric bounded result teardown, and reported
from a 12-run sweep rather than a 4-run one.

## key decisions

- **Compare numerically within last-displayed-digit tolerance**, never by
  re-rendering strings. Re-implementing `prettytime`/`format_bytes` from memory
  is the sourcing failure the project rules forbid. The tolerance also does real
  separating work: `1.653` passes as `1.7` while `3.58` fails as `3.4` — the
  first is drift, the second means the document is wrong.
- **Transcribe from the regenerated `results.md`**, which is mechanically
  produced and independently re-derived from raw by `bench.py`, rather than
  hand-rendering the checker's nanoseconds.
- **Mutation testing over fixture files**, because the failure that burned two
  earlier audit tools was a claim *parsed and counted but never compared*.
- **Clear-and-resweep rather than appending repeats** — mixed provenance in
  `raw/` is what the new mtime-spread guard flags as dangerous.
- **`PARALLEL_1T` capped at 2.** "No measurable contention" was established for
  *two* concurrent 1-thread runs and never for more. Six repeats therefore run
  as three sequential pairs. Raising it requires a measurement.
- **Brace notation `stream_first < {materialized, streaming}`** for pairs the
  sweep does not order. The three-way ordering would have been *false* — six of
  the seven unstable read cells are those two trading places. The collapsed view
  only looks totally ordered because collapsing picked one repeat.
- **§7.5 renumbered, not restructured.** The fastest-path-vs-full-ordering split
  reporting needs new checker coverage, so it landed in phase 6's remit rather
  than being asserted unchecked in phase 4.
- **`mismatches.md` Part 2 was superseded, not followed.** Four of its rows were
  falsified by the 12-run sweep; acting on it would have written false statements
  into `reference.md`.

## the transferable finding

Phase 4's verify criterion — *"coverage count unchanged; a drop means claims went
missing rather than getting fixed"* — caught a bug nobody knew existed.
`numbers.py` located ratio claims by searching for the **literal claimed value**
(`r"3\.4×"`), so *correcting* a number made the claim disappear rather than
re-check. The run reported clean with five claims silently unchecked.

**`--selftest` cannot catch that.** Mutation perturbs claims the checker *found*;
it says nothing about claims that vanished. A verification tool needs two
orthogonal guards:

| Guard | Catches |
|---|---|
| mutation / perturbation | a claim parsed and counted but never *compared* |
| coverage-count delta | a claim that stopped being *found* |

The same lesson recurred in phase 6: string mutation exercised only the
set-equality half of each ranking claim, so three targeted negative tests were
written for the ordering half that mutation could not reach.

## insights captured

- `.claude-work/insights/20260729-0859-a-partial-fix-to-a-benchmark-is-worse-than-none.md`
- `…/20260730-1111-repeat-counts-change-what-a-benchmark-can-claim.md`
- `…/20260730-1715-coverage-delta-and-mutation-catch-different-tool-bugs.md`
- `…/20260730-1726-filename-sort-silently-picks-which-numbers-ship.md`
- `…/20260731-0651-notation-should-be-as-precise-as-the-measurement.md`

## follow-ups carried forward

**Not done, and deliberately so:**

1. **`/code-review` on three code changes** — `numbers.py`'s pattern fix
   (phase 4), `run_all.jl`'s header edit (phase 5), and `numbers.py`'s ~70-line
   ranking extractor (phase 6). The last is the largest code change of the
   session and the only one whose correctness rests on negative tests written by
   the same author as the implementation. **This is the highest-value item here.**
2. **Promote the nine audit tools** from closed session dirs to `RES/tools/`,
   next to the document they audit.
3. **Measure prepared bind (tier 3) and per-row INSERT** to close the
   four-measured-vs-five-tiers gap that §7.0 now discloses. Needs a sweep.
4. **Memory-figure tolerance is coarser than last-displayed-digit** — §7.3's
   `59.143 MiB` passed against a true `59.137 MiB` (6,293-byte gap where three
   decimals of MiB imply ±524 bytes). Corrected by hand; the tolerance is
   unchanged.
5. **Allocations-column mislabel**, two instances — §7.2's `1.705 GiB` cell and
   §7.3's "the allocation columns are near-identical (58.541 vs 59.137 MiB)".
   Both are memory figures in a column the header calls *allocations*.
6. **`1t · read · struct · 1M` is genuinely marginal** — labelled unstable, then
   stable, then dominant-5/6 across three sweeps. Report its distribution, never
   a stable/unstable verdict.
7. **The layering question this session deliberately left alone** — whether
   `results.md` should be demoted the way `findings.md` was.

## final state

```
numbers.py    159 verified · 17 ranking · 0 vacuous · 0 FAILED
  --selftest  159 mutated · 0 survived
bench.py      results.md agrees with raw on every value
runblocks.py  14 clean · 0 failing
citations.py  160 resolved · 0 unresolved
anchors.py    57 links · 58 headings · 0 unresolved
vruns.py      0 shared verbatim runs
```

Commits: `048cfc2` `01f0df7` `04c0482` `1aeacfd` `cbcd8bf` `4e82991` `2769930`
`48705b3`.

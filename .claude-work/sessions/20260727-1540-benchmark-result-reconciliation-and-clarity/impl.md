# implementation: benchmark result reconciliation and clarity

Six phases. Phase 1 builds and proves the tooling, phase 2 repairs the harness
and re-measures, phase 3 builds the checker, phase 4 spends it, phases 5–6 do the
clarity work and extend the tooling to cover it.

The clarity work is split because the two halves have different risk: phase 5
changes **how the numbers are described** without changing any of them and
touches a code generator; phase 6 adds **new prose making new claims** and new
checker coverage. Bundling them would put a mechanical diff and a
summary-construct — the thing that has produced every defect in this document —
behind a single review.

All paths relative to the repo root. Session dir abbreviated `SESS/` =
`.claude-work/sessions/20260727-1540-benchmark-result-reconciliation-and-clarity/`.
Research dir abbreviated `RES/` = `research/duckdb-driver-jl/`.

## established before planning

Read from `RES/run_all.jl:114-205` and the raw JSON, so the plan does not
guess at them:

- **Cell schema** — `cells[]` with `kind` (write|read), `profile`
  (flat|rich|struct|list), `scale` (10000|100000|1000000), `path`
  (appender|register|register_flat|literal|materialized|streaming|stream_first),
  `status` (ok|skipped). `ok` cells add `median_ns`, `min_ns`, `samples`,
  `allocs`, `memory_bytes`, `rows_per_sec`; `skipped` cells add `reason`.
- **Thread count** is `environment.threads`, not a top-level field.
- **The collapse rule** (`run_all.jl:163,172-174,288-290` after the phase-2
  harness repair; `131,140-142,186-188` before it): sort `raw/*.json`
  **by filename**, group by `environment.threads`, `vcat` each group's cells,
  keep the **first occurrence per path**. Filename sort makes that the `-a`
  repeat — but only because of how the tags were named.
- **Rendering** — `BenchmarkTools.prettytime` for times, `Base.format_bytes`
  for memory, `round(Int, ·)` for rows/s and allocs.
- `results-t1-a.json` has exactly 60 `ok` / 24 `skipped` cells.

> Decision — the checker compares **numerically within last-displayed-digit
> tolerance**, not by re-rendering strings. Re-rendering would mean
> reimplementing `prettytime` and `format_bytes` in Python from memory, which
> is the sourcing failure mode the project rules forbid; and string-exactness
> is not the property under test. `2.051 ms` is verified as
> `|median_ns − 2_051_000| ≤ 500`. Cost: a rendering bug that preserves value
> would pass. Accepted — that is a cosmetic defect, not a wrong number.

## phases

### phase 1: ground truth loader + §7 claim inventory — DONE 2026-07-29T08:59:04+12:00

Establish what is true before touching anything that states it.

- [x] **Baseline regeneration check.** With `RES/results.md` and
      `RES/results.json` committed and clean, run
      `julia --project=. run_all.jl merge` in `RES/`, then `git diff`.
      Expected: empty. A non-empty diff means the committed `results.md` is not
      what today's generator produces — that is a **finding**, and it stops the
      phase until explained. Restore with `git checkout -- results.md results.json`
      either way.
- [x] Write `SESS/tools/bench.py` — loads `RES/raw/*.json` into a dict keyed
      `(threads, kind, profile, scale, path)`. Exposes two views: `collapsed`
      (the first-run-per-path rule above, i.e. what `results.md` reports) and
      `all_runs` (every repeat, needed for §7.5's stability claims).
- [x] Add `bench.py --check-results-md RES/results.md` — re-derives every
      numeric cell of `results.md` from the JSON via the `collapsed` view and
      reports mismatches. This validates the loader against a target that is
      already mechanically correct, before it is ever pointed at hand-written
      prose.
- [x] Write `SESS/inventory.md` — every number-bearing claim in `reference.md`
      §7 plus the §1 and §8.1 restatements, one row each: location (line),
      the claim as written, its kind (table cell · derived ratio · count ·
      ordering · environment), and whether it is machine-checkable. Anything
      marked not-checkable carries the reason.
- [x] Cross-check the inventory for completeness mechanically: every line in
      §7 containing a digit is either represented in the inventory or listed
      in an explicit ignore set (section numbers, source `file:line` cites,
      anchor links). No line is silently unaccounted for.

- **verify:**
  - baseline regeneration diff is empty (or the discrepancy is understood and
    recorded before proceeding)
  - `bench.py --check-results-md` reports **0 mismatches** and prints the
    count of cells checked; that count equals the number of value-bearing rows
    in `results.md`'s four tables
  - the §7 digit-line reconciliation leaves 0 unaccounted lines
  - `/code-review` on `bench.py`

### phase 2: harness repair and re-sweep — ADDED 2026-07-28 — DONE 2026-07-29T08:59:04+12:00

Inserted after phase 1 by the scope amendment in `goal.md`. Phase 1's tooling
survives unchanged; what changes is the data it will be pointed at.

- [x] **Confound B1** — `run_all.jl`: reads get a fresh database. The write
      sweep's `w_*` tables were never dropped (`CREATE OR REPLACE`, no scale in
      the name), so reads ran against the 1M-row leftovers.
- [x] **Confound B2** — `bench_read.jl`: `read_first_chunk` closes its
      `QueryResult` in a `try/finally`. Sourced: `StreamResult` is a type tag
      (`DuckDB.jl:16`), `execute` returns a `QueryResult`, and
      `DBInterface.close!(q::QueryResult)` is `result.jl:766`. Closing in
      BenchmarkTools' `teardown` was rejected — the core compiles to its own
      `@noinline` function (`execution.jl:646-666`) so its locals are not in
      teardown's scope, and reaching the result would mean depending on the
      internal `__return_val` binding.
- [x] **Harness 1** — `run_all.jl`: `success(p)` instead of `p.exitcode == 0`.
      Verified on this machine that a signal-killed child reports
      `exitcode=0 termsignal=11 success=false`.
- [x] **Harness 2** — probe output captured to `logs/` instead of `devnull`,
      and reported as "ran"/"CRASHED" rather than "pass"/"FAIL". These are
      observational probes; several deliberately record broken behaviour, so
      "pass" was never the right word.
- [x] **Harness 3** — ordering stability reports "not checked" when a cell has
      fewer than two runs, instead of vacuously "yes".
- [x] **Harness 4** — `run_sweep.sh`: `wait $pid` and `echo` as separate
      statements, so `set -e` sees a failed run.
- [x] **Harness 5** — environment drift between runs is now a hard error, and
      the verification table reports all four runs rather than the first.
- [x] **Harness 6** — cells outside the current `PROFILES`/`SCALES` warn
      instead of vanishing while still feeding ordering stability.
- [x] Smoke test at scale 1000; stale-run warning confirmed to fire.
- [x] Full sweep re-run, merge, and record which orderings moved.
- also: a SECOND code review found the confound fix was applied to only one
      of three read modes, making the comparison worse rather than better.
      All three read modes now close their `QueryResult`, and fixtures are
      dropped between cells. **A third sweep was required.** Six further
      harness bugs fixed: `unchecked` now reaches exit status, verification
      table unions across runs, env drift no longer raises a bare KeyError,
      `logs/` un-ignored, and the stale-cell warning's false justification
      corrected (out-of-range cells feed neither loop) and replaced with an
      mtime-spread check for the hazard that is real.
- also: `orderings.py` was written for criterion 12 and is the fourth tool.

- **verify:**
  - all four `raw/results-*.json` present; merge reports 0 crashed probes
  - merge reports **0 cells unchecked** for stability
  - `bench.py` re-validates the regenerated `results.md` against the new raw
    JSON — the loader is data-independent, so this must still pass
  - the old-vs-new ordering comparison is written down, with any §8.1-relevant
    change called out
  - `/code-review` on the harness diff

### phase 3: the checker, proved by mutation — DONE 2026-07-29T08:59:04+12:00

The tool that criterion 1 asks for, plus the guard that makes its clean run
mean something.

- [x] Write `SESS/tools/numbers.py reference.md RES/raw` — parses and verifies:
      - §7.2 write table — median · rows/s · allocs per cell, and that every
        ❌ / `n/a` / `excluded` marker corresponds to a `skipped` cell with a
        matching reason class
      - §7.3 read table — medians
      - §7.4 thread table — both values per row plus the stated change
        (`7.4× slower`, `~unchanged`, `7% faster`)
      - §7.5 — the reproduced/total counts, against the `all_runs` view.
        **Correction (phase 4):** this step originally also claimed the named
        non-reproducing cells and the cross-config write ordering difference
        were verified. They are not. `extract_stability`
        (`tools/numbers.py:377-414`) emits exactly four claims, matched off two
        fixed sentence forms — the `order 4` in the coverage breakdown is those
        four counts. §7.5's tables are hand-verified against `stability.py`
      - §7.1 — coverage counts (84 cells/run, 4 runs, 60 measured, 24 skipped,
        0 failed, 9 `register_flat` skips per run), thread configs, scales,
        repeat count
      - derived ratios in §7 prose — 3.4×, 538×, 328×, 304×, ~8 allocs/row,
        ~20 allocs/row, 1.705 GiB, 246 µs → 420 µs / 1.7×, 58.541 vs
        59.143 MiB, ≤7%
      - the §1 and §8.1 restatements
- [x] Output is per-claim `PASS`/`FAIL` with the location, the claimed value
      and the derived value, ending in a coverage line: claims parsed, claims
      verified, claims failed.
- [x] Add `numbers.py --selftest` — **mutation test**. For each claim the
      checker says it verified, perturb the parsed value and re-run that
      comparison; the perturbation must produce a `FAIL`. Any claim whose
      mutation survives is reported as *parsed but never compared* — a checker
      bug, not a document result.
- [x] Run against the live `reference.md` (now carrying phase 2's fresh
      numbers). Record the mismatch list in
      `SESS/mismatches.md`. **Do not fix anything in this phase** — the
      inventory and the checker must be trusted before their output is acted on.
- also: running the checker found two bugs IN THE CHECKER that would have
      reported a correct document as wrong — a wrong percentage denominator
      ((t1−t64)/t1, not /t64) and a byte-unit value in the allocations
      column. Against the ORIGINAL data §7 verified 142/142 with zero
      failures: the hand-transcription was already correct.

- **verify:**
  - `--selftest` catches **100%** of claims; the report states the count
  - a second, independent negative test: hand-edit one known-good §7 number in
    a scratch copy and confirm `numbers.py` fails on exactly that claim
  - the real run completes and its mismatch list is written to disk
  - `/code-review` on `numbers.py`

> Why mutation testing rather than a fixture file: last session two audit tools
> were broken in opposite directions and both reported clean. The specific
> failure mode is a claim that gets *parsed and counted* but never *compared* —
> which inflates the coverage number while checking nothing. A fixture with
> known-wrong values catches a tool that is wholly broken; mutation catches a
> tool that is broken per-claim, which is the shape the previous failures took.

### phase 4: corrections — DONE 2026-07-30T17:15:19+12:00

- [x] For each entry in `SESS/mismatches.md`: correct `reference.md` from the
      raw JSON, or record it as a follow-up with the reason it was not
      corrected. Every correction cites which cell of which run it came from.
- [x] Trace every correction into the defect quartet — §1, §4.1, §8.1, §8.2 —
      and into §7.6. A corrected number that a summary construct still quotes
      at its old value is the exact defect class of the last two sessions.
- [x] If a mismatch turns out to be a *reasoning* error rather than a
      transcription error (the ratio was computed from the wrong pair of
      cells, say), note it separately — it may invalidate a conclusion, not
      just a figure.

- also: **the 12-run sweep landed first** (6 repeats at BOTH thread counts,
      11:07–12:35), so phase 4 corrected against that rather than the Jul 29
      data. Headline: `orderings MOVED: 0` vs the original pre-repair snapshot —
      every §7 number changed, no ranking did. The 1-thread question is closed:
      `1t·read·struct·10k` is unanimous at n=6, so its n=2 split was an
      artefact. Recorded as a fourth section in `ordering-delta.md`.
- also: **`mismatches.md` Part 2 was stale and four of its rows were false**
      (notably "the two moved orderings" — zero moved; and "all instability is
      now at 64 threads" — two 1-thread cells are dominant 5/6). Acting on it
      would have written false statements into `reference.md`. Superseded by
      Part 3 rather than followed.
- also: the quartet's fourth site is the **Driver study appendix**, not §4.1 or
      §8.2 as this plan guessed. The checker's line numbers, not the plan, are
      authoritative for restatement sites.
- also: **a checker bug was found by this phase's own verify criterion.**
      `extract_ratios` hardcoded the claimed values (`r"3\.4×"`), so correcting
      a number made the claim *disappear* rather than re-check — coverage fell
      142 → 137 while the run still reported clean. `--selftest` cannot catch
      this: mutation only perturbs claims that were found. Fixed at
      `tools/numbers.py:361-379` with generic value slots anchored on
      surrounding words. Full write-up in `mismatches.md` Part 4.
- also: §7.5 was **renumbered, not restructured.** `extract_stability` matches
      two fixed sentence forms, so the fastest-path-vs-full-ordering split
      reporting moves to phase 6, where prose and coverage land together. §7.5
      states no unchecked `23 of 24`.
- also: three §7.1 methodology disclosures added (symmetric bounded result
      close, per-cell fixture drops, fresh read database with its null result),
      and one broken anchor introduced-then-fixed (`anchors.py` collapses
      whitespace runs to a single hyphen, so an em-dash heading yields
      `-1-thread`, not `--1-thread`).

- **verify:**
  - `numbers.py reference.md RES/raw` → 0 FAIL, coverage count unchanged from
    phase 2 (a drop means claims went missing rather than getting fixed)
    — **142 verified · 16 derived · 0 vacuous · 0 FAILED; `--selftest` 142
    mutated, 0 survived**
  - the four existing audits still pass, run from the closed session's tools:
    `runblocks.py`, `citations.py`, `anchors.py`, `vruns.py`
    — **14 clean/0 failing · 160 resolved/0 unresolved · 0 unresolved anchors ·
    0 shared runs**
  - every follow-up is written down, not just mentioned
    — **four in `mismatches.md`, plus this plan's own correction at the §7.5
    checker-scope line**

### phase 5: repeat-collapse disclosure — DONE 2026-07-30T17:26:49+12:00

Mechanical. No number changes; one generator edit and one sentence.

- [x] **Disclosure in `results.md`** — edit the header `println` block at
      `run_all.jl:177-180` (the plan said `146-148`; the phase-2 harness repair
      shifted it), stating that absolute times are one repeat (the first by
      filename order), that the other repeats feed only the stability table,
      and that the tag naming is what makes it the `-a` run.
      Regenerate. **The resulting diff must be header-only.**
- [x] **Same disclosure in `reference.md` §7.1**, one sentence, phrased for a
      reader who will never open `run_all.jl`.

- also: the disclosure interpolates `$(length(runs))` rather than hardcoding a
      repeat count, so it stays true when the sweep size changes. The plan was
      written when there were 2 repeats and said "the other repeat" (singular);
      there are now 6.
- also: added one clause the plan did not ask for — that two absolute times in
      the tables can differ by ordinary run-to-run spread, which is *why* the
      ordering rather than the magnitude is the deliverable. Without it the
      disclosure states a mechanism and leaves the reader to derive the
      consequence.
- also: `vruns.py` passing is a real check here, not a formality — the same
      fact is now disclosed in two files, which is exactly the duplication that
      gate exists to catch. It passes because the two versions address different
      readers, which is what the plan's "phrased for a reader who will never
      open `run_all.jl`" was for.
- not done: `/code-review` on the `run_all.jl` change. Flagged to the user at
      the phase boundary; not run. Carried as a follow-up.

- **verify:**
  - `git diff RES/results.md` after regeneration touches only the header block
    — **8 added lines in the header, nothing else; `results.json` byte-identical**
  - `numbers.py` → 0 FAIL, coverage count **unchanged** — this phase must not
    move a single number — **142 verified · 16 derived · 0 FAILED, unchanged**
  - `vruns.py` and `anchors.py` still pass — **0 shared runs · 0 unresolved**
  - `/code-review` on the `run_all.jl` change — **not run, see above**

### phase 6: plain-language summary — DONE 2026-07-31T06:51:38+12:00

New prose, therefore a new summary construct, therefore new checker coverage.

- [ ] **Plain-language summary opening §7**, before §7.1:
      - each measured method in one line — what it is, linking to its existing
        home (`register` §4.2, `register_flat` §4.3, `appender` §4.5,
        `literal` §4.6, `materialized` §3.3, `streaming`/`stream_first` §3.4).
        A gloss and a link, never a re-explanation
      - what was **not** measured — prepared bind (tier 3, §4.4) and per-row
        INSERT — stated plainly, with the consequence: those tier positions are
        reasoned, not measured, so §8.1's five tiers rest on four measured paths
      - how the measured methods came out, as a short ranking list in the
        `register < appender < literal` notation `results.md` already uses,
        one line per (kind, thread config) with the scale caveats inline
      - no recommendation — §8.1 keeps tier selection (criterion 8)
- [x] **Extend `numbers.py`** to parse the ranking list and verify each line
      against the `all_runs` view. Re-run `--selftest`; the new claims must be
      caught by mutation like every other claim.

- also: the ranking list is a **table**, not the "one line per (kind, thread
      config)" the plan specified. Four prose lines could not carry the scale
      caveats without an "except" clause per line, and a rigid table is far
      easier to parse reliably — which matters, because a fragile parser here
      reintroduces exactly the silent-coverage-loss bug found in phase 4. 18
      rows, 17 of them checkable.
- also: **reads use a `{a, b}` brace notation** for a pair the sweep does not
      order. Writing `stream_first < streaming < materialized` would have been
      false — six of the seven unstable read cells are `materialized` and
      `streaming` trading places. The collapsed view *looks* totally ordered
      because collapsing picked one repeat.
- also: each row asserts **two** properties — the named paths are exactly the
      ok paths measured, and the strict order holds in every repeat. Set
      equality stops a row silently omitting a measured path.
- also: the claimed value is the ordering **string**, not a parsed structure,
      so `mutate()` needed no change — appending `_mutated` yields a path name
      never measured. But that only exercises set equality, so **three targeted
      negative tests** were run for the properties mutation cannot reach:
      permute an ordering (set held identical), invert a braced group, omit a
      measured path. Each failed on exactly one claim, the right one.
- also: one wording fix on the manual read-through — "§8.1 **ranks** five
      tiers" became "**orders** five tiers, but only four carry a measurement",
      because "ranks" next to a speed table implied the tier order *is* the
      speed ranking. §8.1 orders by precondition fallback.
- also: added a line the plan did not ask for, because the table invites a
      specific misreading — where a row lists one path, the others were **not
      available** to measure, not merely slower. §4.1 named as the authority.
- not done: `/code-review` on the `numbers.py` changes. Flagged at the phase
      boundary; not run. Carried as a follow-up alongside phases 4 and 5.

- **verify:**
  - `numbers.py` → 0 FAIL, and coverage count has **risen** by the number of
    new ranking claims — **159 verified (142 + 17 ranking) · 0 FAILED**
  - `--selftest` still catches 100%, including the new claims — **159 mutated,
    0 survived**; plus three negative tests for the ordering property that
    string mutation cannot reach
  - the four existing audits still pass — in particular `anchors.py`, since
    the summary adds cross-references, and `vruns.py`, since §7 gained text
    — **57 links/58 headings/0 unresolved · 0 shared runs · 160 cites resolved
    · runblocks 14 clean**
  - read the new summary against §8.1 and §7.6 by hand: it must not state or
    imply a recommendation — **done; §7.6 states tier selection lives in §8.1
    alone and §7.0 defers to it explicitly. One phrase tightened, see above**
  - `/code-review` on the `numbers.py` changes — **not run, see above**

## follow-ups to record at close

Carried forward, not done here:

- promote all nine audit tools from closed session dirs to
  `RES/tools/`, next to the document they audit
- measure prepared bind (tier 3) and per-row INSERT to close the
  four-measured-vs-five-tiers gap — needs a sweep
- the layering question this session deliberately left alone: whether
  `results.md` should be demoted the way `findings.md` was
- anything phase 3 could not correct without a fact the document does not hold

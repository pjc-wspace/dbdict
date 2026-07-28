# code review triage — 2026-07-27

`/code-review` over 24 commits plus the in-flight tools. 15 findings, triaged by
whether they bear on this session's goal. Every claim below that I could test, I
re-tested myself rather than accepting; two came back partly overstated and are
marked.

## A. fixed in-session (my tools, phase 1)

| Finding | Status |
|---|---|
| `inventory_check.py` — an over-broad range citation (`L1000-L2000`) marked every line cited and made the check pass unconditionally | fixed: ranges may not straddle the section boundary, and both endpoints must be digit-bearing lines |
| `inventory_check.py` — `section_bounds` not fence-aware; a `## ` inside a fence cut the checked range from 76 lines to 29 and still reported OK | fixed: fences skipped, matching `anchors.py`, `inventory.py`, `tokencov.py` |
| `bench.py` — the docstring promised a row-count check that did not exist; a duplicated row passed clean | fixed: duplicate-key detection plus an explicit count comparison |
| `bench.py` — `parse_scalar` returned `None` for unparseable text *and* for the empty marker, so garbage in a cell whose raw counterpart is null was accepted | fixed: distinct `UNPARSEABLE` sentinel that fails |
| `bench.py` — comment claimed "read cells have no rows_per_sec" | **the reviewer was right and I was wrong.** `bench_read.jl:86` sets `rows_per_sec` to `nothing` for `stream_first` only; `materialized` and `streaming` carry it. The 24 both-absent cells are exactly the `stream_first` cells (4 profiles × 3 scales × 2 configs) |
| `__pycache__/` untracked and not ignored under `.claude-work/.gitignore`'s `!*` | fixed: re-excluded in that file |

The tight-endpoint guard caught five sloppy ranges in my own `inventory.md` the
moment it was added. All four of the reviewer's exploits were replayed against
the hardened tools and are blocked; the original 10-mutation suite still passes.

## A2. `anchors.py` — finding accurate, prescribed fix would have been wrong

The review was right that `one_only` is computed, printed as a bare count,
never listed and never gates exit — contradicting the docstring. But making it
fatal, as that implies, would have **failed a correct document**.

The docstring's premise does not hold for numbered headings. `### 3.4 Streaming
reads` slugs to `34-streaming-reads` under github's dot-stripping and
`3.4-streaming-reads` under the dot-preserving convention. A link can only be
spelled one way, so for numbered headings the conventions are *mutually
exclusive* and "resolves under exactly one" is the correct state — 44 of
`reference.md`'s 46 links are in it. The 2 that resolve under both point at
`Appendix A`, which carries no dotted number.

Fixed by direction instead: `github-only` (44) is expected and fine;
`dot-preserving only` is broken on github and is now **fatal**; `neither` stays
fatal. `reference.md` has **0** in the fatal class, so criterion 9 passes on
merit rather than by omission. Negative-tested by rewriting one link to the
dot-preserving form — correctly exits 1. Docstring corrected in place with a
dated note explaining why the old premise was wrong.

## B. bears on the numbers §7 is about to certify — RESOLVED: fix and re-run

User directed the widest option (2026-07-28): fix both confounds, fix all six
harness bugs, re-run the sweep. See the amendment in `goal.md` and phase 2 of
`impl.md`. Consequence: every §7 number changes, and the orderings that feed
§8.1's writer tiers may move.

Neither is a transcription error. Both are conditions under which the
measurements were taken that §7 does not disclose, so §7 can be made perfectly
faithful to `raw/*.json` and still describe the wrong experiment.

**B1 — reads are measured against a database still holding every write table.**
`run_all.jl:97` opens one in-memory connection and hands it to `bench_writes`
then `bench_reads`. `recreate_table!` is `CREATE OR REPLACE`
(`bench_common.jl:171`) and nothing drops anything; write tables are named
`w_<profile>_<path>` with no scale (`bench_write.jl:35`), so after the sweep the
1M-row versions stay resident. Reads run after all writes, so even the 10k read
cells are measured with multi-gigabyte tables in memory. Verified by reading the
source; the magnitude of the effect is not measured.

**B2 — `stream_first` abandons a `StreamResult` per sample.**
`bench_read.jl:56` takes `first(Tables.partitions(q))` and drops the rest, per
sample, leaving handles to finalizers. Time-to-first-chunk is §7.3's headline
result, so finalizer backlog inside the timed region would inflate exactly the
number the streaming case rests on.

> Reviewer said `samples = 10000` for every `stream_first` cell. **Overstated:**
> 5 of 24 cells hit the 10,000 cap; the rest run 1,278–8,841. Thousands of
> abandoned handles per cell, so the concern stands, but not universally.

## C. real, out of scope, recorded as follow-ups

| Finding | Note |
|---|---|
| `run_all.jl:78` — `ok = p.exitcode == 0` records a signal-killed verification as passing | **verified empirically on this machine**: a SIGSEGV child gives `exitcode=0 termsignal=11 success=false`. Fix is `ok = success(p)`. A segfault is a documented live failure mode here (§5.1.4) |
| `run_all.jl:76` — verify scripts never exit nonzero and their output goes to `devnull`, so "pass" only means "no uncaught exception" | the gate is decorative. Does not falsify a §7 claim — §7.1's "0 failed" counts cells, not scripts — but `results.md`'s verification table is weakly grounded |
| `run_all.jl:220` — ordering stability is vacuously true when a thread group holds one run, yet prints "All orderings reproduced" | not triggered by the committed data (4 runs, 2 per config) |
| `run_sweep.sh:30` — `wait $pid_a && echo …` swallows a failed run under `set -e` | would produce the 3-run raw set that triggers the above |
| `run_all.jl:150` — environment and verification tables built from `first(runs)` only | hides per-run drift |
| `run_all.jl:184` — cells whose profile/scale are outside the current constants are silently unrendered while still feeding the stability table | a stale smoke-run file in `raw/` would corrupt the stability column |
| `tokencov.py:31` — number regex accepts only U+00B5 and drops `×` / `%`, so `538×` is "covered" by any bare `538` | another session's tool; same µ/μ trap `bench.py` guards against |
| `anchors.py:61` — `one_only` links are counted but never listed and never gate exit status | contradicts its own docstring; goal.md criterion 9 leans on this tool |
| `literal_matrix.jl`, `read_path.jl` — byte-identical duplicates of the spike copies, and the only two Julia files here using 4-space indent | `sqllit(v::AbstractFloat)` has **already diverged** (the `%.17e` ULP fix is in `bench_common.jl:43`, not `literal_matrix.jl:34`) |

Not pursued, noted only: `tokencov.py:66` computes an unused `tgt_text` and
reads the target twice; `crossmatch.py:64-73` recomputes loop-invariant token
sets inside the inner loop.


---

# code review round 2 triage — 2026-07-29

Reviewed the harness repair plus the new session tools. 15 findings. The first
one invalidated the sweep I had just run.

## fixed in-session — harness (required a THIRD sweep)

| Finding | Resolution |
|---|---|
| **`bench_read.jl` — the confound fix was applied to only one of three read modes** | Confirmed: the sole `close!` in the harness was the one I added. `stream_first` paid a deterministic destroy inside its timed window while `materialized`/`streaming` leaked to finalizers landing in the next mode's window. Since the modes are ranked against each other, a shared bias largely cancels and a solo bias does not — **the half-fix was worse than no fix**. All three now close, verified empirically that reading values after `close!` plus two forced GCs is safe |
| `run_all.jl` / `bench_read.jl` / `bench_write.jl` — fixtures never dropped *within* a sweep | Confirmed: `r_<profile>` and `w_<profile>_<path>` carry no scale and `recreate_table!` is CREATE OR REPLACE, so late cells ran with every earlier cell's table resident. Both loops now drop |
| `run_all.jl` — `unchecked` never reached exit status or console | Now printed, returned, and a hard error in `merge` mode. `impl.md`'s "0 cells unchecked" criterion finally has a machine signal behind it |
| `run_all.jl` — verification table keyed off run 1's probe set | Union across runs |
| `run_all.jl` — environment drift raised a bare `KeyError` on a missing field | `haskey` first, with the drift message |
| `.gitignore` — `logs/` ignored while `results.md` and every raw JSON point readers at it | Un-ignored. Capturing probe output and then not shipping it was self-defeating |

**The stale-cell warning's justification was false and I wrote it.** It claimed
out-of-range cells "still feed the stability table"; both loops filter
identically on `PROFILES`/`SCALES`, so such a cell feeds neither. Corrected, and
replaced with a check for the hazard that is real — raw files whose mtimes span
hours, i.e. a leftover from an older harness that merges silently.

## fixed in-session — tools

| Finding | Resolution |
|---|---|
| `orderings.py` — `consensus()` vacuously true for a single-run group | The same bug this session had just fixed in `run_all.jl`. Guarded, and "no consensus" now splits into *repeats disagree* (a result) vs *fewer than two runs* (a gap) |
| `numbers.py` — thread count hardcoded to 64 | Derived from `environment.threads`; on another box every §7.4 claim would have failed and been reported as a document defect |
| `numbers.py` — both-absent claims counted as verified and invisible to `--selftest` | Own `VACUOUS` bucket, excluded from the verified count. Currently 0, so the hazard was latent |
| `numbers.py` — coverage mixed per-run and cross-run scope | All tallies now from one run; `skipped` counted directly rather than by subtraction, so a failure cannot be absorbed as a skip |
| `inventory_check.py` — a range *enclosing* the section was classed "outside, allowed" | Both endpoints outside meant the straddle test could not see it. Explicit enclosure check |
| `inventory_check.py` — a bad-endpoint range still marked its whole span cited | Missing `continue`; the guard reported the problem while letting it do the thing it was added to prevent |
| `anchors.py` — links scraped from raw text while headings skip fences | Both sides now read the same unfenced document; a `](#anchor)` in a markdown example no longer fails the build |
| `anchors.py` — usage line contradicted the gate I had just rewritten | Corrected to state the real contract |
| `.claude-work/.gitignore` — comment made a false causal claim | Verified independently: neither the repo `.gitignore` nor `core.excludesfile` carries a `__pycache__`/`*.pyc` pattern, so `!*` had nothing to re-include. Comment corrected — this is precisely the sourcing rule the project sets |
| stale `run_all.jl:122-129` cites in `orderings.py`, `numbers.py`, `bench.py`, `impl.md` | My own diff moved those lines. Corrected. Ironic in a repo that ships `citations.py` |

All four exploits from both reviews were replayed against the hardened tools and
are blocked.

## still open

Neither review's remaining items are done: the six pre-existing harness bugs
listed in round 1 section C that were not fixed here (`tokencov.py`'s regex,
`literal_matrix.jl`/`read_path.jl` duplication and 4-space indent) remain
recorded follow-ups.

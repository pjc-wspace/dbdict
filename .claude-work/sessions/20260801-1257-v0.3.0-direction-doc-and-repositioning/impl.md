# implementation: v0.3.0 direction document and repositioning

Documents-only session, plus one measurement. No crate code, no schema change.
Five phases, each independently committable so the session can stop at any
boundary.

**Goal:** produce the public-facing direction document for the 0.3.0
re-baseline, reposition the repo's own documents around it, and leave an
ordered roadmap — with the one load-bearing inferred claim measured first.

**Approach:** measure before writing (a surprise must land in an internal note,
not a public document); write the direction document once; then have every
other document *cite* it rather than restate it.

**Tech stack:** markdown; Python 3 via `uv` inline script metadata (h5py,
numpy) for phase 1 only. No project dependency is added.

> **Execution:** phase-by-phase in-session. At each boundary I run the
> `**verify:**` block, then `/ws done` (insight capture, mark this file,
> commit). Phases 2–5 are carried forward from the parent session
> `20260731-0930-…` and their steps were reviewed there; phase 1 is new.

## global constraints

Every phase's requirements implicitly include these. Copied from `goal.md`.

- **Evidence standard.** Every external claim about DuckDB, DuckLake, SQLite,
  HDF5, h5py, JLD2, Postgres or QuackIO carries a link to official
  documentation, or is marked `Inferred:` with its reasoning visible. No API
  name, flag, or parameter is written from memory.
- **Out of scope, hard line:** `crates/`, `schema*.yaml`, `$version`. The
  known divergence — 121 `decimal`/`timestamptz` hits across 19 files at
  `3337de5`, source as well as tests — is **documented, not closed**.
- **The type system is settled.** Authority is
  `.claude-work/notes/20260731-1552-dbdict-type-system-decisions.md`. The only
  route to reopening it is phase 1.
- **No claim lives in two files.** Later documents link to the direction
  document instead of repeating it.
- **Phase boundaries are session boundaries.** Start each phase below 25%
  context, keep under 30%.
- **Ordering is fixed:** 1 before 2; 2 before 3 and 5.

---

## phases

### phase 1: measure `hdf5-temporal-compression` — DONE 2026-08-02T13:45:05+12:00

New to this session. Settles the one `Inferred:` claim that the direction
document would otherwise freeze into a public statement.

**The claim under test**, from the decisions note §8:

> `Inferred:` that ISO-8601 columns compress to well under the integer
> encoding's raw size. Not measured. **Probe `hdf5-temporal-compression`**:
> write 10⁶ timestamps both ways, apply gzip/szip, compare on-disk bytes and
> read throughput.

**Falsification test, stated before measuring:** the claim holds iff
compressed fixed-width ASCII temporals land **below 8 bytes/row** — the raw
size of the `int64` µs encoding that was rejected. Baselines to reproduce:
`date` 10 B, `timestamp` no zone 27 B, `timestamp` zoned ≤ 61 B, `int64` 8 B.

**Files:**
- Create: `research/hdf5-temporal-compression/probe.py`
- Create: `research/hdf5-temporal-compression/README.md` (what this is, how to
  re-run, one-paragraph result)
- Create: `.claude-work/notes/{stamp}-hdf5-temporal-compression.md`
- Modify: `.claude-work/notes/20260731-1552-dbdict-type-system-decisions.md`
  — §8's `Inferred:` marker becomes `[measured]` with the figure, or the
  decision reopens
- Modify: this file, `goal.md` if the outcome falsifies anything

> The script goes under `research/` because that directory already holds
> standalone experiments (`duckdb-driver-jl`, `duckdb-examples`,
> `parquet2-as-alternative-backend`, `quackio-driver-jl`). It is **committed**:
> a `[measured]` claim that cannot be re-run is not much better than an
> inferred one. `goal.md` did not name a location — this is the one addition
> to its scope, and it is deliberate.

- [x] **Step 1: source the h5py API from h5py's own documentation.** Do not
      write any of the script first. Fetch and quote the supporting sentence
      for each of: fixed-length byte-string dtype (`S<n>`) in a dataset;
      `create_dataset` compression and `shuffle` arguments; chunking (required
      before filters apply); the API that reports **on-disk** storage for a
      dataset as opposed to its logical size; how to enumerate which filters
      the installed build actually supports. Record each with its link in the
      note as you go.
      *Why this is step 1 and not folded into the script step:* per the global
      evidence standard, none of these may be written from memory — and if the
      storage-size API turns out not to exist as assumed, the entire
      measurement design changes.

- [x] **Step 2: check filter availability, do not assume it.** `szip` is named
      in the decisions note, but its presence depends on the build. Enumerate
      what is available and record it. If `szip` is absent, say so in the note
      and proceed with the rest — its absence is a finding, not a blocker.

- [x] **Step 3: write `probe.py` as a `uv` inline-metadata script.**

```python
# /// script
# requires-python = ">=3.10"
# dependencies = ["h5py", "numpy"]
# ///
```

> Inline metadata rather than `uv run --with h5py --with numpy` (which
> `goal.md` names): same ephemeral env, nothing installed into the project,
> but the deps are pinned **inside the committed file**, so the measurement
> re-runs years later. See
> https://docs.astral.sh/uv/guides/scripts/#declaring-script-dependencies

- [x] **Step 4: generate the data — both orderings.** 10⁶ timestamps spread
      over a realistic multi-year range. Write **two** variants of every
      column: **sorted** and **shuffled**.
      *Why:* the note's own argument for the claim is that *"consecutive
      values share long prefixes"* — which is true only of sorted data. A
      probe that tests sorted columns alone would confirm the claim by
      construction. Real columns are frequently unsorted, so the shuffled
      figure is the honest worst case and the one the spec should quote.

- [x] **Step 5: run the matrix and record bytes/row per cell.**

| encoding | dtype | sorted | shuffled |
|---|---|---|---|
| `date` lexical | `S10` | ✓ | ✓ |
| `timestamp` lexical, no zone | `S27` | ✓ | ✓ |
| `timestamp` lexical, zoned | `S61` | ✓ | ✓ |
| `timestamp` int64 µs | `int64` | ✓ | ✓ |
| `date` int32 days | `int32` | ✓ | ✓ |

Filters per cell: none · gzip(4) · gzip(9) · shuffle+gzip(9) · szip *if
available*. Chunked (filters need it); state the chunk size chosen and why.
Compress the integer encodings too — the note concedes the integer form
*"would also have needed chunking to beat"*, so an uncompressed-int baseline
alone would be an unfair comparison.

- [x] **Step 6: measure read throughput** for the best-compressing lexical cell
      against the int64 cell — full-column read, wall-clock, repeated enough to
      be stable. The note asks for it explicitly. Size is not the only cost:
      a lexical column that wins on disk but loses badly on read changes the
      recommendation.

- [x] **Step 7: write the note** at
      `.claude-work/notes/{stamp}-hdf5-temporal-compression.md` — the matrix,
      the environment (h5py version, HDF5 library version, filters available),
      every h5py link from step 1, and **an explicit verdict against the
      < 8 bytes/row test**, stated for the shuffled case as well as sorted.

- [x] **Step 8: apply the outcome.**
      - *Claim holds* → in the decisions note §8, replace the `Inferred:`
        paragraph with `[measured]` plus the figure and a link to the new note.
        Nothing else changes.
      - *Claim fails* → §8 gets a struck-through correction (the parent
        session's convention: correct in place, strike rather than delete),
        the decision reopens, and phase 2's storage section writes the
        corrected story. Record the reopening in `goal.md` too.

**outcome: the claim HOLDS — the decision stands, nothing reopened.** Lexical
temporals reach 4.52–4.63 bytes/row sorted and 7.43–7.51 shuffled with
`shuffle+gzip(9)`, under the 8.0 threshold in every case. Note:
`.claude-work/notes/20260802-1146-hdf5-temporal-compression.md`.

- also: **three findings the plan did not anticipate**, all carried into phase
  2 and phase 5 —
  1. **szip cannot be applied to lexical temporal columns at all.**
     `filter_avail()` reports it present, but `H5Dcreate` rejects fixed-width
     strings: *"SZIP compression can only be used with atomic datatypes that
     are integer, float, or char"* ([HDF5 — Compressed
     Datasets](https://support.hdfgroup.org/documentation/hdf5/latest/_l_b_com_dset.html)).
     The integer encodings therefore have a filter option the lexical ones do
     not. **New capability-matrix row** for phase 2.
  2. **The fair comparison is against *compressed* `int64`, not raw.** The
     original claim tested compressed-lexical against raw 8 bytes/row. Against
     compressed `int64`, lexical costs 1.14–1.27× — a much better result for
     *canonical ≠ physical* than the raw 3.4–7.6× implied, and the figure the
     direction document should quote.
  3. **Size was never the real cost — read time is**, at 6.6× (`S27`) to 15.8×
     (`S61`). The decisions note asked for read throughput almost in passing;
     that is where the answer lived.
- also: *"well under"* (the original wording) holds for **sorted** data only.
  Shuffled clears 8.0 by just 6–7%. Phase 2 must not reuse the old phrasing.
- also: the first run **aborted** on szip rather than recording it. The script
  gained an `Unsupported` exception so a rejected (encoding, filter) pair is
  captured as a result rather than crashing the probe. This is why the verify
  below reads "no cell blank" rather than "every cell numeric".
- also: the first verdict function reduced with `min()` across *all* lexical
  encodings, which reported HOLDS on the strength of `date` (S10) alone — the
  most compressible column, and 370× better than the binding case. Replaced
  with a per-type verdict. The reducer choice was the test design.
- also: the `date` rows (0.02 sorted / 1.87 shuffled) are a **low-cardinality
  artifact** — ~1,387 distinct dates each repeating ~721 times. Flagged in the
  note; not to be generalised. The `timestamp` rows are the trustworthy ones.
- also: h5py API citations live in `research/hdf5-temporal-compression/README.md`
  (11 quoted-and-linked entries); the note links that table rather than
  duplicating it, keeping "no claim lives in two files" intact.

**verify:** — all 8 checks re-run and passing
- [x] `uv run research/hdf5-temporal-compression/probe.py` completes and prints the
  full matrix — no cell blank, no cell errored (szip×lexical cells read `n/a`
  with the rejection reason recorded beneath the table)
- the note names the h5py version, the HDF5 library version, and the filter
  list actually available on this machine
- every h5py API used in the script appears in the note with a link to h5py
  documentation — `grep -c 'h5py' note` against the API list from step 1
- the note states the verdict explicitly against `< 8 bytes/row`, for both
  sorted and shuffled
- the decisions note §8 no longer contains a bare `Inferred:` for this claim —
  it is either `[measured]` or struck through and reopened
- `research/hdf5-temporal-compression/README.md` gives the one-line re-run
  command

---

### phase 2: write the direction document — DONE 2026-08-03T09:25:23+12:00

Carried from the parent's phase 3, unchanged in substance. **The largest
phase.**

> Read `.claude-work/notes/20260731-1552-dbdict-type-system-decisions.md`
> **before** starting, not just `goal.md`. Its 15-item decision log is the
> authority on types. The 1253 capability-matrix note is the authority on
> per-target capability but is *partly superseded* and carries a banner saying
> which parts. If phase 1 reopened anything, its note outranks both.

**Files:**
- Create: `docs/vision-direction-0.3.0.md`

- [x] write `docs/vision-direction-0.3.0.md`
- [x] sections, in order: positioning · the two entry points · the two-axis
      model · invariants · dbdict type vocabulary · `attrdef:` ·
      `languages:` · metadata propagation · V1 command surface · capability
      matrix (embedded from the parent's phase 2) · what is explicitly *not*
      in V1
- [x] carry over every sourced quote and link from the parent `goal.md` — this
      document is public-facing where `goal.md` is a working record
- [x] state the round-trip property (`spec → DDL → db → draft → spec`) and
      where it is known to fail
- [x] state the compound-type deferral with **both** reasons (no neutral
      spelling; nowhere on the current stack for them to work)
- [x] in "not in V1", name the **code/document divergence** explicitly:
      `decimal(p,s)` and `timestamptz` are out of the V1 type system but are
      still implemented in `crates/`. Recorded debt, not a silent one
- [x] type vocabulary gives, per type, the bit layout (numerics, `bool`) or
      the RFC profile (temporals), plus per-target equivalents for the four V1
      targets, each cited

**split point if this will not fit one context:** positioning · two entry
points · two-axis model · invariants ‖ type vocabulary · `attrdef:` ·
`languages:` · metadata propagation · command surface · capability matrix ·
not-in-V1. Splitting commits a knowingly incomplete file at the boundary, so
the no-`TBD` check runs only after the second half.

**outcome:** `docs/vision-direction-0.3.0.md` written — 12 sections (the eleven
required, plus a short `versioning` closer), 16 external links across 6 domains,
12 `[measured]` · 12 `[cited]` · 10 `Inferred:` markers, 0 placeholders.

- also: the phase 1 measurement **changed how §5 is written**, as intended. The
  storage section quotes 4.52–7.51 bytes/row and the 1.14–1.27× compressed-vs-
  compressed ratio, and states plainly that *"well under" is true of sorted data
  only* and that **read time (6.6–15.8×), not size, is the cost being
  accepted**. The pre-probe phrasing appears nowhere.
- also: the capability matrix gained a **compression-filters row** carrying the
  szip finding — availability ≠ applicability — which did not exist in the
  parent's matrix.
- also: **three unsourced quotes found and fixed during verify**, not by
  eye — SQLite type affinity and SQLite's `"TEXT as ISO8601 strings"`
  (both → [sqlite.org/datatype3.html](https://www.sqlite.org/datatype3.html)),
  and PostgreSQL's *"stored internally as UTC"*
  (→ [datatype-datetime.html §8.5.1.3](https://www.postgresql.org/docs/current/datatype-datetime.html)).
  Each was fetched and confirmed before its link was attached, rather than
  having a plausible URL guessed for it.
- also: the HDF5 variable-length-string finding is cited **by internal
  cross-reference** to the decisions note §7, which holds the original citation,
  rather than by attaching a URL that could not be placed. Honest sourcing beat
  a tidy-looking link.
- also: criterion 7 (the dangling reference) **resolves**. Worth recording that
  it was never a markdown link — the archive note cites the path in backticks,
  so the first extraction returned empty and read as a failure. The check was
  wrong, not the artifact.
- also: `docs/roadmap-0.3.0.md` is now referenced from §11 and §10 and does
  **not yet exist** — phase 5 creates it. Same forward-reference pattern the
  archive note had; it is deliberate and closes in this session.
- also: phase 2 fit one context. The pre-identified split point was **not**
  needed.

**verify:** — all 7 checks re-run and passing
- all eleven required headings present (grep for each)
- every external claim has a link or an `Inferred:` marker — no bare
  assertions about DuckDB, DuckLake, Postgres, SQLite, HDF5, JLD2 or QuackIO
- document contains no `TBD`, `TODO`, or blank section
- the 10 dbdict types appear with their definitions (bit layout for numerics,
  RFC profile for temporals) and a citation
- `grep -n 'decimal\|timestamptz' docs/vision-direction-0.3.0.md` shows them
  in the not-in-V1 section with the divergence named
- the HDF5 temporal storage figures match phase 1's note, not the pre-probe
  inference
- **the dangling link now resolves** (goal criterion 7): the path
  `docs/vision-direction-0.3.0.md` referenced by
  `docs/v0.2.0/README-archive-note.md` exists. Check the reference by
  extracting it from the archive note rather than by eye — the filename has to
  match what phase 2 actually created, and that note has been committed since
  `0f05670` with the link dead

---

### phase 3: reposition README and invert CLAUDE.md — DONE 2026-08-03T13:24:29+12:00

Carried from the parent's phase 4.

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [x] rewrite `README.md` — remove the `site/` claims and the Quarto/Pages
      paragraph; correct the crate list against `ls crates/`; replace the
      DuckDB-native-types pitch with the dbdict type vocabulary; link to
      `docs/vision-direction-0.3.0.md` rather than restating it
- [x] state V1 scope honestly in the README: 10 scalar types, tables only,
      no compounds, no `decimal` (V2+), no `postgres` (V2), `dummy` not
      shipping in 0.3.0
- [x] rewrite `CLAUDE.md` — **invert** the cross-backend stance (it currently
      says *"not aiming for cross-backend portability. DuckDB-first"*), record
      the four V1 targets (postgres is V2), and note the in-process guarantee
      is now target-dependent
- [x] `CLAUDE.md` points at the direction document; no claim lives in two files
- [x] **the crate list is seven, not four** — `dbdict`, `dbdict-cli`,
      `dbdict-ddl`, `dbdict-duckdb`, `dbdict-dummy-data`,
      `dbdict-dummy-data-duckdb`, `dbdict-parquet`. `CLAUDE.md` currently lists
      four; the README's list was already wrong at the `v0.2.0` tag

**outcome:** both files rewritten. `README.md` is now three layers — a status
banner, *what V1 of 0.3.0 covers* (all links, no restatement), and *what runs
today* (everything true of the current binary). `CLAUDE.md` inverts the stance
and adds two standing warnings for agents working in this repo.

- also: the **structural problem of the phase was the conjunction** in goal
  criterion 3 — every claim true of the repo *and* of V1's scope. Those pull
  opposite ways (`dummy` ships today, is out of V1). Resolved by making tense
  and scope explicit per claim rather than picking one timeline: the README
  says both things in separate labelled sections, and `dummy` carries **"Not
  shipping in 0.3.0"** in its own bullet.
- also: **anchor fragments were written and then removed.** The first draft
  linked `docs/vision-direction-0.3.0.md#5-the-dbdict-type-vocabulary` and
  similar. GitHub's heading→anchor slugification is an external-tool claim that
  would have been asserted from memory, and a wrong slug fails *silently* — the
  link still resolves, it just lands at the top of the page. Replaced with the
  repo's existing convention: section number in the **link text** (`[§5](…)`),
  no fragment. Matches how the direction document cites its own sources.
- also: the verify script was **poison-tested** before its result was believed —
  a sentence pasted from the direction document into a copy of the README made
  the overlap check fail, and it matched across the two files' different
  line-wrapping. Direct application of phase 2's insight
  (`verify-scripts-encode-assumptions`).
- also: the overlap check needed **exclusions to be meaningful** — fenced code
  blocks and markdown table rows are stripped before comparison. The CLI
  `Usage:` block and a shared capability-matrix row are the same *data* quoted
  twice, not the same claim living in two files.
- also: facts re-checked against the tree rather than carried from the state
  file — seven crates, no `site/`, CLI command enum unchanged
  (`crates/dbdict-cli/src/main.rs:17`), and the bundled DuckDB version
  (`v1.5.4`) now cited to `Cargo.lock`'s `duckdb 1.10504.0` rather than left as
  a bare number. `v1.5.4` is also the highest version string embedded in
  `target/release/dbdict`.
- also: the checker lives at `$CLAUDE_JOB_DIR/tmp/verify_phase3.py` and is
  **not committed** — the session is documents-only and adding a tools script
  was not in scope. Phase 5 re-runs the same invariant against
  `docs/roadmap-0.3.0.md`, so it is worth promoting to `research/` or a
  `tools/` dir if the check is wanted permanently.

**verify:** — all 6 checks run and passing
- [x] `grep -n 'site/' README.md` returns nothing
- [x] every relative link in `README.md` resolves to an existing path (19 links)
- [x] README crate list matches `ls crates/` exactly (set comparison, all seven)
      — also checked for `CLAUDE.md`
- [x] `grep -n 'cross-backend portability' CLAUDE.md` shows the inverted wording
      (line 22)
- [x] no sentence appears in both `README.md` and `docs/vision-direction-0.3.0.md`
      (check poison-tested)
- [x] `CLAUDE.md`'s in-process claim is qualified per target (lines 68–73)

---

### phase 4: rewrite the held codegen goal

Carried from the parent's phase 5, scope confirmed unchanged: `goal.md` only.

`.claude-work/sessions/20260723-1109-julia-read-write-codegen/goal.md` assumes
premises that have moved: DuckDB-only storage, DuckDB.jl as the only driver,
and compound types as a core deliverable (*"struct typedefs can map to
generated named Julia structs"*, defaults of *"DECIMAL→FixedDecimal,
ENUM→String, STRUCT→NamedTuple, LIST→Vector"* — three of four now out of V1).

**Files:**
- Modify: `.claude-work/sessions/20260723-1109-julia-read-write-codegen/goal.md`
- Create: `.claude-work/sessions/20260723-1109-julia-read-write-codegen/goal-v0.2.0.md`
- Modify: `.claude-work/sessions/20260723-1109-julia-read-write-codegen/__on-hold__.md`
- **Not touched:** that session's `impl.md` and `review-decisions.md`

- [ ] preserve the original as `goal-v0.2.0.md` in the same directory —
      **copy before editing**, and verify byte-identity against the pre-edit
      file, not after the fact
- [ ] rewrite `goal.md` against V1 scope: 10 scalars, `languages:` NAMEs,
      driver determines the type mapping, no companion mapping file
- [ ] update `__on-hold__.md` to note the premises changed and why, and to
      **flag** that `review-decisions.md` is now partly moot under V1 — several
      of its 15 findings concern `TIMESTAMPTZ`, "all dict-expressible types",
      and companion pairing, all of which V1 changes. Flag only; whoever
      resumes reconciles it
- [ ] leave the session on hold — resuming it is out of scope here

**verify:**
- `grep -nE 'STRUCT|LIST|ENUM|NamedTuple|FixedDecimal' goal.md` in that dir
  returns nothing outside an explicit "deferred" section
- the rewritten goal names `languages:` and the driver-determines-mapping rule
- `goal-v0.2.0.md` exists and is byte-identical to the pre-rewrite file
- `__on-hold__.md` still present — session remains held
- `review-decisions.md` and `impl.md` are unmodified (`git status` shows them
  untouched)

---

### phase 5: roadmap, triage, and clean tree

Carried from the parent's phase 6, with the roadmap location now decided.

**Files:**
- Create: `docs/roadmap-0.3.0.md`
- Modify: `docs/vision-direction-0.3.0.md` (link to the roadmap only)

> **Sibling file, not a section of the direction document.** The direction doc
> already runs to eleven sections, and a roadmap churns on a different clock
> than a positioning statement — mixing them means every re-prioritisation
> edits the file people cite for what dbdict *is*.

- [ ] write `docs/roadmap-0.3.0.md` — ordered, each item naming its blocking
      dependency
- [ ] triage the six pending follow-ups from the closed benchmark session —
      each folded into the roadmap or explicitly dropped with a reason:
      1. `/code-review` ×3 (numbers.py ranking extractor, numbers.py pattern
         fix, run_all.jl header)
      2. promote the nine audit tools to `research/duckdb-driver-jl/tools/`
      3. measure prepared bind (tier 3) and per-row INSERT
      4. fix `numbers.py` memory-figure tolerance
      5. fix the allocations-column mislabel (2 instances)
      6. resume the held codegen session
- [ ] fold in the **four remaining open probes** — `sqlitejl-temporal`,
      `pg-type-oracle` (deferred with Postgres to V2), `sqlite-comment-durability`,
      `jld2-h5-crosscheck`
- [ ] fold in the **`decimal`/`timestamptz` code-vs-docs divergence** as an
      explicit roadmap item — 121 hits, 19 files, source and tests
- [ ] confirm the three research dirs are dispositioned (done in `410a44a`;
      re-verify rather than assume)
- [ ] final `git status` clean

**verify:**
- all six follow-ups appear in the roadmap or a "dropped" list, each with a
  one-line reason
- all four open probes appear, `pg-type-oracle` marked V2
- the `decimal`/`timestamptz` divergence appears as its own item
- roadmap items are ordered and each names its blocking dependency
- `docs/vision-direction-0.3.0.md` links the roadmap and does not duplicate it
- `git status --short` is empty
- `git tag -l v0.2.0` still resolves to `ab468fa`

---

## notes

- **Phase 1 may reopen a settled decision.** That is a legitimate outcome, not
  a failure. If it does, phases 2 and 5 both absorb the change and this file
  gets an `- also:` recording it.
- **Verification is partly manual.** Heading presence, dead links, crate-list
  set equality and `git status` are mechanical. "Every external claim carries a
  link or an `Inferred:` marker" is a read. Phases are sized so that read is
  feasible at the boundary.
- **Session scaffolding** (`goal.md`, `.active`) is untracked and lands in
  phase 1's commit, matching what the parent session did.
- **Nothing here touches `crates/`, `schema*.yaml`, or `$version`.** If a
  phase seems to require it, that is a signal the scope line was drawn wrong —
  stop and re-scope rather than reaching across it.

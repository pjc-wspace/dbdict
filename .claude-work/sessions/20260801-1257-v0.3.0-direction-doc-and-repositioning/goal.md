# v0.3.0 direction document and repositioning

Documents-only session. No crate code, no schema change.

## parent session

Direct continuation of
`.claude-work/sessions/20260731-0930-revisit-app-objectives-and-goals-for-v0.3.0/`,
which was **closed early at 2 of 6 phases** (commits `0f05670`, `1257171`,
`56d5b3c`). Its phases 3–6 carry forward here as phases 2–5; phase 1 is new.

**The type system is settled and is not reopened here.** The authority is
`.claude-work/notes/20260731-1552-dbdict-type-system-decisions.md` — 15 logged
decisions, 16 cited sources. `.claude-work/notes/20260731-1253-capability-matrix.md`
is the authority on per-target capability but is **partly superseded** and
carries a banner saying which parts. Read both before phase 2; do not work from
the parent `goal.md` alone, which was corrected in place and reads as a working
record rather than a settled statement.

The one exception is phase 1 below, which exists precisely because it *can*
reopen a settled decision — deliberately, and before the direction document
freezes it.

## problem

The parent session recorded a direction that had already shifted: dbdict stops
being a DuckDB-native *data dictionary* and becomes a **dataspec** that drives
generation across storage targets, in both directions. It archived the 0.2.0
documents and redesigned the type system, then stopped.

What remains is that the shift is written down in two research notes and
nowhere else. Concretely:

- **There is no direction document.** `docs/vision-direction-0.3.0.md` does not
  exist, so there is nothing public-facing to cite, and
  `docs/v0.2.0/README-archive-note.md` carries a **dangling link** to it — live
  in a committed file since `0f05670`.
- **`README.md` and `CLAUDE.md` describe a repo that no longer exists.**
  `CLAUDE.md` still states *"not aiming for cross-backend portability"* — the
  exact stance the re-baseline inverts — and lists four crates where `crates/`
  holds seven (`dbdict`, `dbdict-cli`, `dbdict-ddl`, `dbdict-duckdb`,
  `dbdict-dummy-data`, `dbdict-dummy-data-duckdb`, `dbdict-parquet`). The
  README's claims were, per the archive note, already inaccurate at the
  `v0.2.0` tag itself.
- **The held codegen session rests on removed premises.**
  `.claude-work/sessions/20260723-1109-julia-read-write-codegen/goal.md` assumes
  DuckDB-only storage and treats compound types as a core deliverable —
  `STRUCT`, `LIST`, `ENUM`, `DECIMAL`, three of four now outside V1.
- **One load-bearing claim is inferred, not measured.** The type system rests on
  *canonical ≠ physical*, which puts temporals on SQLite and HDF5 in lexical
  form at 27–61 bytes/row against 8 for a native integer encoding. That this
  gap is closed by HDF5 compression is marked `Inferred:` in the decisions note.
  The direction document would freeze that inference into a public document.

## success criteria

Criteria 1, 3, 7, 8, 9, 10 are inherited from the parent session's `goal.md`
and keep their original numbers there; the mapping is noted per item. Criterion
0 is new to this session.

0. **`hdf5-temporal-compression` is measured, not inferred.** A note records
   on-disk bytes/row for fixed-width ASCII RFC 3339 temporals against `int64`
   microseconds, each under no filter, gzip, and shuffle+gzip. Input values are
   spread across a realistic range rather than repeated — a column of identical
   timestamps compresses to nothing and would prove nothing about either
   encoding. The note states which of the two outcomes obtained and
   what follows: either the *canonical ≠ physical* decision stands with a
   measured figure replacing the inference, or it reopens and phase 2 absorbs
   the change. Every h5py API used is sourced from h5py's own documentation
   with a link, not from memory.

1. *(parent 1)* A canonical direction document exists at
   `docs/vision-direction-0.3.0.md`, covering, in order: positioning · the two
   entry points · the two-axis model · invariants · the dbdict type vocabulary ·
   `attrdef:` · `languages:` · metadata propagation · the V1 command surface
   (including the brown-field `draft` command) · the capability matrix ·
   what is explicitly *not* in V1.

2. *(parent 3)* The V1 type set is written down in both its dbdict-type
   spellings and its per-target equivalents, with a citation for the target
   names, a stated **bit layout** for each numeric and `bool`, a stated **RFC
   profile** for each temporal, and a rationale for what is in and out.

3. *(parent 7)* `README.md` is **repositioned, not repaired**. Every remaining
   factual claim is true of the repo *and* of V1's scope. The crate list matches
   `ls crates/` as a set. No `site/` claims survive.

4. *(parent 8)* `CLAUDE.md` is updated with its cross-backend stance
   **inverted**, not tweaked; it records the four V1 targets and notes that the
   in-process guarantee is now target-dependent. It points at the direction
   document rather than restating it — **no claim lives in two files.**

5. *(parent 9)* The held codegen session's `goal.md` is **rewritten, not
   amended**, so it contains no premise contradicting V1 scope. The pre-rewrite
   file is preserved byte-identically as `goal-v0.2.0.md`. `__on-hold__.md`
   records that the premises moved and why, and additionally **flags** that
   `review-decisions.md` is now partly moot under V1 — without resolving it.
   The session stays held.

6. *(parent 10)* An ordered roadmap exists at `docs/roadmap-0.3.0.md`, into
   which the parent's six pending benchmark follow-ups and the four remaining
   open probes are folded — or from which each is explicitly dropped with a
   one-line reason. Every item names its blocking dependency.

7. The dangling link resolves: `docs/v0.2.0/README-archive-note.md`'s reference
   to `docs/vision-direction-0.3.0.md` points at a file that exists.

8. `git status --short` is empty and `git tag -l v0.2.0` still resolves to
   `ab468fa`.

## scope

**in:**

- five phases: the HDF5 probe · the direction document · README + CLAUDE.md ·
  the held codegen `goal.md` · roadmap and triage
- an **ephemeral** Python environment for the probe, via
  `uv run --with h5py --with numpy`. Nothing is installed into the project; no
  virtualenv is created in the repo; no dependency is added to any manifest
- `docs/` — new files and edits
- root `README.md` and `CLAUDE.md`
- the held session's `goal.md`, `goal-v0.2.0.md`, and `__on-hold__.md`

**out:**

- **`crates/`, `schema*.yaml`, and `$version`.** Unchanged from the parent's
  scope line. This is deliberate and has a **measured** consequence: the
  parent's phase 2 removed `decimal(p,s)` and `timestamptz` from the type
  system, but `grep -rniE '\b(decimal|timestamptz)\b' crates/ --include=*.rs`
  returns **121 hits across 19 files** as at `3337de5`, source as well as
  tests — `dbdict/src/rich.rs`, `dbdict/src/lower.rs`,
  `dbdict-duckdb/src/native.rs`, `dbdict-dummy-data-duckdb/src/types.rs`,
  `dbdict-parquet/src/metadata.rs`. `schema-0.2.yaml` documents a free-form
  DuckDB type expression using `DECIMAL(18, 4)` as its example.
  So the code implements a type system the documents will no longer describe.
  This session **documents that divergence rather than closing it** — the
  direction document's "not in V1" section and the phase 5 roadmap both have to
  name it explicitly, so it is a recorded debt and not a silent one. If a phase
  seems to require reaching across this line, stop and re-scope — do not reach
- **resuming the held codegen session.** Its `impl.md` and
  `review-decisions.md` are not touched. `impl.md` is rebuilt by `/ws plan`
  whenever the session actually resumes; the 15-finding review ledger is
  reconciled then, by whoever resumes it
- **the other four open probes** — `sqlitejl-temporal`, `pg-type-oracle`,
  `sqlite-comment-durability`, `jld2-h5-crosscheck`. These become roadmap items
  in phase 5. `pg-type-oracle` is deferred with Postgres to V2 regardless
- **reopening the type system**, except by the one route phase 1 opens
- site/docs publishing, Quarto, GitHub Pages — the parent removed these claims
  rather than implementing them

## constraints

- **Evidence standard.** Every external claim about DuckDB, DuckLake, SQLite,
  HDF5, h5py, JLD2, Postgres or QuackIO carries a link to official
  documentation, or is marked `Inferred:` with its reasoning visible. The
  direction document is public-facing; bare assertions are a defect there, not
  a style preference. The parent session set the bar — 35 links across 13
  official domains, with `[cited]` / `[measured]` / `Inferred:` markers — and
  this session does not lower it.
- **Phase boundaries are session boundaries.** Start each phase below 25%
  context and keep it under 30%. Phase 2 is the largest by a wide margin.
- **Phase 2 has a pre-identified split point.** If it will not fit one context,
  split at: positioning · two entry points · two-axis model · invariants
  ‖ type vocabulary · `attrdef:` · `languages:` · metadata propagation ·
  command surface · capability matrix · not-in-V1. Splitting commits a
  knowingly incomplete file at the boundary, so the "no `TBD`, no blank
  section" check runs only after the second half. Take the split only if
  needed; it costs no re-planning.
- **Phase 1 may reopen a settled decision.** That is a legitimate outcome, not
  a failure. If the measurement contradicts the inference, the decisions note
  is amended and phase 2 writes the amended story — the finding is not
  suppressed to protect the plan.
- **Verification is partly manual.** Heading presence, dead links, crate-list
  set equality and `git status` are mechanical. "Every external claim carries a
  link or an `Inferred:` marker" is a read. Phases are sized so that read is
  feasible at the boundary.
- Ordering is fixed: phase 1 before phase 2 (a surprise must land in the
  internal note, not the public document); phase 2 before phases 3 and 5 (both
  cite it rather than restating it).

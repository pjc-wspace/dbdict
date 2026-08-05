# dbdict — roadmap, 0.3.0

Companion to [`vision-direction-0.3.0.md`](vision-direction-0.3.0.md). That
document says what dbdict *is* and what V1 covers. This one says in what order
the remaining work happens and what each piece waits on.

They are deliberately separate files. A roadmap is re-prioritised often; a
positioning statement should not churn every time it is. Nothing below restates
the direction document — items cite its sections by number instead.

**Status: nothing here has been started.** The 0.3.0 re-baseline was scoped as
documents-only, so every code item is at zero.

---

## how to read this

- Items are numbered **R1–R20** in dependency order: no item is blocked by a
  higher-numbered one.
- **blocked by:** names what has to land first. `—` means it can start today.
- **source:** points at the record the item came from, so the fuller history
  survives this file's much shorter phrasing.
- Items are not sized. Some are a work session each; several are under an hour.

### three counts here were re-derived, not carried forward

Earlier planning documents quote item counts that no longer match the
artifacts. The corrected figures are used below, and the discrepancy is noted
because a reader arriving from those documents will expect the old ones.

- The benchmark session left **seven** follow-ups, not six. The list of six in
  `.claude-work/sessions/20260731-0930-…/impl.md` substituted a codegen item for
  that session's own items 6 and 7, which are real and are carried here as R19
  and R20.
- The direction document's open-probe table (§10) has **five rows naming six
  probes** — `ducklake-describe` and `ducklake-roundtrip` share a row. All six
  appear below.
- The codegen review ledger has **seven** findings still `PENDING`, not five.
  Four are V1-agnostic, two are companion-file questions V1 dissolves, and one
  was never classified. See R14.

---

## spec and model

Everything with a `crates/` component waits on the first item.

### R1 — write `schema-0.3.yaml`

The dataspec schema for the dbdict type vocabulary, `attrdef:` and
`languages:` (direction §5, §6, §7). `schema-0.2.yaml` describes a free-form
DuckDB type expression and is the format the current code implements.

This is the gate for every other code item: until the file format is settled,
backends and generators have no agreed input.

- **blocked by:** — (direction §5–§7 is the design; this is transcription into
  a schema)
- **source:** the direction document's closing `versioning` section, which
  records the breaking-change decision but explicitly leaves acting on it
  downstream

### R2 — bump `$version` and write the 0.2.0 migration story

`0.2.0` → `0.3.0`, plus what happens to a dataspec written against the old
schema. The direction document records the version decision; it does not say
whether old files are rejected, auto-upgraded, or read under a compatibility
path. That choice is this item.

- **blocked by:** R1
- **source:** the direction document's `versioning` section

### R3 — reconcile `decimal` and `timestamptz` between the code and the documents

The documents removed both types from the V1 vocabulary; `crates/` still
implements them. Direction §11 carries the measurement — **121 hits, 19 files**
at commit `3337de5` — and names the five modules involved, so the inventory is
not repeated here.

This is the only item on the roadmap that closes a **known debt rather than
adding a capability**, and it is why `CLAUDE.md` warns agents off "correcting"
either side on sight. Deletion is not the only outcome available: `decimal` is
out of V1 rather than gone forever, so some of this code may be worth
re-parenting instead.

- **blocked by:** R1 — the schema decides which types survive, and that decides
  whether this is a deletion or a re-parenting
- **source:** direction §11, *a known divergence between this document and the
  code*; this session's `goal.md` scope line

---

## probes that gate a design decision

Each of these is cheap and answers a question that a later item would otherwise
have to guess at. They are listed before the work they gate.

### R4 — probe `sqlite-comment-durability`

Do DDL comments survive `VACUUM` and `ALTER TABLE` on SQLite?

**First among the probes**, because direction §10 identifies it as the one whose
result would still change a design — and because R8 has to commit to a metadata
channel before it can be written. Running it after the backend means discovering
the answer as a rewrite.

- **blocked by:** —
- **source:** direction §10, *open probes*, which states what a negative result
  costs

### R5 — probe `sqlitejl-temporal`

What SQLite.jl actually writes for `Date` and `DateTime` values. Feeds the
Julia side of the SQLite target rather than the backend itself.

- **blocked by:** SQLite.jl is not installed on this machine (Julia 1.12.6 is
  present)
- **source:** direction §10

### R6 — probe `jld2-h5-crosscheck`

JLD2 ↔ HDF5 semantic portability — whether a file written by one is meaningfully
readable by the other, which decides whether the `hdf5` target has a usable
Julia story or only a Python one.

- **blocked by:** JLD2 is not installed (h5py 3.16.0 / HDF5 2.0.0 are reachable
  through an ephemeral `uv` environment, per
  [`.claude-work/notes/20260802-1146-hdf5-temporal-compression.md`](../.claude-work/notes/20260802-1146-hdf5-temporal-compression.md))
- **source:** direction §10

### R7 — probes `ducklake-describe` and `ducklake-roundtrip`

Whether DuckLake's `DESCRIBE` output matches DuckDB's, and whether a dataspec
survives a snapshot. `ducklake` is treated as a near-clone of `duckdb` in the
capability matrix; these two probes are what would justify that.

- **blocked by:** the `ducklake` extension is not installed
- **source:** direction §10

---

## targets and commands

Three of the four V1 targets have no crate. `crates/` currently holds seven:
`dbdict`, `dbdict-cli`, `dbdict-ddl`, `dbdict-duckdb`, `dbdict-dummy-data`,
`dbdict-dummy-data-duckdb`, `dbdict-parquet`.

### R8 — `sqlite` backend

The hardest of the three new targets, and the reason V1's type set is small:
per direction §10 only three dbdict types are native there, three need
encodings, three integer widths are unenforced, and `float32` has no
representation at all.

- **blocked by:** R1, R3, R4
- **source:** direction §10 type coverage

### R9 — `hdf5` backend

Seven types native, three needing encodings. The temporal encoding question is
already settled with measurements rather than inference — lexical RFC 3339
compresses below the `int64` alternative, at a read-time cost that is the real
trade being made.

- **blocked by:** R1, R3. R6 informs the Julia half but does not block the
  backend
- **source:** direction §5 storage, §10; probe note
  [`20260802-1146-hdf5-temporal-compression.md`](../.claude-work/notes/20260802-1146-hdf5-temporal-compression.md)

### R10 — `ducklake` target

Expected to be mostly `duckdb` with a catalog and snapshots underneath, which is
exactly the assumption R7 tests.

- **blocked by:** R1, R7
- **source:** direction §10

### R11 — consolidate the validate commands into `dbdict validate`

The V1 surface names one `validate`. The binary today has three —
`validate-spec`, `validate-meta`, `validate-data`
(`crates/dbdict-cli/src/main.rs:17`). This item decides whether they collapse
into one command with flags or the V1 name simply covers the family.

- **blocked by:** R1
- **source:** direction §9 command surface, read against the current enum

### R12 — rework `dbdict resolve` to emit the mapping from both directions

`resolve` exists, but prints each typedef's canonical DuckDB expansion — the
0.2.0 model. V1 wants the type mapping emitted keyed either by dbdict type or
by target type, because authoring and reading someone else's database want
opposite views of the same table.

- **blocked by:** R1, R3
- **source:** direction §4 invariants, §9

### R13 — `dbdict draft <db>`

The brown-field entry point, and the larger of the two new commands: schema plus
profiled constraints from the D01–D05 queries in inference mode, empty
`description:` stubs, and the evidence counts printed beside each proposal.

The evidence comments are load-bearing rather than decorative — inference here
is unsound by construction, and the counts are what let a reader judge a
proposal instead of trusting it.

- **blocked by:** R1, R12. Per-target `draft` additionally waits on that
  target's backend (R8–R10)
- **source:** direction §9, *`draft` in detail*

---

## codegen

### R14 — `dbdict gen <NAME>`: Julia first, as a **fresh work session**

Not a resumption. The July session
`.claude-work/sessions/20260723-1109-julia-read-write-codegen/` was closed on
2026-08-05 and its `goal.md` carries a supersession banner: the design rested on
a per-language companion mapping file that direction §7 deletes outright, and on
compound types that are out of V1. The maintainer's assessment was that the
goals themselves were wrong, not merely stale, so the file was preserved as
evidence rather than rewritten.

**What a fresh session should mine from it**, none of which was superseded:

- `spike/` — eight Julia scripts establishing what DuckDB.jl can and cannot do,
  plus the pinned environment they ran in
- [`research/duckdb-driver-jl/reference.md`](../research/duckdb-driver-jl/reference.md)
  — the consolidated driver reference, audited and benchmarked across three
  later sessions
- `review-decisions.md` — a 15-finding adversarial review of the original plan

**And the findings that are still open.** The ledger has seven `PENDING`. Four
are V1-agnostic and should be decided by whoever writes the new goal rather than
left buried in a July file:

| # | finding | why it survives V1 |
|---|---|---|
| 8 | identifier safety, Julia and SQL sides | independent of which types exist |
| 10 | `dbdict gen julia` output model undefined | the output-shape question V1 does not answer either |
| 13 | a phase 2 verify step names a `dbdict validate` subcommand that did not exist | see R11 — V1 *does* name one, so this may now resolve itself |
| 15 | primary-key phrasing, table-level vs column-level | the pk-on-compound edge is moot; the phrasing is not |

Two more — 7 and 12 — are companion-file questions that V1 dissolves, since no
companion file exists. **Finding 9 was never classified** and is a mix:
its StructArrays half concerns compound types and is moot, its mixed-table tier
logic half is not. It needs a decision.

- **blocked by:** R1, R12
- **source:** that session's `goal.md` banner, its `summary.md`, and the
  retired hold marker under its `hold-archive/` (2026-08-04 section);
  direction §7

---

## research-document follow-ups

Carried from the closed benchmark session
`.claude-work/sessions/20260727-1540-benchmark-result-reconciliation-and-clarity/`.
These concern `research/duckdb-driver-jl/` and its audit tooling. **None is
blocked by anything above**, and none blocks V1 — they are ordered among
themselves by value.

Nothing from that session's list is dropped. All seven appear below.

### R15 — `/code-review` three benchmark code changes

`numbers.py`'s ~70-line ranking extractor, `numbers.py`'s pattern fix, and
`run_all.jl`'s header edit. The extractor is the largest of the three and the
only one whose correctness rests on negative tests written by the same author as
the implementation — the session itself flagged it as the highest-value item
outstanding.

- **blocked by:** —

### R16 — promote the stranded audit tooling to `research/duckdb-driver-jl/tools/`

The follow-up says nine tools; the tree now holds **thirteen** Python scripts
across two closed session directories — eight in
`.claude-work/sessions/20260727-0924-dedup-findings-and-reference/tools/` and
five in the benchmark session's `tools/`. They audit a document that lives in
`research/`, so they are two directory levels away from what they check and
invisible to anyone reading it.

Fold in the **documentation-overlap checker** written during this session's
phases 3 and 5 — "no sentence appears in two documents" — which is currently in
a job scratch directory and will be lost with it. It is the same problem: an
invariant with a mechanical check that nothing durable owns.

- **blocked by:** —

### R17 — fix the allocations-column mislabel in `reference.md` §7

Two instances: §7.2's `1.705 GiB` cell and §7.3's "58.541 vs 59.137 MiB"
comparison. Both are memory figures sitting in a column whose header says
*allocations*.

- **blocked by:** —

### R18 — tighten `numbers.py`'s memory-figure tolerance

§7.3's `59.143 MiB` passed against a true `59.137 MiB` — a 6,293-byte gap where
three decimals of MiB imply about ±524 bytes. The figure was corrected by hand;
the tolerance that let it through was not.

- **blocked by:** —

### R19 — report `1t · read · struct · 1M` as a distribution

The cell was labelled unstable, then stable, then dominant in five of six runs
across three sweeps. A single stable/unstable verdict is not a claim the data
supports; the distribution is.

- **blocked by:** —

### R20 — measure prepared bind (tier 3) and per-row `INSERT`

Closes the four-measured-against-five-tiers gap that §7.0 currently discloses
rather than fills. Needs a fresh sweep, which makes it the most expensive item
in this group.

- **blocked by:** —

### open question, not an item

**Should `results.md` be demoted the way `findings.md` was?** The benchmark
session left this deliberately alone and it is a layering judgement, not a task
with a definition of done. It is recorded here so it is not lost, but it has no
number and nothing waits on it.

---

## deferred to V2 or later

Not scheduled. Listed so their absence above is visible rather than accidental.

- **`postgres`**, and with it the `pg-type-oracle` probe — the exact
  `information_schema.columns` output for the mappable types. Deferred as a
  pair; the probe is pointless without the target
- **compound types** — direction §11 records that their return would be a
  (target × language) pairing, not new dbdict type entries
- **views** — deferred because the dataspec is SQL-free (direction §4)
- **`decimal`** — out of V1, not out forever; see R3
- **the `dummy` feature** — two crates of it exist and run against DuckDB now,
  but direction §11 rules it out of 0.3.0 on the grounds that the internal
  changes will break it. Revisiting it is a later decision, not a V1 one

### backend leads, recorded but not scheduled

Two alternatives were noted while the direction changed and are parked in
`research/` with a one-line `todo.md` each:
[`parquet2-as-alternative-backend`](../research/parquet2-as-alternative-backend/todo.md)
and [`quackio-driver-jl`](../research/quackio-driver-jl/todo.md). Neither is a
V1 target and neither has been evaluated.

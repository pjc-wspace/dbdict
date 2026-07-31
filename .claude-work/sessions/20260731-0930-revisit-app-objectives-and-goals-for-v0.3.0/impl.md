# implementation: revisit app objectives and goals for v0.3.0

Documents-only session. No crate code, no schema change. Six phases, each
independently committable so the session can be paused at any boundary.

> **Already done before planning** (during `/ws new`, at the user's request):
> - git tag `v0.2.0` created (annotated) at `ab468fa`
> - commit `410a44a` "julia duckdb and jld2 exploration" — 27 research
>   source files + `.gitignore` rules for regenerable `*.jld2`/`*.db`/`*.duckdb`
> - this covers **success criterion 2 (tag half)** and most of
>   **criterion 11**; both are re-verified in their phases rather than assumed

## phases

### phase 1: archive the 0.2.0 state — DONE 2026-07-31T12:39:25+12:00

Freeze the pre-shift documents so the rewrites in phases 4–5 are non-destructive.

- [x] create `docs/` and `docs/v0.2.0/`
- [x] copy (not move) `README.md` → `docs/v0.2.0/README.md`
- [x] copy (not move) `CLAUDE.md` → `docs/v0.2.0/CLAUDE.md`
- [x] add `docs/v0.2.0/README-archive-note.md` — one paragraph stating what
      this directory is, the tag it corresponds to, and that the root files
      have since been repositioned for 0.3.0
- [x] confirm the `v0.2.0` tag resolves to `ab468fa`
- also: checked `git diff --quiet ab468fa -- README.md CLAUDE.md` **before**
  copying — both were byte-identical to the tag, so `cp` from the working tree
  was safe. Had they drifted, the copy would have had to come from
  `git show ab468fa:<file>` instead; the verify would only have caught it after
  the fact
- also: the archive note runs to two paragraphs, not one — the second records
  that the archived README was **already inaccurate at the tag**, verified with
  `git ls-tree ab468fa` rather than against today's tree: `site/` did not exist
  at `ab468fa` (so the `site/spec.md` and `site/validation.md` links were
  already dead), and the README's five-crate list omitted `dbdict-dummy-data`
  and `dbdict-dummy-data-duckdb`, both of which existed at that commit. This is
  direct input to phase 4, which has to correct exactly these
- also: the note forward-references `docs/vision-direction-0.3.0.md`, which
  phase 3 creates — the link is dangling until then

**verify:**
- `ls docs/v0.2.0/` lists `README.md`, `CLAUDE.md`, `README-archive-note.md`
- `git rev-parse v0.2.0^{commit}` prints `ab468fa…`
- `diff <(git show ab468fa:README.md) docs/v0.2.0/README.md` is empty
- `diff <(git show ab468fa:CLAUDE.md) docs/v0.2.0/CLAUDE.md` is empty
- root `README.md` and `CLAUDE.md` still present and unmodified

---

### phase 2: research — fill the capability matrix — DONE 2026-08-01

The only phase with genuine unknowns. Everything downstream depends on it.
Output is a standalone file that phase 3 embeds.

> **Phase 2 exceeded its plan.** It was scoped as "fill in a matrix"; it turned
> into a re-design of the type system, because the research falsified premises
> the type set rested on. Two output files, not one:
> - `notes/20260731-1253-capability-matrix.md` — the capability research
>   (415 lines). **Partly superseded**: its research stands, its type set does
>   not; it carries a banner saying so.
> - `notes/20260731-1552-dbdict-type-system-decisions.md` — the type-system
>   decisions that followed (15 logged decisions, 5 open probes).
>
> `goal.md` was corrected in-phase rather than deferred, per the phase rule —
> **three of its claims were falsified** and one terminology change swept
> through the whole file.

- [x] write `.claude-work/notes/{stamp}-capability-matrix.md`
- [x] **rows**: the 12 LF types (grouped), schema generation, type oracle,
      metadata surface (`COMMENT ON` equivalent), D01–D05, in-process
      guarantee, round-trip fidelity (`spec → db → draft → spec`)
- [x] **columns**: `duckdb`, `ducklake`, `postgres`, `sqlite`, `hdf5`
- [x] source **SQLite's type system** first — if it uses type affinity with a
      small set of storage classes, the LF integer and float widths collapse
      and `decimal`/`date`/`timestamp`/`timestamptz` have no native type,
      making SQLite a **second encoding-convention target alongside HDF5**.
      This would falsify `goal.md`'s "SQL targets ≈ flat cost" claim, which
      must then be corrected there and in the direction doc
- [x] source **SQLite comment support** — `goal.md` records this as unverified
- [x] source **Postgres** type names for the 12 LF types, and confirm
      `COMMENT ON` (currently `Inferred:` from DuckDB's *"follows the
      PostgreSQL syntax"*)
- [x] source **DuckLake** — whether it inherits DuckDB's DDL, types, and
      `COMMENT ON` wholesale, or diverges
- [x] settle the **four HDF5 encoding conventions** (`date`, `timestamp`,
      `timestamptz`, `decimal(p,s)`) — decide and record, or name the exact
      probe per goal.md criterion 5
- [x] every cell resolved with a citation, or `unknown — needs probe: <name>`

**verify:** — all 10 checks re-run and passing against the *revised* state
- [x] no blank table cells (0 across both notes)
- [x] every in-table `unknown` names a probe (1 remains: `pg-type-oracle`)
- [x] every non-obvious claim carries a markdown link or `Inferred:` marker —
      **35 links across 13 official domains**; markers: 98 `[cited]`,
      34 `[measured]`, 10 `Inferred:`
- [x] the in-process row explicitly marks Postgres as breaking it
- [x] SQLite **was** confirmed affinity-based → `goal.md` corrected in-phase

**what the research actually falsified in `goal.md`:**
1. *"`duckdb → ducklake → postgres → sqlite` ≈ flat, then a step up to
   `hdf5`"* — **false.** SQLite is affinity-typed and needs the same encoding
   conventions as HDF5. Real shape is three tiers.
2. *"8 of the 12 types are free on every target"* — **false.** Three, against
   the V1 targets.
3. *"SQLite comment support is unverified"* — **resolved**: no `COMMENT ON`
   statement exists, but DDL comments survive verbatim in `sqlite_schema.sql`.

**decisions taken (full record in the 1552 note):** vocabulary renamed to
**dbdict types** (LF/lingua franca retired and swept); **10 types** with exact
definitions — numerics by bit layout, temporals by RFC profile; `decimal` →
V2+; `timestamptz` removed; `datestamp` never introduced; `date` = RFC 3339
`full-date`, `timestamp` = RFC 3339 `date-time` + optional RFC 9557 zone;
canonical form ≠ physical storage (native where it exists, lexical on SQLite
and HDF5); SQLite emission **non-STRICT**; **Postgres → V2**; `string`
unbounded with `max_chars:`/`max_bytes:` as constraints — the latter doubling
as HDF5's compression switch.

---

### phase 3: write the direction document

> **Re-scoped by phase 2.** The type system changed substantially — read
> `.claude-work/notes/20260731-1552-dbdict-type-system-decisions.md` **before**
> starting, not just `goal.md`. Its 15-item decision log is the authority on
> types; the 1253 capability-matrix note is the authority on per-target
> capability but is *partly superseded* and carries a banner saying which parts.

- [ ] write `docs/vision-direction-0.3.0.md`
- [ ] sections, in order: positioning · the two entry points · the two-axis
      model · invariants · dbdict type vocabulary · `attrdef:` ·
      `languages:` · metadata propagation · V1 command surface · capability
      matrix (embedded from phase 2) · what is explicitly *not* in V1
- [ ] carry over every sourced quote and link from `goal.md` — this document
      is public-facing where `goal.md` is a working record
- [ ] state the round-trip property (`spec → DDL → db → draft → spec`) and
      where it is known to fail
- [ ] state the compound-type deferral with **both** reasons (no neutral
      spelling; nowhere on the current stack for them to work)

**verify:**
- all eleven required headings present (grep for each)
- every external claim has a link or an `Inferred:` marker — no bare
  assertions about DuckDB, DuckLake, Postgres, SQLite, HDF5, JLD2 or QuackIO
- document contains no `TBD`, `TODO`, or blank section
- the 10 dbdict types appear with their definitions (bit layout for numerics,
  RFC profile for temporals) and a citation

---

### phase 4: reposition README and invert CLAUDE.md

- [ ] rewrite `README.md` — remove the `site/` claims and the Quarto/Pages
      paragraph; correct the crate list against `ls crates/`; replace the
      DuckDB-native-types pitch with the dbdict type vocabulary; link to
      `docs/vision-direction-0.3.0.md` rather than restating it
- [ ] state V1 scope honestly in the README: 10 scalar types, tables only,
      no compounds, no `decimal` (V2+), no `postgres` (V2), `dummy` not
      shipping in 0.3.0
- [ ] rewrite `CLAUDE.md` — **invert** the cross-backend stance (it currently
      says *"not aiming for cross-backend portability. DuckDB-first"*), record
      the four V1 targets (postgres is V2), and note the in-process guarantee is now
      target-dependent
- [ ] `CLAUDE.md` points at the direction document; no claim lives in two files

**verify:**
- `grep -n 'site/' README.md` returns nothing
- every relative link in `README.md` resolves to an existing path
- README crate list matches `ls crates/` exactly (set comparison)
- `grep -n 'cross-backend portability' CLAUDE.md` shows the inverted wording
- no sentence appears in both `README.md` and `docs/vision-direction-0.3.0.md`

---

### phase 5: rewrite the held codegen goal

`.claude-work/sessions/20260723-1109-julia-read-write-codegen/goal.md`
assumes premises that have moved: DuckDB-only storage, DuckDB.jl as the only
driver, and compound types as a core deliverable (*"struct typedefs can map to
generated named Julia structs"*, defaults of *"DECIMAL→FixedDecimal,
ENUM→String, STRUCT→NamedTuple, LIST→Vector"* — three of four now out of V1).

- [ ] rewrite it against V1 scope: 10 scalars, `languages:` NAMEs, driver
      determines the type mapping, no companion mapping file
- [ ] preserve the original as `goal-v0.2.0.md` in the same directory
- [ ] update `__on-hold__.md` to note the premises changed and why
- [ ] leave the session on hold — resuming it is out of scope here

**verify:**
- `grep -nE 'STRUCT|LIST|ENUM|NamedTuple|FixedDecimal' goal.md` in that dir
  returns nothing outside an explicit "deferred" section
- the rewritten goal names `languages:` and the driver-determines-mapping rule
- `goal-v0.2.0.md` exists and is byte-identical to the pre-rewrite file
- `__on-hold__.md` still present — session remains held

---

### phase 6: roadmap, triage, and clean tree

- [ ] add an ordered roadmap to `docs/vision-direction-0.3.0.md` (or a
      sibling `docs/roadmap-0.3.0.md` if it crowds the direction doc)
- [ ] triage the six pending follow-ups from the closed benchmark session —
      each folded into the roadmap or explicitly dropped with a reason:
      1. `/code-review` ×3 (numbers.py ranking extractor, numbers.py pattern
         fix, run_all.jl header)
      2. promote the nine audit tools to `research/duckdb-driver-jl/tools/`
      3. measure prepared bind (tier 3) and per-row INSERT
      4. fix `numbers.py` memory-figure tolerance
      5. fix the allocations-column mislabel (2 instances)
      6. resume the held codegen session
- [ ] confirm the three research dirs are dispositioned (done in `410a44a`;
      re-verify rather than assume)
- [ ] final `git status` clean

**verify:**
- all six follow-ups appear in the roadmap or a "dropped" list, each with a
  one-line reason
- roadmap items are ordered and each names its blocking dependency
- `git status --short` is empty
- `git tag -l v0.2.0` still resolves to `ab468fa`

---

## notes

- **Phase boundaries are session boundaries.** Per `goal.md`'s context
  constraint, start any phase below 25% context. Phase 2 is the largest and
  should begin fresh.
- **Phase 2 can falsify `goal.md`.** If SQLite turns out to be
  affinity-typed, the "SQL targets ≈ flat cost" claim and possibly the
  five-target roster itself need revisiting. That is a legitimate outcome, not
  a failure — `goal.md` gets corrected in phase 2 rather than the finding
  being suppressed to protect the plan.
- **Nothing here touches `crates/`, `schema*.yaml`, or `$version`.** If a
  phase seems to require it, that is a signal the scope line was drawn wrong —
  stop and re-scope rather than reaching across it.

# summary: revisit app objectives and goals for v0.3.0

started: 2026-07-31 09:30
closed: 2026-08-01T10:47:38+12:00

**Closed at the user's request with 2 of 6 phases complete.** Phases 3–6 were
not attempted. This is an early close, not a completion — see "not done" below.

## goal

Documents-only re-baseline. Record a direction that had already shifted but was
never written down, and repair documents describing a repo that no longer
exists. dbdict stops being a DuckDB-native *data dictionary* and becomes a
**dataspec** that drives generation across several storage targets, in both
directions.

## what was accomplished

### phase 1 — archive the 0.2.0 state (DONE, commit `0f05670`)

`docs/v0.2.0/` holds byte-identical copies of `README.md` and `CLAUDE.md` as at
tag `v0.2.0` (`ab468fa`), plus an archive note. Copies were verified against
the tag *before* copying rather than after.

The archive note records that the archived README was **already inaccurate at
the tag** — verified with `git ls-tree ab468fa`, not against today's tree:
`site/` did not exist there (so two documented links were already dead) and the
crate list omitted two crates that did exist. That is direct input to phase 4.

### phase 2 — capability research, which became a type-system redesign (DONE)

Scoped as "fill in a matrix". It became a re-design, because the research
falsified premises the type set rested on. Two outputs:

- `.claude-work/notes/20260731-1253-capability-matrix.md` — per-target
  capability research. **Partly superseded** (banner explains which parts); its
  research stands, its type set does not.
- `.claude-work/notes/20260731-1552-dbdict-type-system-decisions.md` — the
  resulting type system. **This is the authority on types.** 15 logged
  decisions, 5 open probes, 16 cited sources.

Evidence: 35 markdown links across 13 official domains; 98 `[cited]`,
34 `[measured]`, 10 `Inferred:` markers. Probes were run locally against
DuckDB CLI v1.5.4 and SQLite 3.37.2.

## key decisions

**Three `goal.md` claims were falsified and corrected in-phase:**

1. *"`duckdb → ducklake → postgres → sqlite` ≈ flat, then a step up to
   `hdf5`"* — **false.** SQLite is affinity-typed, not declared-typed, and
   needs the same encoding conventions as HDF5. Three tiers, not two.
2. *"8 of the 12 types are free on every target"* — **false.** Three, against
   the V1 targets.
3. *"SQLite comment support is unverified"* — resolved: there is no
   `COMMENT ON` statement, but DDL comments survive verbatim in
   `sqlite_schema.sql` (probed).

**The type system, as settled:**

| decision | |
|---|---|
| naming | **"dbdict types"** — *lingua franca* / *LF* retired and swept from every file |
| the set | **10 types**: `bool`, `int8/16/32/64`, `float32/64`, `string`, `date`, `timestamp` |
| definition | numerics + `bool` by **bit layout**; temporals by **pinned RFC profile** |
| `date` | RFC 3339 `full-date` — `YYYY-MM-DD`, no time, no zone |
| `timestamp` | RFC 3339 `date-time`, µs, optional RFC 9557 `[Zone]` suffix |
| storage | **canonical ≠ physical** — native type where one exists; lexical form on SQLite and HDF5 |
| removed | `decimal(p,s)` → V2+ · `timestamptz` removed · `datestamp` never introduced |
| zones | value-level per RFC 9557, **plus** `timezone:` / `timezone_from:` as the required spillover where native types discard the zone |
| SQLite | emission is **non-STRICT**, affinities chosen deliberately |
| strings | unbounded; `max_chars:` / `max_bytes:` optional — the latter doubles as HDF5's compression switch |
| targets | **V1: `duckdb` `ducklake` `sqlite` `hdf5`** — **`postgres` → V2** |

**Reasoning worth preserving:**

- **Postgres → V2** because it alone breaks the in-process guarantee, has no
  1-byte integer (so `int8` widens and round-trip identity fails), and could
  not be probed here.
- **`datestamp` was never introduced** on two independent grounds: no
  standards-compliant spelling exists (RFC 3339 attaches offsets only to times;
  RFC 9557 extends only `date-time`), and a zoned date is *provenance*, not a
  distinct value.
- **Lexical-on-SQLite** because Python and rusqlite both already write ISO
  text; integer encodings would have broken every stock driver on the target
  chosen for portability.
- **Canonical ≠ physical** dissolved the "one shared encoding" deadlock: what
  must be shared is the *value space*, not the bytes. Measured proof it was
  needed — DuckDB's native `TIMESTAMPTZ` discards the input zone, so the
  canonical form is strictly more expressive than some physical layers, and
  the overflow needs a declared home.
- **HDF5 variable-length strings get no chunking and no compression**, which
  settled the temporal sizing question (fixed-size) and promoted `max_bytes:`
  from a validation nicety to a performance lever.

## not done — 4 of 6 phases outstanding

| phase | state |
|---|---|
| 3 — direction document `docs/vision-direction-0.3.0.md` | **not started** |
| 4 — reposition README, invert CLAUDE.md | **not started** |
| 5 — rewrite the held codegen goal | **not started** |
| 6 — roadmap, triage six follow-ups, clean tree | **not started** |

`impl.md` for phases 3–6 has been **updated to the new decisions** (10 types,
four V1 targets, `dbdict types` terminology) so the plan is not stale for
whoever resumes. Phase 3 carries a banner directing the reader to the 1552
decisions note first.

Success criteria 1, 3 (partly), 7, 8, 9, 10 remain unmet. Criterion 4 is met
for the capability matrix; criterion 5 is met and revised (three conventions,
not four). Criteria 2 and 11 were met before planning.

**One consequence to watch:** `docs/v0.2.0/README-archive-note.md` links
`docs/vision-direction-0.3.0.md`, which phase 3 was to create. That link is
**dangling** until phase 3 runs.

## open probes, carried forward

| probe | why it matters |
|---|---|
| `hdf5-temporal-compression` | the only open item that could **revisit a settled decision** — lexical temporals cost 27–61 bytes/row vs 8 for integers, and "compression closes the gap" is `Inferred:`, not measured |
| `sqlitejl-temporal` | the one unresolved driver row; Julia is the first codegen target and SQLite.jl may serialize to `BLOB`. Julia 1.12.6 is installed, SQLite.jl is not |
| `pg-type-oracle` | deferred with Postgres to V2 |
| `sqlite-comment-durability` | do DDL comments survive `VACUUM` / `ALTER TABLE`? The comment is a metadata carrier on SQLite |
| `jld2-h5-crosscheck` | JLD2 ↔ HDF5 semantic portability |

## insights captured

- `.claude-work/insights/20260731-1238-archive-from-the-tag-not-the-working-tree.md`
- `.claude-work/insights/20260731-1219-dataspec-re-baseline-type-systems-and-extensibility.md`
  (written before phase 1, committed with it)
- plus this session's closing capture — see `.claude-work/insights/`

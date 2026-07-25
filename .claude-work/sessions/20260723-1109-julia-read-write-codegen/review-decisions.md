# adversarial plan review — findings and decisions

review of goal.md + impl.md by an independent adversarial agent,
2026-07-23. 15 findings: 3 blocker, 8 major, 4 minor. working through
them one at a time with the user; plan edits applied in batch once all
are decided.

## finding 1 (blocker) — type-structure gap — DECIDED 2026-07-23

claim: generators receive raw type strings; nothing parses DuckDB type
expressions; parser is an unplanned phase-sized job; phase 4's "dep on
core only" contradicts dbdict-ddl's own dbdict-duckdb dependency.

verification: half right. the gap and the dependency contradiction are
real, but the parser exists — the reviewer never opened the dummy-data
crates. `dbdict-dummy-data-duckdb/src/types.rs` (331 lines) parses
canonical spellings (via `dbdict_duckdb::instantiate` / DESCRIBE) into a
`DuckType` tree: all C-enum types except TIMESTAMP_S/MS/NS and TIMETZ,
plus JSON and GEOMETRY, with total-over-behavior `Unsupported` fallback.
canonicalize-then-parse also solves finding 6's normalization hole.

decision:
- new phase before companion-file work: hoist `DuckType` + `parse_type`
  from `dbdict-dummy-data-duckdb` into `dbdict-duckdb` (backend crate;
  both generators may depend on it — generators still never depend on
  each other); update dummy-data imports; move tests
- hoist phase also adds the 4 missing parser arms (TIMESTAMP_S/MS/NS,
  TIMETZ), canonical spellings pinned empirically per module convention
- phase 4 drops "dep on dbdict core only": dbdict-julia depends on
  dbdict + dbdict-duckdb, same as dbdict-ddl
- phases 3-7 consume DuckType trees instead of strings (wiring change,
  not the reviewer's "reshapes phases 3-7" surgery)
- noted for finding 4: parsing ≠ end-to-end support. TIMESTAMP_NS
  cannot round-trip julia's ms-precision DateTime; TIMETZ shares
  TIMESTAMPTZ's offset policy question

## finding 2 (blocker) — phases 5-7 cannot fail — DECIDED 2026-07-23

golden tests pin emitted text only; nothing executes generated julia
until phase 8; three phases of defects surface at once.

decision: live-execution smoke test from phase 5, growing per phase:
- phase 5: crates/dbdict-julia/tests/live.rs — emit for an
  all-primitives fixture, run julia against the committed harness env,
  call write_/read_, compare a row, nonzero exit on mismatch
- phase 6 adds the nested fixture; phase 7 adds the row-op sequence
- phase 8 extends coverage (full matrix), no longer first execution
golden tests stay for emission-stability; live test is deliberately tiny.

## finding 3 (blocker) — literal path overclaimed / NULL + TIMESTAMPTZ
untested — DECIDED 2026-07-23, addendum RUN

decision: spike addendum executed (`literal_matrix.jl`) — 27 cells,
all pass: full type matrix × {value, NULL} through the literal path,
NaN/Inf spellings, blob with embedded null/quote bytes, hugeint 2^100.
timezone policy (a) adopted and verified: julia DateTime ≡ UTC instant;
literals carry explicit +00; binding paths bind naive DateTime as UTC
even with session TimeZone = Pacific/Auckland in effect (measured, not
assumed). TIMETZ same contract. spike note §2b records the verified-for
list. gotcha recorded: literal serializer must be DuckType-directed
(blob vs UTINYINT[] dispatch collision).

## finding 4 (major) — "all dict-expressible types" unfalsifiable —
DECIDED 2026-07-24

decision: goal.md gets an explicit two-list criterion.
supported v1 (verified through the literal path; primitives also via
binding paths): BOOLEAN, all integer widths signed+unsigned, FLOAT,
DOUBLE (incl. NaN/Inf), DECIMAL, VARCHAR, BLOB, DATE, TIME, TIMESTAMP,
TIMESTAMPTZ, TIMETZ, UUID, ENUM, LIST, STRUCT, MAP, and nestings.
(USMALLINT/UINTEGER/UHUGEINT enter via the phase 5 live fixture.)
diagnostic v1 (generation-time, span-aware, with reason): ARRAY, UNION,
BIT, INTERVAL, JSON, GEOMETRY, TIMESTAMP_S/MS/NS.
promotion rule: a type joins the supported list only by passing the
round-trip harness; the goal list and the harness matrix are the same
list.

SIMPLIFIED 2026-07-25 (user direction): a hard two-list split —
dbdict-supported / dbdict-unsupported. an unsupported type encountered
in dbdict.yaml → error. an unsupported type encountered in a mapping
file → error.

LISTS CONFIRMED 2026-07-25 (grounded in the driver study,
notes/20260725-1007-duckdb-jl-driver-study.md; DuckDB.jl 1.5.2 is the
latest registered release, verified against the General registry):
- supported: BOOLEAN; TINYINT/SMALLINT/INTEGER/BIGINT;
  UTINYINT/USMALLINT/UINTEGER/UBIGINT; HUGEINT/UHUGEINT; FLOAT/DOUBLE;
  DECIMAL(w,s); VARCHAR; BLOB; DATE; TIME (µs contract); TIMESTAMP
  (ms contract); TIMESTAMPTZ (UTC contract); TIMETZ (UTC contract);
  UUID; ENUM; LIST; STRUCT; MAP; and their nestings
- unsupported (error at both intake points): ARRAY, UNION, INTERVAL,
  BIT, GEOMETRY, JSON, TIMESTAMP_S, TIMESTAMP_MS, TIMESTAMP_NS
- promotion: a type moves up only by passing the round-trip harness

driver-study consequences adopted for the plan batch edit:
- LIST columns write via the literal tier always (appender empty-vec→
  NULL corruption, no missing elements, non-ascii truncation bug)
- appender tier = scalar-only tables; silent appender errors → every
  generated writer ends with a row-count verification and raises
- never emit per-row prepared INSERTs, DuckDB.load!/appendDataFrame,
  DBInterface.lastrowid
- precision contracts documented in generated code: DateTime ≡ ms,
  Time ≡ µs (normalize explicitly on write), TIMESTAMPTZ/TIMETZ ≡ UTC
- bulk-replace = DBInterface.transaction + DELETE + write, appender
  flush inside the transaction; dedicated Connection per writer task
- readers accept Vector{T} and Vector{Union{Missing,T}} both; emit
  AS-alias per column (case decision, finding 6)
- streaming read (StreamResult + Tables.partitions) exposed for large
  tables as a reader option
- spike/study discrepancy to settle in phase 5 harness: appender blob
  (spike measured ERR; code has duckdb_append_blob wired)

## finding 5 (major) — parameterized defaults can't live in a plain
key→value data file — DECIDED 2026-07-24 (design refined with user)

decision, four parts:
- built-in defaults are CODE, not a data file: a rust function recursing
  over DuckType (structural mapping is an algorithm — recursion +
  parameter capture — not a finite key→value list). the compiled-in
  defaults file is dropped from phase 4
- LHS restriction (1:1 rule): a type_mappings key may only be a typedef
  name, a base type keyword, or exact DECIMAL(w,s). structural nested
  keys are illegal — nested overrides must be typedef-named in the dict
  first. kills nested-key matching logic in dbdict entirely
- RHS: verbatim julia type expressions. type_declarations entries are
  pure REFERENCES: {type?: expr (defaults to entry key), using?: pkg}.
  NO define: block — user julia code lives in user .jl files, loaded by
  the user; unresolved names fail julia-side as UndefVarError. generated
  module header comments list expected-in-scope names. closed-world
  check binds on the base identifier of the expression
- conversion contracts: read = RHS applied as constructor (RHS(v));
  write = DuckType-directed structural serialization (getproperty /
  iterate) — no user code needed on write
- test debt adopted: DECIMAL(38,6) (Int128-backed FixedDecimal) +
  USMALLINT/UINTEGER/UHUGEINT join the phase 5 live fixture

## finding 6 (major) — keyspace normalization — DECIDED 2026-07-24

resolved by earlier decisions plus measurements:
- case/whitespace/alias variance: canonicalize-then-match (finding 1)
- nested structural keys: abolished by LHS restriction (finding 5)
- typedef-shadows-builtin: THE ENGINE ENFORCES IT — measured: CREATE
  TYPE decimal/DECIMAL/varchar/int/text all rejected with Catalog Error,
  any case. dict validation's instantiation round-trip surfaces it
  already. work item: test pinning this + friendlier message if the raw
  Catalog Error reads badly. no keyword list in dbdict.
- case rules (cited, duckdb keywords_and_identifiers doc): keywords and
  identifiers both case-insensitive — quoted identifiers TOO (unlike
  postgres); case-preserving; ASCII comparison; same-name-different-case
  conflict → "one will be selected randomly"
- consequences adopted: companion→dict name matching is ASCII-case-
  insensitive; dict-level uniqueness (tables/columns/typedefs) should be
  ASCII-case-insensitive (verify core's current behavior in the hoist
  phase — engine picks randomly on conflict, julia is case-sensitive:
  never let it happen)
- measured: result sets use the DECLARED column spelling regardless of
  query spelling (even quoted), but an explicit AS alias's spelling
  wins → generated readers alias every column with the dict spelling,
  making julia-side names deterministic

## finding 7 (major) — goal.md vs impl.md companion structure mismatch —
PENDING (nested-under-tables is the defensible shape; goal.md is stale)

## finding 8 (major) — identifier safety (julia + sql sides) — PENDING

## finding 9 (major) — mixed-table tier logic; structarrays write-side
contradiction between spike §2 and §3 — PENDING

## finding 10 (major) — `dbdict gen julia` output model undefined — PENDING

## finding 11 (major) — phase 8 julia gate tests wrong condition —
DECIDED 2026-07-23 (jointly with finding 2)

decision: two-tier gate for the live test. julia binary absent → skip
with a loud message (workspace stays green on julia-less machines).
julia present but harness packages not instantiated → FAIL with the
exact fix printed (Pkg.instantiate command) — the likely real-machine
misconfiguration must not silently skip. harness Project.toml +
Manifest.toml committed to the repo (unlike the spike env).

## finding 12 (minor) — companion pairing undefined for fallback names —
PENDING

## finding 13 (minor) — phase 2 verify names nonexistent `dbdict
validate` subcommand — PENDING

## finding 14 (minor) — impl.md says DuckDB_jll 1.5.3, measured 1.5.2 —
PENDING

## finding 15 (minor) — goal.md pk phrasing table-level vs column-level
model; pk-on-struct-column edge — PENDING

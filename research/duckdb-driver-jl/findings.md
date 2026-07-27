# DuckDB.jl 1.5.2 — probe notebook (phases 1 and 2)

> **This file states no verdicts.** It is the record of *how* the driver findings
> were arrived at: what each probe set out to settle, what confounded it, and how
> far each boundary was actually pushed. Every result, capability table, code recipe
> and correction it once carried now lives in [`reference.md`](reference.md), which
> is the single source of truth.
>
> To learn how DuckDB.jl behaves, read `reference.md`. Read this only to judge how
> much weight a claim there can carry, or before re-running a probe.
>
> Section references are to **this file** unless prefixed: `ref §N` is
> `reference.md`, `spike §N` is `.claude-work/notes/20260723-1530`, `study §N` is
> `.claude-work/notes/20260725-1007`. Corrections this work made to the spike and
> the study are collected in ref Appendix A.

Conditions these observations were made under: julia 1.12.6, DuckDB.jl 1.5.2,
DuckDB_jll 1.5.4, engine `version()` = `v1.5.4`, `Threads.nthreads()` = 1; driver
source `~/.julia/packages/DuckDB/2J7sd/src/`. The environment contract is ref §2;
re-run instructions are ref §9.

---

## 1. Appender + BLOB — the spike/study discrepancy

**Script:** `verify_blob_appender.jl` → **ref §5.1.1**

**Question.** The capability spike (spike §2) measured appender × blob = `ERR`; the
driver study (study §3a) found `duckdb_append_blob` wired at `appender.jl:94`. Which
is right?

**The confound.** "Does the appender accept blob bytes" cannot be settled with one
payload, because three payload classes fail at three different layers:

- **ASCII bytes** round-trip — and so prove less than they appear to.
- **Valid non-UTF-8 bytes** are rejected by DuckDB's UTF-8 validation, inside the
  engine.
- **Bytes containing `0x00`** are rejected by Julia's `Cstring` conversion, before
  any C call happens.

The first probes were therefore measuring those two layers rather than the
VARCHAR→BLOB cast under test. Only re-declaring the C entry point with `Ptr{Cvoid}`
isolates the cast itself, which is what made the verdict decidable.

---

## 2. Appender + ENUM, and the stringify-cast family

**Script:** `verify_enum_appender.jl` → **ref §5.1.2** (silent failure and
misalignment), **ref §4.5** (the tier's type table)

**Question.** Study §3a / gotcha 12 marked "appender writes ENUM by appending a
string" as *Inferred*, extrapolated from the UUID stringify path (`appender.jl:93`).
Measure it — and, since §1 had just shown the sibling VARCHAR→BLOB cast succeeding
only for a narrow slice of inputs, measure the other stringify paths (`UUID`,
`FixedDecimal`) alongside it rather than trusting the same extrapolation twice.

**Why the probe needed a multi-column table.** The first design used a single ENUM
column, and it hid the result. Appending `["sad","ok","banana","happy"]` returned
`["sad","ok","happy"]` — indistinguishable from "the invalid row was dropped", which
is the benign reading. Adding a second column made the appender's column cursor
observable, and the real behaviour appeared: surviving rows carry *other rows'*
values. A probe whose output is consistent with the benign hypothesis is not
evidence against it.

---

## 3. Appender flush vs. the connection's transaction

**Script:** `verify_appender_transaction.jl` → **ref §5.1.3**

**Question.** Study §5 recorded "appender flush participates in the connection's
active transaction" as *Inferred*, justified only as "standard DuckDB appender
behavior". The generated bulk-replace pattern (`BEGIN; DELETE FROM t; <append>;
COMMIT`) is atomic only if that holds, so an inference was not good enough to build
codegen on.

The probe outgrew that question. The flushed-row scenarios confirmed the study
immediately; the informative cases turned out to be the *unflushed* ones, which the
study had not considered, and which is where the leak lives.

---

## 4. StructArray through `register_table`

**Script:** `verify_structarray_register.jl` → **ref §4.2**, **ref §4.3**

**Question.** Does the Tables.jl route accept a `StructArray`, and where exactly does
it stop? This underpins the spike's path E — register the struct's leaf fields as
flat columns, reassemble the struct in SQL.

**How far the boundary was pushed.** The cases tried, so a re-runner knows what has
and has not been probed:

- flat `StructArray(id::Int32, name::String, score::Float64)`
- nullable field `Union{Missing,Int32}`
- nested field `loc::StructArray(x,y)` — column eltype `@NamedTuple{x,y}`
- `UUID` field
- list field `Vector{Int32}`

Path E was then run end to end rather than assumed to follow: 2 rows written, first
row read back as `(x = 1.0, y = 3.0)`.

This section also refuted the study's §3c claim about *when* the failure is
observed — see ref Appendix A.

---

## 5. Appender + LIST segfaults the process

**Script:** `verify_list_appender_gc.jl` → **ref §5.1.4**

**Not a planned verification.** It was found when the phase-2 benchmark harness died
while timing the `list`/`appender` cell — a crash in the measuring instrument, not a
result any probe set out to get.

**Harness internals a re-runner needs.** The GC hypotheses were tested through
`verify_list_appender_gc.jl`'s `midbatch` mode, which forces a collection while rows
are still buffered, pre-flush. The benchmark suite excludes the `list`/`appender`
cell via `skip_reason` in `bench_common.jl`, with the crash as its stated reason, so
`results.md` reports it as an explicit exclusion rather than a blank.

Two hypotheses were tested and neither was confirmed. Both, the reason each arm was
uninformative rather than negative, and why root-causing was left undone are all
recorded in ref §5.1.4 — read them there before re-running either.

---

## 6. Literal SQL silently loses 1 ULP on DOUBLE

**Script:** `bench_common.jl` (`sqllit`) → **ref §5.2.1**

**Also unplanned**, and surfaced the same way as §5: the benchmark harness's own
content gate failed at `flat` / 1M / `literal`. Neither of the two phase-2 findings
was on the plan — both exist because the harness checked what it had written instead
of only timing it.

The six literal forms measured, and the serializer rule they produce, are in
ref §5.2.1.

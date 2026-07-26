---
created: 2026-07-26T13:22:37+12:00
title: benchmark harness caught two driver defects
tags: [duckdb, julia, gotcha, verification, debugging]
source: /ws done
---

## reading the source located the crash before any test ran

- `create_value(::AbstractVector)` builds `type = create_logical_type(T)` and `values = create_value.(val)`, then passes `type.handle` and the raw child handles into `duckdb_create_list_value`. Both `type` and `values` are finalizer-owned Julia objects (`value.jl:9`, `logical_type.jl:10`) that are **dead after their `.handle` fields are read** — with no `GC.@preserve` guarding the call.
- That's the classic Julia FFI lifetime bug: the GC may run `_destroy_type`/`_destroy_value` while DuckDB is still dereferencing those pointers. A use-after-free on a `LogicalType` is exactly what would crash inside `StructType::GetChildTypes`.
- It's timing-dependent, which is why the n=1000 smoke test passed and a 4800-sample benchmark did not. "The list append path works" is true only until the GC lands badly.

> outcome: the hypothesis was NOT confirmed. see the next two sections — the
> reasoning was plausible and the test design was the problem.

## a test that cannot fail is not evidence

- Forcing `GC.gc()` *between* batches can never test a race that occurs *during* a ccall. The dangerous window is a collection triggered naturally mid-loop, concurrent with `duckdb_create_list_value` — my "force GC at a safe point" test could only ever pass, and disabling GC removed finalizers entirely, so both arms were uninformative.
- The real independent variable is sustained allocation pressure with GC left to fire on its own. My repro did 80k list appends; the benchmark did roughly 10M before dying.

**Why it matters:** two arms both "passed" and neither carried information. Before
believing a negative result, ask what the test would have done if the hypothesis
were true. A second, subtler instance followed: the H2 `midbatch` test appended
only ~40k values against a ~1M crash threshold — underpowered, not refuting.

## the discriminator was the path that DIDN'T crash

- Both paths call `create_value`, yet only the appender dies — so this isn't a race *during* the ccall. The appender **buffers rows until flush**, so it must still reference the `duckdb_value` after `append` returns. But the Julia `Value` goes out of scope at the end of `append` (`appender.jl:106-114`) and its finalizer calls `duckdb_destroy_value`. The bind path survives because `execute` consumes the value before returning.
- That also explains why my earlier forced-GC test passed: it collected *after* `flush`, when the appender no longer held the values.

**Method note:** the prepared-bind control was worth more than any amount of
further appender testing. When two call sites share a code path and only one
fails, the shared code is exonerated and the difference between the call sites
is the whole search space.

## duckdb parses bare decimal literals as DECIMAL, not DOUBLE

- `SELECT 0.11914626526441173` returns a **`DECIMAL(_,17)`**, not a DOUBLE — DuckDB parses bare decimal literals as DECIMAL. So `sqllit(::Float64) = string(v)` emits a DECIMAL literal, and writing it into a DOUBLE column round-trips through DECIMAL.
- Adding `::DOUBLE` doesn't rescue it: the literal is parsed as DECIMAL(17,17) *first*, then cast, and 17 fractional digits can't uniquely identify a Float64 — hence the **1-ULP loss**. More `%.17g` digits don't help for the same reason.

Fix: `@sprintf("%.17e", v)` — exponent notation selects the DOUBLE parser
directly. Verified exact over 2005 values incl. `0.0`, `-0.0`, `1e308`,
`5e-324`, `1/3`.

**Why it matters beyond this harness:** any generated SQL writer emitting
`string(x)` for floats corrupts data silently — no error, no warning, wrong in
the last bit. It was caught only because the benchmark harness content-verifies
writes instead of trusting row counts (itself a lesson carried from phase 1's
column-misalignment finding).

## measured: the driver study's default write tier was wrong

`register_table` + `INSERT … SELECT` beats the Appender by 3.4x at 1M rows
(58.1 ms vs 196.0 ms) and allocates 538x less (14.8k vs 8.0M allocations) —
the appender costs one Julia allocation per cell. The study had recommended the
appender on the strength of DuckDB's docs. Crossover is between 10k and 100k
rows; below it the appender wins.

Also measured: `-t auto` (64 threads) is ~2x **slower** than 1 thread at every
scale, because DuckDB inherits Julia's thread count (`database.jl:81-82`) and
each query spawns a task per thread — overhead that never pays back here.

---
created: 2026-07-26T13:59:39+12:00
title: consolidating notes surfaces citation and headline drift
tags: [julia, duckdb, documentation, sourcing, verification]
source: /ws done
---

## merging sources of different evidence classes needs explicit markers

The merge has to resolve a **provenance conflict**, not just concatenate: the spike
measured behaviour, the study read source code, and phase 1 measured the things the
study only inferred — and they disagree in four places. A reference doc that flattens
all of it into one confident voice loses the ability to tell "we measured this" from
"we read this in the source." So the doc carries an explicit evidence marker on every
claim, and inference gets marked rather than silently promoted to fact.

One number needed correcting during the read-through: the phase-2 headline says the
appender/register crossover sits "between 10k and 100k." That's only true at 64
threads. At 1 thread `register` wins at **every** scale including 10k (1.015 ms vs
2.051 ms) — it's the one write ordering that flips between thread configs, so the
reference states it per-config.

## a compressed headline silently dropped its qualifying condition

The phase-2 headline "crossover between 10k and 100k, below that the appender wins" is
true only at 64 threads. At 1 thread `register` wins at every scale including 10k
(1.015 ms vs 2.051 ms) — it's the single write ordering that flips between thread
configs, stable within each. The reference states it per-config; `impl.md`'s phase-2
record still has the compressed version if you want it amended at `/ws done`.

## citation drift is invisible until something mechanically re-checks it

Phase 3 spot-checked its own source material rather than trusting it, and that is the
only reason two errors were caught. Both had already propagated.

**1. A wrong `file:line` in phase 1's own findings.** `findings.md` §3b credited the
appender finalizer to `appender.jl:59`; it is actually at `:56` (line 59 is a `DB`
constructor overload). By the time it was found it had spread to `impl.md`, a saved
*insight* file, and the new reference doc — four live documents, plus a state dump.
Auditing the other 26 load-bearing citations found them all exact, so this was a
one-off slip, not systemic — but a slip that a reader would have had no way to detect,
because a plausible line number in a plausible file reads exactly like a correct one.

**2. A compat bound read as a pin.** Two notes and a held session's review finding all
recorded `DuckDB_jll 1.5.2`. That number is DuckDB.jl's own
`[compat] DuckDB_jll = "1.5.2"` — a *lower bound* (Julia's Pkg docs: "a version
specifier given as e.g. `1.2.3` is therefore assumed to be compatible with the versions
`[1.2.3 - 2.0.0)`"), not the resolution. Both Manifests resolve `1.5.4+0` and the engine
reports `v1.5.4`. The consequence was material: the spike's "storage format is
compatible 1.5.2 ↔ 1.5.4" check had actually run with the *same* engine on both sides,
so it never tested what it claimed to.

**The generalisable lesson:** the moment to verify citations is when consolidating
them, because that is the last point where the original source is still at hand and the
first point where errors start being copied rather than written. Verify by *executing*
where possible — re-running two verification scripts and tracing three benchmark
numbers back to the raw JSON was stronger evidence than re-reading any of them, and
took less time than reasoning about whether they were still true.

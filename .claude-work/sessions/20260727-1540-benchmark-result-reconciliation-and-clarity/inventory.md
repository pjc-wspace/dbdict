# §7 claim inventory

Every number-bearing claim in `reference.md` §7 (lines 1244–1405), plus every
benchmark-derived number restated outside §7. Line numbers are against
`reference.md` as of commit `b6cb54a`.

`inventory_check.py` enforces completeness: every digit-bearing line in §7 must
appear here, either as a claim row or in the ignore list at the bottom. Nothing
is silently unaccounted for.

**Kinds.** `cell` = a value in a §7 table · `derived` = computed from cells ·
`count` = a coverage/tally claim · `order` = an ordering or stability claim ·
`env` = environment or sweep configuration · `harness` = a property of the
benchmark source, not of its output.

**Checkable** = verifiable by `numbers.py` against `raw/*.json`. Anything `no`
carries the reason and the tool that does own it.

## amendment to goal.md

`goal.md` scopes "the two restatements of §7 figures outside §7 (§1 line ~75,
§8.1 tier preamble)". Rebuilding the map found **three**: the Appendix A
correction at L1586 also restates 3.4× and 538×, and adds a fourth claim
("wins at every scale at 1 thread"). Scope is unchanged in kind — all three are
in — but the count in `goal.md` was wrong and is corrected here.

## claims

| Line | Claim | Kind | Checkable | Notes |
|---|---|---|---|---|
| L1250 | BenchmarkTools.jl **1.8.0** | env | yes | `environment.benchmarktools` |
| L1250 | 5-second budget caps sample count | harness | no | property of BenchmarkTools defaults, not of the output |
| L1251 | large cells get as few as **1 sample** | derived | yes | `min(samples)` over ok cells |
| L1255 | scales **10,000 / 100,000 / 1,000,000** | env | yes | distinct `scale` values |
| L1261, L1263 | profile DDL table (`DECIMAL(18,4)`, `1–4` elements, …) | harness | no | lives in `bench_common.jl`; JSON records only profile names |
| L1269 | paths measured; **prepared bind and per-row INSERT not measured** | env | yes | distinct `path` values per kind |
| L1270 | `literal` batched at **1000 rows** per statement | harness | no | `bench_common.jl:225`; not in output |
| L1271 | thread configurations **1 and 64** | env | yes | distinct `environment.threads` |
| L1273 | **2 repeats** per configuration | env | yes | runs grouped by threads |
| L1278 | **84 cells** per run × **4 runs**; **60 measured, 24 skipped, 0 failed** | count | yes | per-run tallies by status |
| L1279 | **9** `register_flat` cells per run skipped as not-applicable | count | yes | status+reason match |
| L1289–L1300 | §7.2 write table — 12 rows × 4 paths | cell | yes | median · rows/s · allocs; ❌ / n/a / excluded markers must match `skipped` cells |
| L1305 | `register` **3.4×** faster than appender at flat/1M (**58.115 vs 195.964 ms**) | derived | yes | ratio of medians |
| L1306 | **538×** fewer allocations (**14,853 vs 7,996,936**) | derived | yes | ratio of allocs |
| L1306–L1307 | **328×** less memory (**380.672 KiB vs 122.024 MiB**) | derived | yes | ratio of memory_bytes |
| L1310 | appender allocs ≈ **8 per row** on a **5-column** profile (**~1.6 per cell**) | derived | yes | allocs/scale; column count from the DDL is `harness`, the arithmetic is checkable |
| L1311 | rich rises to **~20 per row** over **4 columns** | derived | yes | same |
| L1314 | `literal` **2–3 orders of magnitude** behind everywhere | derived | yes | ratio bounds across all cells |
| L1314–L1315 | **304×** slower than `register` at flat/1M; allocates up to **1.705 GiB** | derived | yes | ratio + max memory_bytes |
| L1321–L1326 | §7.3 read table — 6 rows × 3 paths | cell | yes | medians |
| L1328–L1329 | **246 µs** at 10k → **420 µs** at 1M; **100×** data for **1.7×** latency | derived | yes | stream_first medians; note U+00B5 here vs U+03BC in results.md |
| L1339 | flat/1M allocation **58.541 vs 59.143 MiB** | derived | yes | memory_bytes, materialized vs streaming |
| L1344 | raising threads **1 to 64** helped nothing materially | derived | yes | restates L1271 + the table below |
| L1347–L1356 | §7.4 thread table — 8 rows, both values + stated change | cell + derived | yes | includes `~unchanged` and `7% faster` |
| L1358 | three cells improved, all by **≤7%** | derived | yes | count + bound over 64-vs-1 ratios |
| L1365–L1367 | `Inferred:` ROW_GROUP_SIZE = **204,800**; 1M rows ≈ **~5 blocks** | harness | no | driver source, already marked `Inferred:`; `citations.py` owns the cites |
| L1375 | writes: **all 24** orderings reproduced | order | yes | across repeats within each thread config |
| L1376 | reads: **22 of 24** reproduced | order | yes | same |
| L1382 | 1 thread · read · struct · 1M flipped (**854.118 vs 865.208 ms**) | order + cell | yes | named cell must be one of the non-reproducing pair |
| L1383 | 64 threads · read · flat · 10k flipped; `materialized` last in both runs | order | yes | same |
| L1391–L1393 | write · flat · 10k ordering differs between configs | order | yes | both orderings from the data |
| L1395–L1397 | at 1 thread `register` wins **every scale including 10k**; at 64 threads appender wins at 10k, `register` from **100k** up | derived + order | yes | per-scale winner |

## restatements outside §7

| Line | Claim | Kind | Checkable | Notes |
|---|---|---|---|---|
| L75–L76 | §1: **3.4×** faster, **538×** fewer allocations at 1M, beats appender at **every** scale tested | derived | yes | must equal L1305–L1306; "every scale tested" must equal L1395 |
| L1430 | §8.1: tier 1 fastest, **3.4×** the appender at flat/1M | derived | yes | must equal L1305 |
| L1586 | Appendix A: **3.4×** faster, **538×** fewer allocations, wins at **every scale at 1 thread** | derived | yes | third restatement, not in `goal.md`'s count |

## ignore list

Digit-bearing lines in §7 carrying no benchmark claim. Each is owned by an
existing audit, or is structural.

| Line(s) | Why ignored |
|---|---|
| L1244, L1246, L1283, L1317, L1342, L1373, L1399 | section headings |
| L1266, L1277, L1302, L1331, L1385, L1402 | cross-references to other sections — `anchors.py` owns these |
| L1272 | `database.jl:81-82` source citation — `citations.py` owns it |

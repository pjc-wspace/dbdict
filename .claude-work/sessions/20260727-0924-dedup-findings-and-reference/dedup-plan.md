# dedup decision table

Phase 1 output. Phases 2 and 3 execute this; phase 4 diffs against it.

Baseline: `inventory-before.tsv` — **1021 claims** (findings.md 256,
reference.md 765) across 59 heading contexts. Heading coverage is complete: every
heading in either file contributes claims, except five section containers in
reference.md (`3. Reading`, `5. Defects and traps`, `5.1 Driver defects`,
`5.2 DuckDB engine behaviour`, `7. Benchmarks`) verified to have zero body lines.

## Method note — two false trails, recorded so they are not re-run

1. **Line-level similarity is the wrong unit.** `crossmatch.py` compared claims
   line by line and returned 113 "unique" lines, nearly all false positives: the
   two files state identical facts with different sentence breaks, so no single
   line pairs up. `matched-findings.tsv` is kept as evidence, not as input.
2. **Distinctive-token coverage is the right unit.** `tokencov.py` asks whether
   each anchor a claim rests on — `file.jl:NNN`, backticked identifiers, C error
   strings, measured numbers — appears anywhere in the other file. Tokens survive
   rewrapping and rewording. It needed one fix: collapse whitespace on both sides,
   because a token wrapped across a line break in the target read as absent.

Result: of 256 source tokens, **23 citations (2 absent), 9 error strings (3
absent), 158 identifiers (27 absent), 66 numbers (7 absent)**.

---

## A. UNIQUE-SUBSTANTIVE — move into reference.md BEFORE cutting findings.md

`goal.md` orders phase 2 this way for exactly this reason. Six items.

| # | Content | Now only in | Move to | Why it matters |
|---|---|---|---|---|
| A1 | **The six-row literal-form table** — `%.17g` bare → `FixedDecimal{Int64,17}`; `%.17g` + `::DOUBLE` → **still 1 ULP low**; `'…'::DOUBLE` quoted → exact; parser picks `DECIMAL(_,17)` | findings §6 (L344-360) | reference §5.2.1 | **The phase-3b rewrite dropped it.** §5.2.1 now asserts "adding digits does not help" with no evidence, and names the quoted-string fix without ever showing it. This is real loss already incurred, not a hypothetical |
| A2 | `table_scan.jl:201` — the line where `register_table` stores `columntable(tbl)` | findings §4c (L231) | reference §4.2 | §4.2 credits alias-based registration to the verify script but cites only the coarse `table_scan.jl:200-208`. The precise line is the code evidence for the zero-copy claim |
| A3 | C error text `Invalid unicode (byte sequence mismatch) detected in value construction` | findings §1 (L73) | reference §5.1.1 | The observable proof that a String-cast blob append fails silently. Anyone writing the polling wrapper will see this string |
| A4 | C error text `Call to EndRow before all columns have been appended to!` | findings §1 (L75) | reference §5.1.2 | This is *how you detect* a mis-aligned row from the error slot — directly actionable for §8.2 rule 4 |
| A5 | `Failed to cast value: Unimplemented type for cast (INTEGER -> ENUM(...))` | findings §2b (L131) | reference §5.1.2 | The second-order error in the misalignment cascade — evidence for *why* it stops where it does |
| A6 | Concrete over-precision case: `FixedDecimal{Int64,4}(12.3456)` into `DECIMAL(18,2)` → `12.35` | findings §2 (L109-112) | reference §4.5 | §4.5 says "over-precision silently rounds" with no instance. A concrete case makes the rule checkable |

## B. PROVENANCE — keep in findings.md, this is its remaining job

| Content | Why it stays |
|---|---|
| The `Question.` framing opening §1–§4 | Why each probe was run at all — the one thing reference.md deliberately omits |
| Single-column ENUM control: `["sad","ok","banana","happy"]` → `["sad","ok","happy"]` | Explains *why* the probe needed a multi-column table. The design rationale, not the finding |
| Three blob payload classes (ASCII / non-UTF-8 / with-NUL) | The confound: the first two probes measured Julia's `Cstring` conversion and DuckDB's UTF-8 validation, neither of which is the cast under test |
| ~~§5b hypotheses H1/H2 and why each arm was uninformative~~ | **CORRECTED in phase 2 — this row was wrong.** reference.md §5.1.4 already carries H1 and H2 in full, including "both arms were uninformative" and "underpowered, not a refutation". They are *not* omitted there, so keeping them here would recreate the duplication this session exists to remove. findings.md points at ref §5.1.4 instead. `goal.md` names them as a findings.md keeper on the same mistaken premise |
| StructArray probe cases (`StructArray(id,name,score)`, `loc::StructArray(x,y)`) | Which cases were tried, i.e. how far the boundary was actually pushed |
| `midbatch`, `skip_reason` harness internals | Names the mechanism a re-runner needs |
| Findings' own run values (`(x = 1.0, y = 3.0)`) | reference.md has its own executed values; keeping both is fine as history |

## C. CUT from findings.md — duplicated conclusions

Verdict lines · probe result tables · root-cause mechanism prose · the `ccall`
recipe (superseded — reference.md §5.1.2 has the correct wrapper, and findings'
comment about needing a hand-rolled `ccall` is **wrong**) · the phase-1 summary
table · the "corrections to the driver study" list (now reference.md Appendix A) ·
transcripts reference.md reproduces.

## D. INTRA-REFERENCE single-sourcing (phase 3)

Mention counts. Allowed = §1 one-clause + pointer, §8.2 action row + pointer,
Appendix A correction entries, comments inside executed examples.

| Fact | Mentions | Sections | Canonical home | Action |
|---|---|---|---|---|
| LIST segfault | 15 | 12 | §5.1.4 | §7.2's "excluded by policy, not measured to crash at 10k" is a real clarification — move it into §5.1.4 and point from §7.2. §8.4's paragraph → one clause |
| blob `Ref{Cvoid}` | 11 | 7 | §5.1.1 | §4.5 table row stays; Appendix A entries stay; check §4.4's example comment does not re-explain the mechanism |
| column misalignment | 10 | 7 | §5.1.2 | §8.1's tier-4 guard prose → pointer |
| appender GC leak | 11 | 7 | §5.1.3 | §5.1.4 mentions it incidentally — verify that is a pointer, not a restatement |
| chunk `columnnames` | 6 | 4 | §5.1.6 | Already lean; example comments are legitimate |
| 1 ULP / `%.17e` | 9 | 6 | §5.2.1 | §4.6's two serializer requirements restate it — reduce to pointer, keep the DuckType-dispatch requirement which is *not* duplicated |
| register 3.4×/538× | 6 | 4 | §7.2 | §8.1 restates the numbers; keep one ratio + pointer |
| threads hurt | 10 | 5 | §7.4 | §2 and §7.1 mention it as context — check for restatement |
| empty vec → NULL | 7 | 5 | §5.1.5 | §7.1's methodology note explains *why the list profile avoids them* — that is provenance for the benchmark, keep |

## E. Verification contract for phase 4

- `inventory-after.tsv` vs `inventory-before.tsv`: every dropped claim is in
  section C, or present in reference.md, or listed here as a deliberate cut
- all 14 julia blocks execute; documented output matches; block hash recorded
- every `file:line` re-resolves; every anchor resolves under both conventions
- §4.1 / §8.1 / §8.2 agree row for row
- `tokencov.py` re-run: section A items must no longer appear as absent

---

## F. Phase 2 execution record

All six §A items moved into reference.md **before** any cut, then findings.md was
reduced: 404 → 139 lines, 19,445 → 6,246 chars (68% smaller). reference.md
1549 → 1593 lines, 78,029 → 81,551 chars.
Claim inventory: findings 256 → 94, reference 765 → 800.

Landing sites: A1 → §5.2.1 (six-row table plus a note that "reads back as" is the
Julia type, since the example prints the SQL type) · A2 → §4.2 · A3 → §5.1.1 ·
A4, A5 → §5.1.2 · A6 → §4.5.

### Deliberate cuts, verified accounted for

`tokencov.py` was re-run with the **pre-cut findings.md** as source and
`findings.md + reference.md` concatenated as target — the direct "was anything
lost" test. Absent tokens fell from 39 to 8 distinct; acting on the `sqllit` one
took it to **7 at the phase-2 gate**, every one accounted for:

| Absent token | Accounting |
|---|---|
| `table_scan.jl:201-205` | findings' range for the view creation; reference.md §4.2 cites the wider `table_scan.jl:200-208` for the function and `:201` for the store. Superseded, not lost. Phase 4 pass 2 re-resolves both against the driver source |
| `DuckDB.append(ap, ::Vector{UInt8})` | §C probe-table cell. Fact in reference.md §5.1.1 prose and the §4.5 table row |
| `duckdb_appender_error(handle)` | findings' incidental-defect note; reference.md §5.1.2 states it as "(`appender.jl:46`) passes the `Ref` box instead" |
| `"happy"::String` | §C probe-table cell. reference.md §4.5 covers the ENUM label contract |
| `"Happy"` | §C probe-table cell. reference.md §4.5: "Invalid and **wrong-case** labels are silently lost" |
| `DECIMAL(_,17)` | findings' placeholder; reference.md carries the precise `DECIMAL(18,17)` |
| `sqllit(::AbstractFloat)` | **acted on** — reference.md §5.2.1 named this only as "the `%.17e` method at line 32"; now named and cited as `bench_common.jl:32` |
| `1.5.2.` | tokenizer artifact (trailing period); version pinned in reference.md §2 |

### Other phase-2 verification

- `tools/vruns.py` added — exact shared-substring check on whitespace-normalized
  text, which is what "no verbatim run over N chars" actually asks. **0 runs ≥ 120
  chars**; tightened to 60 it found one 78-char run this rewrite had itself
  introduced (the out-of-scope sentence in §5), now cut. **0 runs ≥ 60 chars**
- findings.md: 0 code fences, 0 table rows, no verdict lines
- reference.md's 14 julia blocks are **byte-for-byte unchanged** (sha256 per block,
  diffed against `HEAD`) — no edit touched executable content
- all 45 internal anchors resolve against the 101 headings

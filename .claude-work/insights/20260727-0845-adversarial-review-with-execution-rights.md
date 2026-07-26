---
created: 2026-07-27T08:45:29+12:00
title: adversarial review with execution rights
tags: [adversarial-review, verification, documentation, testing, duckdb]
source: /ws close
---

## auditing citations is not auditing claims

Phase 3 audited every `file:line` in a 1,100-line reference doc and found exactly one
wrong. That felt like diligence. An adversarial pass then found **twelve** substantive
errors, five of them critical, and confirmed ~100 of the citations clean — so the
citation audit had been *correct and nearly worthless*. Everything it caught was in
the one dimension it checked.

The five criticals sat in four blind spots a citation audit structurally cannot see:

1. **Internal contradiction.** A tier-selection table routed BLOB columns to the
   appender while three other sections of the same document said the appender's BLOB
   method throws before reaching C. Both statements had correct citations. The
   contradiction existed only *between* them — and only because tier guidance had been
   written in two places. The durable fix was single-sourcing the table, not correcting
   the row.
2. **Provenance of the evidence marker itself.** A claim marked *measured* ("per-row
   prepared INSERTs are the slowest path") was never benchmarked — the harness had four
   paths and none of them was per-row. Marking a claim as measured is itself a claim,
   and nothing was checking it.
3. **Derived counts.** "34 of 36 read orderings reproduced" was arithmetic over a table
   that has 24 read orderings. No citation is attached to a number you computed
   yourself.
4. **Claims inherited uncorrected from a source.** "Empty vector appends/binds as NULL"
   came from the study and was half wrong — prepared bind writes a real `[]`. It was
   faithfully carried forward, citation and all.

**Why:** a citation check asks "does the cited line say this?" It never asks "is this
claim true", "does it agree with the rest of the document", or "was this actually
measured". Those are different passes and need to be run deliberately.

**How to apply:** when consolidating or reviewing a document, run four passes, not one
— citations, internal consistency, evidence-provenance (spot-check things marked
*measured* against the harness that supposedly measured them), and derived numbers.
Grep for absolutes (`never`, `every`, `no cell`, `always`) and check each against the
data; two of the five criticals were overstated absolutes contradicted by the
document's own tables a few lines later.

## give reviewers the ability to execute, not just to read

The three reviewers were each handed the pinned Julia environment. That single choice
is what separated opinion from finding:

- The examples reviewer ran every code block and found that two of the seven "code"
  blocks were fragments, that no `using` line existed anywhere, and that the obvious
  `using DuckDB, DBInterface` **fails** because `DBInterface` is a transitive dep — a
  defect nobody discovers by reading.
- It found a genuine new driver bug by *probing beyond the doc*: a streamed chunk
  declares `Tables.columnaccess` true, but `getcolumn`/`schema` throw and
  `columnnames` returns `(:tbl,)` with **no error at all** — a silently wrong answer on
  the exact path the doc recommends for large tables.
- It falsified a benchmark generalisation by constructing the case the harness never
  ran: streaming's "latency is flat in table size" holds only for pipeline-able
  queries; add `ORDER BY` and first-chunk time goes 0.72 ms → 6.75 ms.

**Why:** a reader can only check a document against itself. An executor checks it
against the world, and can test the cases the original author didn't think to run —
which is precisely where the unknown-unknowns live.

**How to apply:** never accept reviewer findings on trust either — every one of the
twelve was re-verified here before being acted on, and the re-verification is what made
the correction defensible. Then close the loop: after fixing, extract every code block
from the finished document, run them all, diff actual output against documented output,
and hash the blocks against what was executed so "the examples are tested" is a
checkable fact rather than a claim. One documented output line was wrong (a missing
`Tuple{Int32, String}` prefix) and only that diff caught it.

See [[consolidating-notes-surfaces-citation-and-headline-drift]] for the earlier,
weaker version of this lesson — that one concluded "verify when consolidating", which
was right but insufficient: it verified the wrong dimension.

# §8.1's tier-3 precondition omits prepared bind's own type gaps

created: 2026-07-27T13:06:35+12:00
status: **open follow-up — not fixed this session**
found: phase 3 of `20260727-0924-dedup-findings-and-reference`, by the
`§4.1 / §8.1 / §8.2 must agree` check

## the gap

`reference.md` §8.1 states tier 3's precondition as:

> | 3 | **prepared bind** | the table has a BLOB column, or a LIST column at bulk scale | appender (§5.1.1, §5.1.4) |

That rule selects prepared bind on the basis of *one* column's type, but prepared
bind has type gaps of its own, which the document records in three other places:

- §4.1 capability matrix — `DECIMAL` × prepared bind = ❌, `UUID` × prepared bind = ❌
- §4.4 — "**Gaps vs the appender**: no `Int128`, `UInt128`, `UUID`, `FixedDecimal`,
  interval"
- §5.3 API traps — "UUID / DECIMAL write as strings via the appender, relying on
  C-appender casts; **bind supports neither**"

So a table with **BLOB + DECIMAL**, or **BLOB + UUID**, selects tier 3 by §8.1 and
then cannot write the second column. The `BLOB + UUID` combination is worse than a
tier misselection: bind cannot write UUID, the appender cannot write BLOB, and
`register` covers neither — literal SQL (tier 5) is the only path that works, which
§8.1 reaches only via its "anything else" catch-all, and only if the generator
notices the conflict at all.

The `rich` benchmark profile (`id INTEGER, u UUID, d DECIMAL(18,4), s VARCHAR`,
§7.1) is one column away from being exactly this case.

## why it matters

This is the same defect *class* as the BLOB contradiction fixed last session: the
summary tier table not agreeing with the capability matrix it summarizes. §4.1 has
the facts right, row by row. §8.1 compresses them into a per-table rule and loses the
per-column constraint in the compression. A generator author working from §8.1 alone
— which §8.1 is explicitly designed to allow — gets a tier that cannot write the
table.

Tier preconditions are per-*table* predicates over per-*column* capabilities. Any
such rule needs to be a conjunction across all columns, not a test on the column that
triggered it.

## why it was not fixed here

`goal.md` scope: "**out:** rewriting `reference.md`'s substance — this is a
restructuring pass, not a second rewrite", and "if a gap or a wrong claim surfaces,
record it as a follow-up; do not go and measure it".

Fixing it means rewriting tier-selection guidance, which is a codegen decision, not a
deduplication one. No new measurement is needed — every fact required is already in
the document — but the *decision* belongs to the held codegen session
(`20260723-1109-julia-read-write-codegen`), for which `reference.md` is the
resumption gate.

## what a fix would look like

Options, for whoever picks this up:

1. Restate tier 3's precondition as a conjunction — "*every* column is in bind's
   coverage, **and** at least one is BLOB or bulk LIST" — and add the symmetric
   qualifier to tier 4.
2. Add a "mixed-type fallback" row above tier 5: any table whose columns cannot all
   be served by one tier goes to literal, with a pointer to §4.1.
3. Leave §8.1 as the fast path and add one sentence under the tier table stating
   that tiers 1-4 assume all columns clear the tier's ceiling, with §4.1 as the
   authority.

Option 3 is the smallest change that removes the contradiction, and does not commit
the codegen session to a strategy.

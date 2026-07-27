# §8.1's tier-3 precondition omits prepared bind's own type gaps

created: 2026-07-27T13:06:35+12:00
status: **RESOLVED 2026-07-27T13:32:18+12:00 — fixed in reference.md on user direction**
found: phase 3 of `20260727-0924-dedup-findings-and-reference`, by the
`§4.1 / §8.1 / §8.2 must agree` check

> **Scope note.** This was recorded as an out-of-scope follow-up per `goal.md`
> ("out: rewriting `reference.md`'s substance"). The user overrode that and
> directed the fix in-session. See "what was actually done" at the end — the fix
> turned out to require no new decisions, because every fact it needed was already
> in §4.1; only the *quantifier* was missing.

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

---

## what was actually done (2026-07-27, user directed the fix in-session)

Options 1 and 3 combined, because they turned out not to be alternatives: making the
preconditions conjunctive is a statement of *fact* derivable from §4.1, not a strategy
choice, and the guard sentence names the authority.

1. **Tiers 3 and 4 restated as conjunctions**, symmetric with tiers 1 and 2 which
   already read "**every** column's Julia type is in…". Both now test membership in
   §4.1's own column for that path, rather than enumerating a list inline.
   - *A first attempt enumerated bind's gaps as "no `Int128`/`UInt128`, `UUID`,
     `DECIMAL` or interval" — copied from §4.4's "Gaps vs the appender". That
     reproduced the very bug being fixed: bind also cannot write STRUCT, MAP or
     nested LIST, so the list was partial and would read as complete.* The cells now
     point at §4.1 and flag the notable exclusions as *notable*, not exhaustive.
2. **Guard sentence added** under the tier table: every precondition is a conjunction
   over all columns, §4.1 is the authority, and a table no single tier covers falls to
   tier 5. `BLOB + DECIMAL` and `BLOB + UUID` are named as the cases that catch it.
3. **Tier 5's "anything else"** extended to say it also absorbs any table no single
   tier above can cover, so the fall-through is explicit rather than implied.

### three further contradictions found by the same sweep, all fixed

Looking for more of the same class rather than stopping at the reported one:

- **§1 contradicted itself in a single sentence** — "no single path covers the type
  matrix" followed by "Only literal SQL covers everything." §4.1 shows literal is ❌
  for `ARRAY` and read-only for `INTERVAL`. Now states the two exceptions.
- **§4.4 claimed "bind is the only working path for BLOB"** — §4.1 shows literal
  writes BLOB too, and qualifies bind as the only working *bulk* path. The
  unqualified form would route a small-table BLOB write away from a path that works.
- **§8.1 undercounted tier 4's guards as four** — rules 1-4 are the structural ones,
  but §8.2 rules 10 (wrong-case ENUM) and 11 (over-precision `FixedDecimal`) are also
  appender-specific. Now six, split into structural and value-level, noting the
  value-level pair is exactly what a row count cannot detect.

### verification after the fix

0 tokens absent across citations, error strings, identifiers **and numbers** against
the pre-fix commit; all 14 julia blocks unchanged; 46/46 anchors resolve.

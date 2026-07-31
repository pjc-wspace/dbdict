---
created: 2026-07-31T12:19:43+12:00
title: dataspec re-baseline — type systems, extensibility, and inference
tags: [spec-design, duckdb, storage, type-conversion, product-strategy]
source: /state save
---

## measuring the substrate is the design telling you something

When a project spends a week measuring its *substrate* rather than building on
it, that's usually the design telling you an assumption is load-bearing and
unexamined. dbdict's architecture rule ("the core is a pure library; generators
consume the model") was written to keep backends swappable — but every crate
downstream of it (`dbdict-duckdb`, `dbdict-ddl`, `dbdict-dummy-data-duckdb`)
hard-assumes DuckDB, and validation is *defined* as "round-trip through
in-memory DuckDB and diff `DESCRIBE`". So the abstraction exists on paper but
the DuckDB dependency is baked into the validation semantics, not just a
backend crate.

## relational and array workloads want opposite things

dbdict is a **relational schema** tool — typedefs, primary keys, foreign keys,
cardinality, referential integrity, dummy-data generation. But the JLD2 probes
are **array/scientific** workloads: a 2M-row StructArray of eight `Float64`
fields, benchmarked for round-trip time and compressed size. Relational wants
constraints, joins, and a query engine; wide numeric arrays want columnar
layout, compression ratio, and fast bulk write-once/read-many — where a
`PRIMARY KEY` is dead weight. A backend decision made without settling which
workload is primary will optimise for the wrong one.

## a backend that defines "correct" is an oracle, not a backend

dbdict's validation isn't backend-agnostic logic that happens to use DuckDB —
it's *defined* as "round-trip the dict through in-memory DuckDB, diff
`DESCRIBE`". That makes DuckDB the **type oracle**, not just a storage target.
Everything in the DuckDB family (file, DuckLake, Quack) shares that one type
system, so they cost *deployment plumbing* and reuse the oracle unchanged.
HDF5 shares nothing with it — no `DESCRIBE`, no DuckDB type algebra — so it
doesn't cost plumbing, it costs **a second definition of what "the types agree"
means**.

## a closed enum in a schema is a version decision, not a backend decision

`closed: true` + `required: [duckdb]` means the rich schema doesn't merely
*default* to DuckDB — it **forbids anything else**. Adding a backend isn't a
new crate slotting into an open door; it's an edit to a closed enum in the
format itself, which means a `$version` decision. And because `required:
[duckdb]` is a single key rather than a one-of over a `backend:`
discriminator, the shape picked now is the one every future backend inherits.

## separate the target axis from the driver axis

**Axis 1 — target database** (what `source:` names) vs **axis 2 — driver per
language** (a codegen concern). Keeping those axes separate is what stops a
backend roster from re-exploding: adding a driver must never touch `source:`,
and adding a target must never touch a language mapping. Corollary asymmetry:
DuckDB and DuckLake have DDL — `CREATE TYPE`/`CREATE TABLE`, provably runnable
before printing. **HDF5 has no DDL.** Creating an HDF5 store is programmatic,
so "generate the schema" means generating *code that constructs the layout*.
One generator, two output kinds, two proof strategies.

## there are three cost tiers for types, not two

The honest framing isn't "primitives are free, compounds are hard". It's:
**tier A (fixed-width numerics, bool, string) is free; tier B (temporal,
decimal, unsigned, 128-bit) costs one encoding convention per type per target;
compounds cost a full db×language pairing.** A V1 line should be drawn on that
gradient, not on the compound/scalar boundary alone. Domain matters: a spec
for financial work that cannot express `TIMESTAMP` or `DECIMAL(p,s)` isn't a
reduced V1, it's an unusable one.

## views force SQL into a spec that was deliberately SQL-free

A view is defined by a query, and a query is SQL. You cannot synthesise
`CREATE VIEW v AS …` from a column list — the query text is irreducible input.
So "generate DDL for views" necessarily means **SQL enters the spec**, and SQL
is target-dialect text. Separately, HDF5 has no views at all, so `views:` is a
SQL-only construct. Deferring views is what lets "the dataspec is SQL-free"
remain an invariant rather than an accident.

## a lingua franca is the third option, not a revert

A project can try coarse-semantic types (portable, can't drive codegen) and
native-engine types (precise, bound to one target) and conclude the axis has
only two ends. It doesn't — the reason those felt exclusive is that the
semantic vocabulary **conflated physical storage with semantic role**. Split
them: `type: int64` (physical, drives codegen and DDL) alongside optional
`role: id` / `units: USD` (semantic, drives documentation). One is inferred
from the database, the other is authored by a human or AI — so they should
never share a field.

## metadata in the store closes the round-trip

If generated DDL writes the attribute set *into* the store, a database
produced by the tool **carries its own dataspec** — so pointing the
introspection path back at it *recovers* the original spec rather than
inferring one from statistics. That turns a nice-to-have into a testable
property: `spec → DDL → db → draft → spec` should be identity, or the docs
should say exactly where it isn't. The obstacle is shape mismatch: HDF5
attributes are key–value (open set maps 1:1) while SQL `COMMENT ON` is **one
string per object**, forcing either JSON-in-a-comment or a side table.

## snapshot vs live is a deployment decision, not a feature variant

Emitting metadata as comments or as a hard-coded struct produces *snapshots* —
self-contained, no runtime dependency, stale the moment the spec changes
without regeneration. Emitting a live read of the spec at runtime is never
stale but makes the spec a runtime dependency that must ship alongside the
code. These are two different deployment stories, not two settings of one
knob.

## generated metadata structs need typed attributes

A hard-coded-struct codegen mode needs a *type* per attribute to emit a struct
field. A bare name list can't supply that, so every attribute would arrive as
a string in every language (`scale: 4` → `"4"`). The fix is nearly free and
self-referential: let the attribute-declaration layer draw its types from the
**same primitive vocabulary the data columns use**, rather than inventing a
parallel one.

## extensibility belongs where the consumer is a reader

The regress in a self-describing schema only threatens if **every level can
invent new vocabulary**. It can't, and the split is principled: attributes
that describe *your data* are read by humans and AI, so you must be able to
invent them. Attributes that describe *how the tool executes something* need a
code path, so the tool owns them. Extensibility is needed exactly where the
consumer is a reader, and not where the consumer is the tool.

## D01–D05 run backwards are a profiler

Each constraint check answers "does the data satisfy this declared
constraint?" — pointed at a database with no spec, the same query answers
"does this hold, and should I therefore propose it?" So schema inference is
largely a rewiring of existing validators, not new machinery. What changes is
the **epistemics**: a validator is sound (`count_nulls > 0` *disproves*
`required`), an inferrer is not (`count_nulls == 0` does not *prove* it).
Every inferred constraint is a hypothesis from absence of counter-evidence.
For production that gap is disqualifying; for a research tool it's fine
*provided the draft prints its evidence* (row counts, distinct counts) so "no
nulls in 12 rows" can be told from "no nulls in 8,412 rows".

## an unnamed encoding gap gets filled by accident

HDF5 has no date, time, or decimal type, so writing those requires choosing a
byte-level representation — and `float64` for `decimal(18,4)` is a silent money
bug. Worse, without recording the convention *in the file*, a reader sees an
`int64` and cannot recover `decimal(18,4)`: the spec **degrades on every round
trip** and nothing errors. The encoding decision and the metadata decision are
therefore the same decision. Leaving it unnamed means whoever implements the
writer first sets the de facto standard without it ever having been decided.

## marginal backend cost is not uniform

Once a neutral type vocabulary exists, additional **SQL** targets are nearly
free: they consume generated DDL, they have `COMMENT ON`, and the only
per-target work is a mapping table. A non-SQL target is a step change — no
DDL, no comment facility, no temporal or decimal types. Roster decisions
should be costed on that curve, not per-target-count. Related trap: adding a
client-server target breaks an "everything runs in-process" guarantee that
embedded targets preserve, which changes how the **test suite** works, not
just what's supported.

## structural vs documentary is the real closure boundary

"Anything the tool has never heard of is inert, so extensibility buys nothing"
is true only of *structural* fields — the ones with a code path. Documentary
fields are passthrough, exactly like the layer below them, so there's no
principled reason to close them. Which means recursion in a self-describing
schema terminates for a better reason than a closed vocabulary: **documentary
values are leaves with no internal structure.** A string has no attributes. You
go one level up and stop, however many names live at that level.

## multi-backend as insurance beats multi-backend as aspiration

"We support N backends because portability is good" is an aspiration a
reviewer can argue with. "The driver for our chosen backend isn't mature
enough to bet the tool on, so the tool must not be welded to one backend" is a
finding, with receipts, that produced a design constraint. The second version
also explains why a neutral type vocabulary exists — not elegance, insurance.
Prefer the version your own evidence supports.

## deferral is stronger when availability, not just design, blocks it

Deferring a feature because it's hard to specify is an argument about design
difficulty. Deferring it because **on the actual stack there is currently
nowhere for it to work** is an argument about availability, and it's harder to
overturn. Compound types illustrate both: no neutral spelling exists across
languages *and* each available path fails differently — one driver isn't
ready, and the other costs the cross-language portability its target was
chosen for. When both arguments hold, record both.

---
created: 2026-08-01T10:47:38+12:00
title: a canonical form can outrun its physical layers
tags: [design, spec-design, storage, serialization, gotcha, sourcing]
source: /state save
---

## what must be shared is the value space, not the bytes

Designing one encoding for two targets that both lacked a type, the goal was
stated as "one shared scheme so the bytes are identical". That framing hid an
error: the *bytes* are a serialization detail each target should get to choose.
What has to be common is the **value space** — which values are legal and what
they mean.

Once that is the invariant, SQLite writing ISO text, HDF5 writing ISO text and
DuckDB writing a binary `DATE` are three encodings of **one type**, not three
types. The deadlock ("shared bytes vs per-target ergonomics") simply stops
existing, because it was never a real trade-off.

The general shape: when two targets disagree about representation, check
whether the thing you are trying to unify is the *meaning* or the
*encoding*. Unifying meaning is a type system. Unifying encoding is a storage
format, and imposing one across targets that have native support is how you
end up fighting every driver in the ecosystem.

## the canonical layer can express what a physical layer cannot — say where it goes

A canonical form richer than some of its backends is normal in a type system,
but it has a consequence that is easy to miss: **any information the canonical
form can carry and a target cannot must have a declared spillover location, or
it silently vanishes.**

Measured instance: the canonical timestamp allows an RFC 9557 zone name, but
DuckDB's native `TIMESTAMPTZ` discards the input zone — one stored value
renders `+00`, `+12` or `-04` purely by session setting. PostgreSQL documents
the same behaviour. So the zone had to be given an explicit home (a column
attribute, or a sibling column) on exactly those targets.

That reframed an earlier decision. The `timezone:` / `timezone_from:`
attributes had been justified as a *modelling preference*; they are actually a
*required storage mapping*. Same artifact, much stronger reason — and a reason
that says precisely which targets need it rather than applying it everywhere.

## a probe answers what docs can only bound

Repeatedly this session, documentation bounded the space of possible behaviours
and a probe picked the actual one:

- SQLite's docs list five normalizations applied to `sqlite_schema.sql` and are
  **silent on comments** — reading alone cannot tell you whether comments
  survive. A probe showed they do, verbatim.
- The affinity rules are precise enough to *derive* that `"1.05"` becomes a
  float in a `DECIMAL` column. Deriving it and seeing `3.1500000000000004` are
  different confidence levels.
- HDF5's user-guide page on datatypes does not mention `H5T_VARIABLE` at all;
  the answer was on a different page, and that page also carried the
  consequential caveat — variable-length strings get **no chunking and no
  compression** — which no amount of reasoning from the first page would have
  produced.

The discipline that paid: when a claim is load-bearing for a decision, get a
direct citation rather than a search-result summary. Twice a summary was
hedged or subtly wrong ("comments are not retained" — inferred by the
summarizer, not stated by the docs), and the direct fetch changed the answer.

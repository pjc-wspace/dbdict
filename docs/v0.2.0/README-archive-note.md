# archive note — v0.2.0 documents

This directory is a frozen copy of the root `README.md` and `CLAUDE.md` as they
stood at the annotated tag **`v0.2.0`** (commit `ab468fa`), the last commit
before the project's direction changed. They are preserved because the root
files have since been repositioned for **0.3.0**, in which dbdict stops being a
DuckDB-native *data dictionary* that describes one database and becomes a
**dataspec** that drives generation — DDL plus client code — across several
storage targets, in both directions. The rewrites at the root are therefore not
a revision of what these files say but a replacement of it, and this copy is
what they said before.

These files are **verbatim and unmaintained**. Nothing here is corrected, and
some of it was already inaccurate at the time of the tag — the archived
`README.md` describes a Quarto site in `site/` and links to `site/spec.md` and
`site/validation.md`, none of which exist in the tree, and its crate list omits
`dbdict-dummy-data` and `dbdict-dummy-data-duckdb`. Read this directory as a
record of the 0.2.0 position, not as documentation. For the current position see
`docs/vision-direction-0.3.0.md` and the root `README.md`.

## contents

- `README.md` — the 0.2.0 public README (DuckDB-first, `typedef:` over
  DuckDB-native types, `not aiming for cross-backend portability`)
- `CLAUDE.md` — the 0.2.0 project instructions for Claude Code

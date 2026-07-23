---
created: 2026-07-23T10:53:43+12:00
title: post-close — single-branch repo, next is codegen
tags: [duckdb, rust, git, workflow, ws-end-session]
summary: Between sessions at f605eec. The repo has moved to pjc-crates/dbdict and consolidated onto a single branch with five archive tags. Nothing in flight; the next-piece choice (Python/Julia codegen vs the recorded follow-ups vs feature/vscode salvage) is the only open thread.
---

## Goal

No active work session. `review-branches-and-merge-to-main` is closed and
shipped. This checkpoint is a resumption pointer for whatever comes next.

## Current State

- Branch `main`, HEAD **`f605eec`**, in sync with `origin/main`, working tree
  clean. No `.claude-work/.active`.
- **The repo is now `pjc-crates/dbdict`** (transferred earlier in the same
  conversation via the GitHub transfer API; `gh` has no `repo transfer`
  subcommand). Old `pjc-wspace` URLs redirect, and 52 files were rewritten to
  the new org in `33ffe89`.
- **One remote branch.** `main` at 159 commits is the project; the five
  upstream tidyverse branches were archived as tags and deleted, and
  `duckdb-source` is gone now that `main` carries everything.
- Archive tags, all resolving, each annotated with provenance and its own
  restore command: `archive/yaml-schema`, `archive/more-constraints`,
  `archive/feature/vscode`, `archive/uniqueness`,
  `archive/d03-enum-validation`.
- `cargo test --workspace` **415 passed / 0 failed**, clippy 0 warnings, fmt
  clean. **No code changed** in the last session — the tree is byte-identical
  to its pre-session state.
- 7 crates, 12 CLI subcommands. Rich path (D01–D05 validation, DDL generator,
  dummy-data generator) all shipped; legacy parquet path preserved.

## Key Decisions

- (carried) Archive-and-delete over salvaging upstream work — the fork is
  deliberately diverged. Tags keep everything recoverable, so this is a
  question of *when* to look, not whether the work survives.
- (carried) The first branch analysis was wrong because the clone was
  **shallow**; `.git/shallow` makes `git log`, `git rev-list --max-parents=0`
  and `git merge-base` agree on a false topology. `git rev-parse
  --is-shallow-repository` is the cheap up-front check. Repo is now unshallowed.
- (carried) Author/committer identity split is deliberate machine tracking —
  never "fix" it. Saved as a memory.
- (carried, unresolved) `/code-review` was not run at any phase boundary of the
  last session, against the standing mandate, because the session changed no
  code. The mandate stands for the next session, which will.

## Next Steps

Pick one when resuming (none started):

- **Python/Julia codegen** — the next model consumer and the project's stated
  direction, recorded as the recommendation since 2026-07-07. Mirror
  `crates/dbdict-ddl/` structurally; consume `load_and_lower`; generators never
  touch YAML or the CLI. Start with `/ws new`.
- **`feature/vscode` salvage** — 6 commits (Gábor Csárdi): a minimal VS Code
  extension plus an LSP server behind a hidden subcommand. The only archived
  branch not superseded by dbdict's own work; the project has no editor
  integration. Restore with
  `git push origin archive/feature/vscode^{}:refs/heads/feature/vscode`
- **D03 identifier collision** — upstream's D03 is *enum validation*; dbdict's
  D03 is the *unique-column check*. Settle the naming before docs publish.
  Recorded in `archive/d03-enum-validation`'s tag annotation.
- **Recorded follow-ups** — hoist the extension-name charset rule to one shared
  validator in `dbdict` core (currently S19 + `native.rs::safe_extension_name`
  + `is_safe_extension_name`, 3 crates); `--install-extensions` (network
  `INSTALL` opt-in).
- **Closed, no action:** the `research/` housekeeping question from the
  2026-07-19 checkpoint — those files were committed 2026-07-19 in `fa83c71`.

## Relevant Files

- `.claude-work/sessions/20260722-1847-review-branches-and-merge-to-main/summary.md`
  — last session's record
- `.claude-work/state/20260723-1009-session-closed-branches-consolidated-onto-main.md`
  — close-time dump (fuller detail on the session itself)
- `.claude-work/insights/20260722-1928-git-topology-traps-shallow-clones-and-tag-derefs.md`
- `.claude-work/insights/20260723-1009-self-recording-workflows-move-their-own-target.md`
- `.claude-work/memory/` — 5 memories; canonical and project copies now agree
- `CLAUDE.md` (root) — architecture rule for generator crates
- `crates/dbdict/src/lib.rs` — `load_and_lower`, the generator entry point
- `crates/dbdict-ddl/` — the existing generator to mirror structurally

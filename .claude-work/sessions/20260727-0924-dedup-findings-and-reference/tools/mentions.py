#!/usr/bin/env python3
"""map every mention of a fact to the section that owns it.

phase 3 single-sources facts within one document, which needs the current
mention map, not phase 1's — the phase 2 moves changed some counts. this walks
the file once, tracks the innermost heading, and reports each pattern's hits
grouped by owning section.

a mention is classified by where it sits, because that is what decides its fate:
  fence     inside a ``` block — a comment in an executed example, legitimate
  pointer   the line already defers (§N.N reference, "see", "per")
  prose     everything else — a candidate restatement, needs a human call

the classification is a triage aid, not a verdict. "prose" only means "read
this one"; some prose mentions are the canonical explanation itself.

usage: python3 mentions.py FILE.md [FACT ...]     (omit FACT for all)
"""

import re
import sys

# the §D fact list, as (label, regex). patterns are deliberately broad — a
# missed mention is worse than a false positive we skim past
FACTS = [
  ("list-segfault", r"segfault|SIGSEGV|crash(?:es|ed|ing)?\b"),
  ("blob-refcvoid", r"Ref\{Cvoid\}|append_blob"),
  ("misalignment", r"misalign|column cursor|scrambled"),
  ("appender-gc-leak", r"GC time|finalizer|leak(?:s|ed)?\b"),
  ("chunk-columnnames", r"columnnames"),
  ("one-ulp", r"ULP|%\.17e|\.17e"),
  ("register-ratios", r"3\.4×|538×"),
  ("threads-hurt", r"thread"),
  ("empty-vec-null", r"empty vec"),
]

POINTER = re.compile(r"§\s?\d|\bsee\b|\bper\b|\[§")


def sections(path):
  """yield (lineno, text, heading, in_fence) for every line."""
  heading, fence = "(preamble)", False
  for n, line in enumerate(open(path), 1):
    stripped = line.rstrip("\n")
    if stripped.lstrip().startswith("```"):
      fence = not fence
      continue
    if not fence:
      m = re.match(r"^(#{2,6})\s+(.*)$", stripped)
      if m:
        heading = m.group(2).strip()
        continue
    yield n, stripped, heading, fence


def main():
  if len(sys.argv) < 2:
    sys.exit(__doc__)
  path = sys.argv[1]
  wanted = set(sys.argv[2:])
  lines = list(sections(path))

  for label, pattern in FACTS:
    if wanted and label not in wanted:
      continue
    rx = re.compile(pattern, re.I)
    hits = [(n, t, h, f) for n, t, h, f in lines if rx.search(t)]
    by_section = {}
    for n, t, h, f in hits:
      kind = "fence" if f else ("pointer" if POINTER.search(t) else "prose")
      by_section.setdefault(h, []).append((n, kind, t.strip()))

    prose = sum(1 for items in by_section.values()
                for _, kind, _ in items if kind == "prose")
    print(f"\n=== {label}: {len(hits)} mentions / {len(by_section)} sections "
          f"({prose} prose)")
    for h, items in by_section.items():
      kinds = ",".join(sorted({k for _, k, _ in items}))
      print(f"  [{kinds:14s}] {h}  (lines {', '.join(str(n) for n, _, _ in items)})")


if __name__ == "__main__":
  main()

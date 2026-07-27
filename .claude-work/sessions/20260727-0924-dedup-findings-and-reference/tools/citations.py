#!/usr/bin/env python3
"""phase 4 pass 2: re-resolve every `file.jl:NNN` citation against real source.

the document's evidence rule is that every behavioural claim carries a source
citation. a citation that no longer resolves — wrong file, line past the end of it,
line number drifted after a package upgrade — is worse than no citation, because it
reads as verified.

what this checks mechanically:
  - the cited file exists, in the driver source tree or the research directory
  - the cited line (or range) is within that file
  - the cited line's text is printed, so a human can confirm it says what the
    document claims it says

what it cannot check: whether the line *supports* the claim. that is a reading
task. printing the line is what makes the reading cheap — spot-check the
load-bearing ones rather than all 158.

usage: python3 citations.py DOC.md SRC_DIR [SRC_DIR ...]
exit status is 1 if any citation fails to resolve.
"""

import re
import sys
from pathlib import Path

CITE = re.compile(r"\b([a-zA-Z_][\w]*\.jl):(\d+)(?:-(\d+))?")


def index(dirs):
  """map bare filename -> path, searching each source dir in order."""
  found = {}
  for d in dirs:
    for p in Path(d).rglob("*.jl"):
      found.setdefault(p.name, p)
  return found


def main():
  if len(sys.argv) < 3:
    sys.exit(__doc__)
  doc, dirs = sys.argv[1], sys.argv[2:]
  files = index(dirs)
  text = open(doc).read()

  seen, bad, ok = set(), [], []
  for m in CITE.finditer(text):
    name, start, end = m.group(1), int(m.group(2)), m.group(3)
    key = (name, start, end)
    if key in seen:
      continue
    seen.add(key)

    path = files.get(name)
    if path is None:
      bad.append((name, start, end, "file not found in any source dir"))
      continue
    lines = path.read_text(errors="replace").splitlines()
    last = int(end) if end else start
    if start < 1 or last > len(lines):
      bad.append((name, start, end, f"line out of range (file has {len(lines)})"))
      continue
    ok.append((name, start, end, lines[start - 1].strip()[:100]))

  print(f"# {doc}: {len(seen)} distinct citations")
  print(f"# resolved: {len(ok)}   unresolved: {len(bad)}\n")
  for name, start, end, why in bad:
    rng = f"{start}-{end}" if end else str(start)
    print(f"UNRESOLVED  {name}:{rng}  — {why}")
  if bad:
    print()
  # sort key normalizes `end`: it is None for a single line and a string for a
  # range, and comparing those two directly raises TypeError
  for name, start, end, txt in sorted(ok, key=lambda r: (r[0], r[1], r[2] or "")):
    rng = f"{start}-{end}" if end else str(start)
    print(f"  {name}:{rng:<10} | {txt}")

  sys.exit(1 if bad else 0)


if __name__ == "__main__":
  main()

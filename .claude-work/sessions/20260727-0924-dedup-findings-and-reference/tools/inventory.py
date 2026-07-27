#!/usr/bin/env python3
"""extract an atomic-claim inventory from markdown docs.

emits TSV: file, line, heading_path, kind, normalized_text, raw_text

a "claim" is any line that asserts something a reader could act on or be wrong
about: table data rows, list bullets, blockquote lines, and paragraph lines
carrying a bold assertion. headings supply context, not claims. fenced code and
output blocks are skipped — they are verified by execution, not by inventory.

normalized_text strips markdown formatting and collapses whitespace, so that
before/after diffs surface *content* changes rather than formatting churn.

usage: python3 inventory.py FILE [FILE ...] > inventory.tsv
"""

import re
import sys

# markdown noise to strip when normalizing. order matters: links before emphasis
_LINK = re.compile(r"\[([^\]]*)\]\([^)]*\)")   # [text](url) -> text
_EMPH = re.compile(r"[*_`~]+")                 # bold/italic/code/strike markers
_WS = re.compile(r"\s+")
_TABLE_SEP = re.compile(r"^\|[\s:|-]+\|$")     # |---|---| separator rows
_BULLET = re.compile(r"^\s*([-*+]|\d+\.)\s+")
_HEADING = re.compile(r"^(#{1,6})\s+(.*)$")


def normalize(text):
  """strip formatting so reworded-but-identical content compares equal."""
  t = _LINK.sub(r"\1", text)
  t = _EMPH.sub("", t)
  t = t.strip().strip("|").strip()
  return _WS.sub(" ", t)


def heading_path(stack):
  """render the current heading stack as a > separated path."""
  return " > ".join(h for h in stack if h)


def classify(line):
  """return a claim kind, or None if the line is not a claim."""
  s = line.strip()
  if not s:
    return None
  if _TABLE_SEP.match(s):
    return None
  if s.startswith("|"):
    return "table_row"
  if s.startswith(">"):
    return "blockquote"
  if _BULLET.match(line):
    return "bullet"
  # every remaining non-empty line outside a fence is captured. an earlier
  # version counted paragraph lines only when they carried bold, which silently
  # dropped real claims stated in plain prose (findings.md 4d's path-E result,
  # reference.md 4.3's list-field boundary). this inventory is the safety net
  # phase 4 diffs against, so it must favour recall: precision loss is noise you
  # filter by `kind`, recall loss is a claim nothing is protecting
  if "**" in s:
    return "assertion"
  return "prose"


def inventory(path):
  rows = []
  stack = [""] * 7
  in_fence = False
  fence_marker = None

  with open(path, encoding="utf-8") as fh:
    for lineno, raw in enumerate(fh, 1):
      line = raw.rstrip("\n")
      stripped = line.strip()

      # fenced blocks: skip wholesale. ``` and ~~~ both count, and the closing
      # fence must match the opener so nested/indented fences don't end early
      if stripped.startswith("```") or stripped.startswith("~~~"):
        marker = stripped[:3]
        if not in_fence:
          in_fence, fence_marker = True, marker
        elif marker == fence_marker:
          in_fence, fence_marker = False, None
        continue
      if in_fence:
        continue

      m = _HEADING.match(line)
      if m:
        depth = len(m.group(1))
        stack[depth - 1] = normalize(m.group(2))
        for d in range(depth, 7):
          stack[d] = ""
        continue

      kind = classify(line)
      if kind is None:
        continue
      norm = normalize(line)
      if not norm:
        continue
      rows.append((path, lineno, heading_path(stack), kind, norm, stripped))
  return rows


def main(argv):
  if len(argv) < 2:
    print(__doc__, file=sys.stderr)
    return 2
  print("file\tline\theading\tkind\tnormalized\traw")
  total = 0
  for path in argv[1:]:
    rows = inventory(path)
    total += len(rows)
    for r in rows:
      # tabs inside cells would corrupt the TSV
      print("\t".join(str(c).replace("\t", " ") for c in r))
  print(f"# {total} claims across {len(argv) - 1} file(s)", file=sys.stderr)
  return 0


if __name__ == "__main__":
  sys.exit(main(sys.argv))

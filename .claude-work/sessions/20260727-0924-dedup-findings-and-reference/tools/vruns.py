#!/usr/bin/env python3
"""find verbatim runs shared by two files.

the goal's cross-file test is "no verbatim run over N characters". this answers
it directly rather than by similarity score: normalize whitespace on both sides,
then look for exact shared substrings.

whitespace is collapsed because the two documents wrap at different widths — an
identical sentence broken after a different word is still a verbatim duplicate,
and a raw-text comparison would miss it. this is the same normalization tokencov
needed for the same reason.

method: every window of exactly MIN chars in SOURCE is looked up in the set of
all MIN-char windows of TARGET. a hit means a shared run of at least MIN; the hit
is then extended left and right to report the maximal run. exact, and linear in
practice — no similarity threshold to argue about.

usage: python3 vruns.py SOURCE.md TARGET.md [MIN]
exit status is 1 if any run is found, so it can gate a phase.
"""

import re
import sys

DEFAULT_MIN = 120


def normalize(text):
  """collapse all whitespace runs to a single space.

  returns the normalized string. offsets into it are not offsets into the file,
  which is fine — we report the matched text itself, not a line number.
  """
  return re.sub(r"\s+", " ", text)


def maximal_runs(src, tgt, min_len):
  """yield the maximal shared substrings of at least min_len chars.

  windows: a set of every fixed-length slice of tgt. python's `in` on a set of
  strings is a hash lookup, so this is far cheaper than a nested scan, at the
  cost of holding ~len(tgt) slices in memory. our targets are <100KB.
  """
  windows = {tgt[i:i + min_len] for i in range(len(tgt) - min_len + 1)}

  runs = []
  i = 0
  while i <= len(src) - min_len:
    if src[i:i + min_len] not in windows:
      i += 1
      continue
    # found a run of at least min_len — extend it as far right as it still
    # appears in the target, then record it and skip past it
    end = i + min_len
    while end < len(src) and src[i:end + 1] in tgt:
      end += 1
    runs.append(src[i:end])
    i = end - min_len + 1
  return runs


def main():
  if len(sys.argv) < 3:
    sys.exit(__doc__)
  src_path, tgt_path = sys.argv[1], sys.argv[2]
  min_len = int(sys.argv[3]) if len(sys.argv) > 3 else DEFAULT_MIN

  src = normalize(open(src_path).read())
  tgt = normalize(open(tgt_path).read())

  runs = maximal_runs(src, tgt, min_len)

  print(f"# source {src_path} ({len(src)} normalized chars)")
  print(f"# target {tgt_path} ({len(tgt)} normalized chars)")
  print(f"# shared verbatim runs >= {min_len} chars: {len(runs)}")
  for r in runs:
    print(f"\n[{len(r)} chars]\n  {r}")

  shared = sum(len(r) for r in runs)
  pct = 100.0 * shared / len(src) if src else 0.0
  print(f"\n# {shared} of {len(src)} source chars in shared runs ({pct:.1f}%)")
  sys.exit(1 if runs else 0)


if __name__ == "__main__":
  main()

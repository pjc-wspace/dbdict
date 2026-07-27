#!/usr/bin/env python3
"""classify each claim in a source file against a target file.

for every claim in SOURCE, find its closest counterpart in TARGET and bucket it:

  duplicated      >= 0.80  near-verbatim or lightly reworded — safe to cut
  overlap         >= 0.50  same subject, different wording — needs a human call
  unique          <  0.50  no counterpart — MUST move to TARGET before cutting

similarity is the max of a sequence ratio (catches rewording) and a token-set
Jaccard (catches reordering), so neither rewording nor reordering alone can hide
a duplicate. short claims are reported separately: below the length floor the
scores are noise, not signal.

usage: python3 crossmatch.py INVENTORY.tsv SOURCE_PATH TARGET_PATH > matched.tsv
"""

import sys
from difflib import SequenceMatcher

MIN_LEN = 25      # below this, similarity scores are noise
DUP = 0.80
OVERLAP = 0.50


def tokens(text):
  return {w for w in text.lower().split() if len(w) > 2}


def similarity(a, b):
  seq = SequenceMatcher(None, a, b, autojunk=False).ratio()
  ta, tb = tokens(a), tokens(b)
  jac = len(ta & tb) / len(ta | tb) if (ta or tb) else 0.0
  return max(seq, jac)


def load(path):
  rows = []
  with open(path, encoding="utf-8") as fh:
    next(fh)  # header
    for line in fh:
      if line.startswith("#"):
        continue
      parts = line.rstrip("\n").split("\t")
      if len(parts) >= 6:
        rows.append(parts)
  return rows


def main(argv):
  if len(argv) != 4:
    print(__doc__, file=sys.stderr)
    return 2
  inv, src_path, tgt_path = argv[1], argv[2], argv[3]
  rows = load(inv)
  src = [r for r in rows if r[0] == src_path]
  tgt = [r for r in rows if r[0] == tgt_path]
  if not src or not tgt:
    print(f"no rows for {src_path!r} or {tgt_path!r}", file=sys.stderr)
    return 1

  print("bucket\tscore\tsrc_line\tsrc_heading\tsrc_text\tbest_tgt_line\tbest_tgt_text")
  counts = {}
  for r in src:
    _, line, heading, _kind, norm, _raw = r[:6]
    if len(norm) < MIN_LEN:
      bucket, score, best = "short", 0.0, None
    else:
      best, score = None, 0.0
      for t in tgt:
        s = similarity(norm, t[4])
        if s > score:
          score, best = s, t
      bucket = "duplicated" if score >= DUP else "overlap" if score >= OVERLAP else "unique"
    counts[bucket] = counts.get(bucket, 0) + 1
    print("\t".join([
        bucket, f"{score:.2f}", line, heading, norm,
        best[1] if best else "", (best[4][:120] if best else ""),
    ]))

  for b in ("unique", "overlap", "duplicated", "short"):
    if b in counts:
      print(f"# {b}: {counts[b]}", file=sys.stderr)
  return 0


if __name__ == "__main__":
  sys.exit(main(sys.argv))

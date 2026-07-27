#!/usr/bin/env python3
"""token-coverage check: which facts in SOURCE have no trace in TARGET.

line-level similarity was the wrong unit for this job — the two documents state
the same facts with different sentence breaks, so a true duplicate scores as
"unique" purely because no single line pairs up. distinctive tokens survive
rewrapping and rewording, so they answer the actual question: is there a fact
here that exists nowhere in the other file?

tokens extracted (the things a driver claim is anchored on):
  citation   file.jl:123 / file.jl:12-34   — a source reference
  ident      `backticked` identifiers      — API names, types, values
  errstr     Capitalised C/DuckDB error text
  number     measured quantities incl. units and multipliers

a token found in TARGET means that anchor is covered there. tokens missing from
TARGET are where genuinely unique content hides — review those by hand.

usage: python3 tokencov.py SOURCE.md TARGET.md
"""

import re
import sys

CITATION = re.compile(r"\b([a-z_]+\.jl:\d+(?:-\d+)?)")
IDENT = re.compile(r"`([^`\n]{2,60})`")
ERRSTR = re.compile(r"(?:Binder Error|Catalog Error|Invalid unicode|Failed to cast"
                    r"|Call to EndRow|cannot convert a value|Unsupported type"
                    r"|NotImplementedException|InexactError|MethodError|FieldError"
                    r"|ArgumentError|SIGSEGV)[^.\n`|]*")
NUMBER = re.compile(r"\b(\d[\d,._]*\s?(?:ms|µs|s|GiB|MiB|KiB|×|x|%|ULP|rows/s)?)\b")


def strip_fences(text):
  """drop fenced blocks: code is verified by execution, not by token coverage."""
  out, fence = [], False
  for line in text.splitlines():
    st = line.strip()
    if st.startswith("```") or st.startswith("~~~"):
      fence = not fence
      continue
    if not fence:
      out.append(line)
  return "\n".join(out)


def extract(text):
  """return {kind: {token: [line numbers]}} for one document."""
  found = {"citation": {}, "ident": {}, "errstr": {}, "number": {}}
  for lineno, line in enumerate(text.splitlines(), 1):
    for kind, rx in (("citation", CITATION), ("ident", IDENT),
                     ("errstr", ERRSTR), ("number", NUMBER)):
      for m in rx.finditer(line):
        tok = m.group(1).strip() if rx is not ERRSTR else m.group(0).strip()
        if not tok:
          continue
        found[kind].setdefault(tok, []).append(lineno)
  return found


def main(argv):
  if len(argv) != 3:
    print(__doc__, file=sys.stderr)
    return 2
  src_text = strip_fences(open(argv[1], encoding="utf-8").read())
  tgt_text = strip_fences(open(argv[2], encoding="utf-8").read())
  src = extract(src_text)
  # match against the WHOLE target, fences included: a fact may be covered there
  # by an executable example. whitespace is collapsed on both sides because a
  # token that wraps across a line break in the target is still present there —
  # not normalizing produced a whole class of false "absent" results
  tgt_raw = re.sub(r"\s+", " ", open(argv[2], encoding="utf-8").read())

  print(f"# source {argv[1]}  target {argv[2]}")
  for kind in ("citation", "errstr", "ident", "number"):
    toks = src[kind]
    missing = {t: ls for t, ls in toks.items()
               if re.sub(r"\s+", " ", t) not in tgt_raw}
    print(f"\n## {kind}: {len(toks)} distinct in source, "
          f"{len(missing)} absent from target")
    for tok, lines in sorted(missing.items(), key=lambda kv: kv[1][0]):
      locs = ",".join(str(l) for l in lines[:6])
      print(f"  L{locs:<22} {tok[:100]}")
  return 0


if __name__ == "__main__":
  sys.exit(main(sys.argv))

#!/usr/bin/env python3
"""prove the §7 claim inventory is complete.

an inventory is only worth what its completeness guarantee is worth. a hand-built
list of claims silently omits whatever the author's eye skipped, and the omission
is invisible — the list still looks thorough. so this check is mechanical: every
digit-bearing line inside §7 must be cited somewhere in inventory.md, either as a
claim row or in its ignore list.

it deliberately does NOT check that the classification is right — only that no
line went unaccounted for. a wrong classification is caught later, by numbers.py
failing to verify a claim it should have verified.

three guards, each closing a way this check could pass while checking nothing —
all three were found by code review of the first version, which had none of them:

  fence-aware bounds   a line starting with "## " inside a fenced code block
                       used to truncate the section. inserting one fake heading
                       cut the checked range from 76 lines to 29 and still
                       reported OK. anchors.py, inventory.py and tokencov.py all
                       skip fences; this now does too.
  bounded ranges       "L1000-L2000" used to be accepted verbatim, so one
                       over-broad or copy-pasted range marked every line cited
                       and the check passed unconditionally. a range may not
                       straddle the section boundary.
  tight endpoints      a range must begin and end on a digit-bearing line.
                       without this, a range can be widened until it swallows
                       lines nobody classified.

citations may be single (`L1305`) or ranges (`L1289-L1300`, en dash accepted).
citations wholly outside the section are allowed and reported separately — the
inventory legitimately cites restatements elsewhere in the document.

usage: python3 inventory_check.py REFERENCE_MD INVENTORY_MD [SECTION]
SECTION defaults to "## 7. Benchmarks".
exit status is 1 if any line is unaccounted for, or any citation is malformed.
"""

import re
import sys


def fenced(lines):
  """1-based set of line numbers sitting inside ``` fenced blocks.

  numbers inside a code example are not claims, and a "## " inside one is not a
  heading. every other audit tool in this project skips fences for the same
  reason.
  """
  inside = set()
  open_fence = False
  for n, line in enumerate(lines, 1):
    if line.lstrip().startswith("```"):
      open_fence = not open_fence
      inside.add(n)
      continue
    if open_fence:
      inside.add(n)
  return inside


def section_bounds(lines, heading, skip):
  """1-based [start, end) of the named section, ignoring fenced lines.

  reading the bounds from the document rather than hardcoding them means the
  check survives edits that shift §7 up or down.
  """
  start = None
  for i, line in enumerate(lines, 1):
    if i not in skip and line.startswith(heading):
      start = i
      break
  if start is None:
    sys.exit(f"section heading not found: {heading!r}")
  for i in range(start + 1, len(lines) + 1):
    if i not in skip and lines[i - 1].startswith("## "):
      return start, i
  return start, len(lines) + 1


def citations(path):
  """every citation in the inventory as (lo, hi) pairs; singles have lo == hi."""
  text = open(path, encoding="utf-8").read()
  spans = []
  # ranges first, then remove them so their endpoints are not re-read as singles
  for match in re.finditer(r"L(\d+)\s*[-–—]\s*L?(\d+)", text):
    lo, hi = int(match.group(1)), int(match.group(2))
    spans.append((min(lo, hi), max(lo, hi)))
  text = re.sub(r"L(\d+)\s*[-–—]\s*L?(\d+)", " ", text)
  for match in re.finditer(r"L(\d+)", text):
    n = int(match.group(1))
    spans.append((n, n))
  return spans


def main(argv):
  if len(argv) not in (3, 4):
    sys.exit("usage: python3 inventory_check.py REFERENCE_MD INVENTORY_MD [SECTION]")
  ref, inv = argv[1], argv[2]
  heading = argv[3] if len(argv) == 4 else "## 7. Benchmarks"

  lines = open(ref, encoding="utf-8").read().splitlines()
  skip = fenced(lines)
  start, end = section_bounds(lines, heading, skip)

  digit_lines = [
    n for n in range(start, end)
    if n not in skip and re.search(r"[0-9]", lines[n - 1])
  ]
  digits = set(digit_lines)

  failures = []
  cited = set()
  outside = 0

  for lo, hi in citations(inv):
    inside_lo = start <= lo < end
    inside_hi = start <= hi < end
    # a range that ENCLOSES the section has both endpoints outside it, so the
    # straddle test below cannot see it — "L1-L2000" would have been waved
    # through as a benign restatement while marking every line cited. that is
    # the same hole the straddle guard was added to close, entered from the
    # other side
    if lo < start and hi >= end:
      failures.append(
        f"citation L{lo}-L{hi} encloses the whole section [{start}, {end}) — "
        f"an over-broad range cannot stand in for per-line citations")
      continue
    if not inside_lo and not inside_hi:
      outside += 1
      continue
    if inside_lo != inside_hi:
      failures.append(
        f"citation L{lo}-L{hi} straddles the section boundary [{start}, {end})")
      continue
    bad_endpoint = False
    for endpoint in {lo, hi}:
      if endpoint not in digits:
        failures.append(
          f"citation L{lo}" + (f"-L{hi}" if hi != lo else "") +
          f": endpoint L{endpoint} is not a digit-bearing line in the section")
        bad_endpoint = True
    # `continue`, not just a recorded failure: without it the over-wide range
    # still marked its whole span as cited, so the guard reported the problem
    # while letting it do exactly what it was added to prevent
    if bad_endpoint:
      continue
    cited.update(range(lo, hi + 1))

  missing = [n for n in digit_lines if n not in cited]

  print(f"section:              {heading} (lines {start}..{end - 1})")
  print(f"fenced lines skipped: {len(skip & set(range(start, end)))}")
  print(f"digit-bearing lines:  {len(digit_lines)}")
  print(f"cited in inventory:   {len(digit_lines) - len(missing)}")
  print(f"citations outside:    {outside}   (restatements elsewhere — allowed)")

  for n in missing:
    failures.append(f"{ref}:{n}: unaccounted for: {lines[n - 1].strip()[:90]}")

  if failures:
    print(f"\nFAIL — {len(failures)} problem(s):\n")
    for f in failures:
      print("  " + f)
    return 1
  print("\nOK — every digit-bearing line in the section is accounted for")
  return 0


if __name__ == "__main__":
  sys.exit(main(sys.argv))

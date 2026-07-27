#!/usr/bin/env python3
"""resolve every internal anchor link against the document's real headings.

phase 4 pass 2 requires this, and `goal.md` requires it under *both* anchor
generation conventions — github strips dots from `#### 5.1.2 Foo` to give
`512-foo`, while some renderers keep them (`51 2-foo` / `5.1.2-foo`). a link that
resolves under one and not the other is a latent broken link, so both are checked.

**fenced blocks are skipped.** an earlier version of this check did not skip
them, so julia comments (`# WRONG — ...`) were parsed as markdown headings and
silently inflated the set of "valid" anchors. that cannot produce a false
*failure*, but it can hide a real one, which is worse in a verification tool.

usage: python3 anchors.py FILE.md
exit status is 1 if any link fails to resolve under both conventions.
"""

import re
import sys


def strip_dots(heading):
  """github's convention: lowercase, drop punctuation, spaces to hyphens."""
  s = re.sub(r"[^\w\s-]", "", heading.strip().lower())
  return re.sub(r"\s+", "-", s)


def keep_dots(heading):
  """the variant that preserves dots in the section number."""
  s = re.sub(r"[^\w\s.-]", "", heading.strip().lower())
  return re.sub(r"\s+", "-", s)


def headings(path):
  """collect headings, ignoring anything inside a fenced code block."""
  out, fence = [], False
  for line in open(path):
    if line.strip().startswith("```"):
      fence = not fence
      continue
    if fence:
      continue
    m = re.match(r"^#{1,6}\s+(.*)$", line.rstrip("\n"))
    if m:
      out.append(m.group(1).strip())
  return out


def main():
  if len(sys.argv) < 2:
    sys.exit(__doc__)
  path = sys.argv[1]
  text = open(path).read()

  heads = headings(path)
  slugs_a = {strip_dots(h) for h in heads}
  slugs_b = {keep_dots(h) for h in heads}

  links = re.findall(r"\]\(#([^)]+)\)", text)
  bad = [l for l in links if l not in slugs_a and l not in slugs_b]
  one_only = [l for l in links if (l in slugs_a) != (l in slugs_b)]

  print(f"{len(links)} internal links, {len(heads)} headings (fences excluded)")
  print(f"  unresolved under both conventions: {len(bad)}")
  for l in bad:
    print(f"    BROKEN: {l}")
  print(f"  resolve under one convention only: {len(one_only)}")

  sys.exit(1 if bad else 0)


if __name__ == "__main__":
  main()

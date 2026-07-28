#!/usr/bin/env python3
"""resolve every internal anchor link against the document's real headings.

phase 4 pass 2 requires this, and `goal.md` requires it under *both* anchor
generation conventions — github strips dots from `#### 5.1.2 Foo` to give
`512-foo`, while some renderers keep them (`5.1.2-foo`).

CORRECTED 2026-07-28. this file used to claim "a link that resolves under one
and not the other is a latent broken link". that premise is wrong whenever the
headings are numbered: the two conventions then produce DIFFERENT slugs for the
same heading, a link can only be spelled one way, so resolving under exactly one
convention is the normal, correct state. 44 of reference.md's 46 links are in
it. the old code computed `one_only`, printed it as a bare count, listed nothing
and gated nothing — and a code review flagged the gating gap. gating it as the
docstring implied would have failed a correct document.

what actually matters is the DIRECTION:
  - resolves under github's convention only  -> correct; expected for `§N.N` links
  - resolves under the dot-preserving one only -> BROKEN on github, the renderer
    this repo is read in. this is a real defect and is now fatal
  - resolves under neither -> broken everywhere, fatal (unchanged)

**fenced blocks are skipped.** an earlier version of this check did not skip
them, so julia comments (`# WRONG — ...`) were parsed as markdown headings and
silently inflated the set of "valid" anchors. that cannot produce a false
*failure*, but it can hide a real one, which is worse in a verification tool.

usage: python3 anchors.py FILE.md
exit status is 1 if any link fails to resolve under GITHUB's convention — that
is, `bad` (resolves under neither) plus `keepdots_only` (resolves only under the
dot-preserving one). links and headings are both read with fenced blocks
excluded, so a markdown example containing `](#anchor)` is not treated as a
real link.
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


def unfenced_lines(path):
  """every line outside a ``` fenced block. headings and links both use this,
  so the two sides of the check see the same document."""
  out, fence = [], False
  for line in open(path):
    if line.strip().startswith("```"):
      fence = not fence
      continue
    if fence:
      continue
    out.append(line.rstrip("\n"))
  return out


def headings(path):
  """collect headings, ignoring anything inside a fenced code block."""
  out = []
  for line in unfenced_lines(path):
    m = re.match(r"^#{1,6}\s+(.*)$", line)
    if m:
      out.append(m.group(1).strip())
  return out


def main():
  if len(sys.argv) < 2:
    sys.exit(__doc__)
  path = sys.argv[1]
  # links must be collected on the SAME terms as headings, which skip fenced
  # blocks. scraping the raw text picked up `](#anchor)` inside markdown
  # examples, which resolve against no real heading — harmless while the exit
  # gate was loose, a hard build failure now that it is strict
  text = "\n".join(unfenced_lines(path))

  heads = headings(path)
  slugs_a = {strip_dots(h) for h in heads}
  slugs_b = {keep_dots(h) for h in heads}

  links = re.findall(r"\]\(#([^)]+)\)", text)
  bad = [l for l in links if l not in slugs_a and l not in slugs_b]
  # the interesting split is by DIRECTION, not by "one only" — see the note in
  # the module docstring. a link resolving only under the dot-preserving
  # convention is broken on github; the reverse is simply correct.
  github_only = [l for l in links if l in slugs_a and l not in slugs_b]
  keepdots_only = [l for l in links if l in slugs_b and l not in slugs_a]

  print(f"{len(links)} internal links, {len(heads)} headings (fences excluded)")
  print(f"  unresolved under either convention: {len(bad)}")
  for l in bad:
    print(f"    BROKEN: {l}")
  print(f"  github-style only (expected for numbered headings): {len(github_only)}")
  print(f"  dot-preserving only — BROKEN ON GITHUB: {len(keepdots_only)}")
  for l in keepdots_only:
    print(f"    GITHUB-BROKEN: {l}")

  sys.exit(1 if (bad or keepdots_only) else 0)


if __name__ == "__main__":
  main()

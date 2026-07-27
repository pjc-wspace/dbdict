#!/usr/bin/env python3
"""phase 4 pass 1: execute every julia example and diff against its documented output.

the document's contract is that its examples run and produce what it says they
produce. reading them cannot establish that; running them can. each ```julia block
is extracted, run in its own process against the research directory's project, and
its stdout compared to the plain ``` block that immediately follows it (the
document's convention for "this is what that prints").

blocks with no following output block are executed anyway — a block that throws is
a defect even when nothing was claimed about its output. blocks that are meant to
throw say so in their own comments; their expected output is shown in the doc, so
they are compared like any other.

comparison collapses runs of whitespace, because the doc wraps some printed lines
for width. that is deliberately lenient: this pass is for catching "the documented
output is no longer what happens", not for formatting drift.

runs blocks concurrently — each is an independent process and julia's startup plus
DuckDB load dominates, so serial execution wastes most of the wall clock.

usage: python3 runblocks.py REFERENCE.md PROJECT_DIR [-j N]
exit status is 1 if any block fails to run or mismatches its documented output.
"""

import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

BLOCK = re.compile(
  r"^```julia\n(?P<code>.*?)^```\n"          # the example
  r"(?:\s*^```\n(?P<want>.*?)^```\n)?",       # its documented output, if any
  re.S | re.M,
)


ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")

# a block whose first line carries this marker is an excerpt, not a program: it
# quotes code shown in full elsewhere and deliberately omits the setup. running it
# proves nothing, so it is reported and skipped rather than counted as a failure
FRAGMENT = "# fragment"


def norm(text):
  """collapse whitespace and drop ANSI colour so neither counts as a diff.

  DataFrames emits colour codes even when stdout is a pipe, so without this every
  DataFrame-printing example reports a false mismatch against the plain text the
  document records.
  """
  return re.sub(r"\s+", " ", ANSI.sub("", text)).strip()


def extract(path):
  src = open(path).read()
  out = []
  for i, m in enumerate(BLOCK.finditer(src), 1):
    line = src[: m.start()].count("\n") + 1
    out.append({
      "n": i,
      "line": line,
      "code": m.group("code"),
      "want": m.group("want"),
    })
  return out


def run_one(block, project, workdir):
  """run a single block in its own julia process; return the block with results."""
  if block["code"].lstrip().startswith(FRAGMENT):
    block["rc"], block["out"], block["err"] = None, "", ""
    return block
  path = Path(workdir) / f"block{block['n']:02d}.jl"
  path.write_text(block["code"])
  try:
    p = subprocess.run(
      ["julia", f"--project={project}", str(path)],
      capture_output=True, text=True, timeout=900,
    )
    block["rc"] = p.returncode
    block["out"] = p.stdout
    block["err"] = p.stderr
  except subprocess.TimeoutExpired:
    block["rc"], block["out"], block["err"] = -1, "", "TIMEOUT"
  return block


def main():
  if len(sys.argv) < 3:
    sys.exit(__doc__)
  ref, project = sys.argv[1], sys.argv[2]
  jobs = 6
  if "-j" in sys.argv:
    jobs = int(sys.argv[sys.argv.index("-j") + 1])

  blocks = extract(ref)
  print(f"# {len(blocks)} julia blocks extracted from {ref}")
  print(f"# {sum(1 for b in blocks if b['want'])} have documented output")
  print(f"# running with {jobs} concurrent julia processes\n")

  with tempfile.TemporaryDirectory() as wd:
    with ThreadPoolExecutor(max_workers=jobs) as pool:
      done = list(pool.map(lambda b: run_one(b, project, wd), blocks))

  bad = 0
  for b in sorted(done, key=lambda x: x["n"]):
    tag = f"block {b['n']:2d} (line {b['line']:4d})"
    if b["rc"] is None:
      print(f"skip  {tag}  marked '{FRAGMENT}' — excerpt, not a program")
      continue
    if b["rc"] != 0:
      print(f"FAIL  {tag}  exit={b['rc']}")
      print("      stderr: " + " | ".join(b["err"].strip().splitlines()[-3:]))
      bad += 1
      continue
    if b["want"] is None:
      print(f"ran   {tag}  (no documented output to compare)")
      continue
    if norm(b["out"]) == norm(b["want"]):
      print(f"OK    {tag}  output matches")
    else:
      print(f"DIFF  {tag}")
      print(f"      want: {norm(b['want'])[:160]}")
      print(f"      got : {norm(b['out'])[:160]}")
      bad += 1

  print(f"\n# {len(done) - bad} clean, {bad} failing")
  sys.exit(1 if bad else 0)


if __name__ == "__main__":
  main()

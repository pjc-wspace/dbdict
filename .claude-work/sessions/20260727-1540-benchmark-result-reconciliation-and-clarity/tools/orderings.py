#!/usr/bin/env python3
"""compare per-cell path orderings between two sweeps.

the orderings — not the absolute times — are what reference.md calls the
deliverable (§7.5), and §7.6 feeds them into §8.1's writer tiers, which is the
codegen contract. so when the harness is repaired and the sweep re-run, the
question that matters is not "did the numbers move" (they always do) but "did
any ORDERING move, and does it reach a tier".

this reproduces run_all.jl's ordering rule (run_all.jl:155-160): within a
(threads, kind, profile, scale), take the cells with status ok and sort by
median_ns ascending. an ordering is reported per run, so a cell that disagrees
between repeats is visible rather than collapsed.

usage: python3 orderings.py OLD_RAWDIR NEW_RAWDIR
exit status is 0 always — this is a reporting tool, not a gate. whether a moved
ordering is acceptable is a judgement for the session, not for a script.
"""

import sys

import bench


def orderings(rawdir):
  """(threads, kind, profile, scale) -> {tag: [path, ...] fastest first}."""
  runs = bench.load_runs(rawdir)
  out = {}
  for run in runs:
    for cell in run["cells"]:
      if cell["status"] != "ok":
        continue
      key = (run["threads"], cell["kind"], cell["profile"], cell["scale"])
      out.setdefault(key, {}).setdefault(run["tag"], []).append(
        (cell["median_ns"], cell["path"]))
  ordered = {}
  for key, bytag in out.items():
    ordered[key] = {
      tag: [path for _, path in sorted(cells)] for tag, cells in bytag.items()
    }
  return ordered


def consensus(bytag):
  """the ordering if at least two runs agree on it, else None.

  the `len < 2` guard is load-bearing. `all(o == seen[0] for o in seen)` is
  vacuously true for a one-element list, so a cell reported by a single repeat
  — a crashed run, a partial re-sweep, a cell skipped in the other run — would
  come back as an agreed ordering and be counted as unchanged or reported as
  MOVED, as though two runs had established it.

  this is the same vacuous-agreement bug this session fixed in
  run_all.jl's stability table, and the rule now matches there and in
  numbers.py: fewer than two runs means not checked, not passed.
  """
  seen = list(bytag.values())
  if len(seen) < 2:
    return None
  return seen[0] if all(o == seen[0] for o in seen) else None


def main(argv):
  if len(argv) != 3:
    sys.exit("usage: python3 orderings.py OLD_RAWDIR NEW_RAWDIR")
  old, new = orderings(argv[1]), orderings(argv[2])

  moved, unstable_old, unstable_new, same = [], [], [], 0
  insufficient = []
  for key in sorted(set(old) | set(new)):
    o, n = old.get(key, {}), new.get(key, {})
    co, cn = consensus(o), consensus(n)
    # "no consensus" has two causes and they mean opposite things: repeats that
    # disagree is a result, fewer than two repeats is a gap in the data
    if co is None:
      (unstable_old if len(o) >= 2 else insufficient).append((key, "old", o))
    if cn is None:
      (unstable_new if len(n) >= 2 else insufficient).append((key, "new", n))
    if co is not None and cn is not None:
      if co == cn:
        same += 1
      else:
        moved.append((key, co, cn))

  def fmt(key):
    threads, kind, profile, scale = key
    return f"{threads:>2}t {kind:<5} {profile:<6} {scale:>7}"

  print(f"cells compared:            {len(set(old) | set(new))}")
  print(f"orderings unchanged:       {same}")
  print(f"orderings MOVED:           {len(moved)}")
  print(f"unstable in old sweep:     {len(unstable_old)}   (repeats disagree)")
  print(f"unstable in new sweep:     {len(unstable_new)}   (repeats disagree)")
  print(f"insufficient data:         {len(insufficient)}   (fewer than 2 runs — NOT checked)")

  if moved:
    print("\nmoved:")
    for key, co, cn in moved:
      print(f"  {fmt(key)}")
      print(f"      was: {' < '.join(co)}")
      print(f"      now: {' < '.join(cn)}")

  if unstable_new:
    print("\nunstable in the NEW sweep (repeats disagree):")
    for key, _, bytag in unstable_new:
      print(f"  {fmt(key)}")
      for tag, o in sorted(bytag.items()):
        print(f"      {tag}: {' < '.join(o)}")

  if insufficient:
    print("\nINSUFFICIENT DATA — fewer than two runs, so nothing was checked:")
    for key, which, bytag in insufficient:
      print(f"  {fmt(key)} [{which}]: {len(bytag)} run(s): {sorted(bytag)}")

  if unstable_old:
    print("\nunstable in the OLD sweep (for reference):")
    for key, _, bytag in unstable_old:
      print(f"  {fmt(key)}: " +
            " | ".join(f"{tag} {' < '.join(o)}" for tag, o in sorted(bytag.items())))

  return 0


if __name__ == "__main__":
  sys.exit(main(sys.argv))

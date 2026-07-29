#!/usr/bin/env python3
"""per-cell ordering distribution within one sweep.

run_all.jl's stability column is binary: every repeat agrees, or it does not.
With two repeats that is all the data supports. With more, the binary answer
throws away most of what was measured — it cannot distinguish a genuine
coin-toss tie from a single rare excursion, and it cannot say which ordering
dominates.

Two separations this reports that the binary rule cannot:

  winner vs full ordering — §7.3's actual claim is that `stream_first` is
      fastest. If it wins every run and only positions 2-3 shuffle, that is a
      much weaker instability than "the ordering did not reproduce" suggests.
      Reported separately.

  unanimous vs dominant vs split — with n repeats, if a cell were a true 50/50
      between two orderings the chance of unanimity is 2 * 0.5**(n-1): 100% at
      n=2, 12.5% at n=4, 3.1% at n=6. So unanimity only becomes evidence as n
      grows, and a near-even split only becomes evidence of a real tie as n
      grows. The verdict column is meaningless at n=2 and is labelled as such.

usage: python3 stability.py RAWDIR [--kind write|read]
exit status is always 0 — this reports, it does not gate.
"""

import collections
import sys

import bench


def distributions(rawdir):
  """(threads, kind, profile, scale) -> Counter of ordering tuples."""
  runs = bench.load_runs(rawdir)
  per_cell = {}
  for run in runs:
    for cell in run["cells"]:
      if cell["status"] != "ok":
        continue
      key = (run["threads"], cell["kind"], cell["profile"], cell["scale"])
      per_cell.setdefault(key, {}).setdefault(run["tag"], []).append(
        (cell["median_ns"], cell["path"]))
  out = {}
  for key, bytag in per_cell.items():
    counter = collections.Counter(
      tuple(path for _, path in sorted(cells)) for cells in bytag.values())
    out[key] = counter
  return out


def unanimity_note(n):
  """how much weight unanimity carries at this repeat count."""
  if n < 2:
    return "n<2 — nothing was compared"
  chance = 2 * 0.5 ** (n - 1)
  return (f"at n={n}, a true 50/50 tie would still look unanimous "
          f"{chance * 100:.1f}% of the time")


def main(argv):
  args = [a for a in argv[1:] if not a.startswith("--")]
  want_kind = None
  for a in argv[1:]:
    if a.startswith("--kind"):
      want_kind = a.split("=", 1)[1] if "=" in a else None
  if len(args) < 1:
    sys.exit("usage: python3 stability.py RAWDIR [--kind=write|read]")
  if len(args) > 1 and want_kind is None:
    want_kind = args[1]

  dists = distributions(args[0])
  if not dists:
    sys.exit("no ok cells found")

  n_runs = max(sum(c.values()) for c in dists.values())
  print(f"repeats per thread config (max): {n_runs}")
  print(f"unanimity weight: {unanimity_note(n_runs)}\n")

  tally = collections.Counter()
  rows = []
  for key in sorted(dists):
    threads, kind, profile, scale = key
    if want_kind and kind != want_kind:
      continue
    counter = dists[key]
    total = sum(counter.values())
    top, top_n = counter.most_common(1)[0]
    winners = collections.Counter()
    for ordering, k in counter.items():
      winners[ordering[0]] += k
    win_top, win_n = winners.most_common(1)[0]

    if len(counter) == 1:
      verdict = "unanimous"
    elif top_n * 2 > total:
      verdict = f"dominant {top_n}/{total}"
    else:
      verdict = f"SPLIT {top_n}/{total}"
    tally[verdict.split()[0]] += 1
    tally["winner-stable" if win_n == total else "winner-MOVES"] += 1

    rows.append((threads, kind, profile, scale, total, len(counter),
                 verdict, win_top, win_n, counter))

  print(f"{'cfg':<4} {'kind':<5} {'profile':<7} {'scale':>8} "
        f"{'runs':>4} {'ords':>4}  {'verdict':<14} winner")
  print("-" * 78)
  for (threads, kind, profile, scale, total, distinct,
       verdict, win_top, win_n, counter) in rows:
    flag = "" if win_n == total else f"  <<< winner moves ({win_n}/{total})"
    print(f"{threads:>3}t {kind:<5} {profile:<7} {scale:>8} "
          f"{total:>4} {distinct:>4}  {verdict:<14} {win_top}{flag}")
    if distinct > 1:
      for ordering, k in counter.most_common():
        print(f"{'':>22}{k}/{total}  {' < '.join(ordering)}")

  print()
  for k in ("unanimous", "dominant", "SPLIT"):
    print(f"{k:<12} {tally.get(k, 0)}")
  print(f"{'winner stable':<12} {tally.get('winner-stable', 0)}")
  print(f"{'winner moves':<12} {tally.get('winner-MOVES', 0)}")
  return 0


if __name__ == "__main__":
  sys.exit(main(sys.argv))

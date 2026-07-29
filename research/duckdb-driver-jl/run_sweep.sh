#!/usr/bin/env bash
# full benchmark sweep for this directory.
#
# two thread configurations x N repeats, then merge:
#   - two configurations because DuckDB takes its thread count from Julia's
#     (database.jl:81-82), so a 1-thread run measures the registered-scan tier
#     with its parallelism switched off
#   - repeats because the deliverable is the per-cell path ORDERING, and an
#     ordering that does not reproduce is not a result
#
# REPEAT COUNTS ARE ASYMMETRIC BY DESIGN. the 64-thread configuration is much
# noisier than the 1-thread one: §7.4 shows the registered scan degrading
# sharply under threads, worst at small scales, and after the harness repair
# every non-reproducing ordering was at 64 threads while the sole 1-thread
# instability went away. two repeats can tell you an ordering did not
# reproduce; they cannot tell you which ordering dominates, or whether a flip
# is a coin-toss or a rare excursion. so -t auto gets more.
#
# SCHEDULING — why this is only partly parallel:
#   the `-t 1` runs use one thread each, so on a many-core box they run
#   CONCURRENTLY with no measurable contention.
#   the `-t auto` runs each claim every core. running two at once would
#   oversubscribe the machine 2x and inflate both — and since the deliverable
#   is a timing ORDERING, contention noise could flip cells spuriously. so
#   those run one after another, and the wall clock is roughly
#   (10 min) + (10 min x n_auto).
#
# usage: ./run_sweep.sh [n_repeats_1t] [n_repeats_auto]
#        defaults: 2 6
set -euo pipefail
cd "$(dirname "$0")"

n_one=${1:-2}
n_auto=${2:-6}
letters=(a b c d e f g h i j k l m n o p q r s t u v w x y z)

if (( n_one < 2 || n_auto < 2 )); then
  echo "both repeat counts must be >= 2: an ordering seen once is not reproduced," >&2
  echo "and run_all.jl merge now errors rather than calling it stable" >&2
  exit 2
fi
if (( n_one > 26 || n_auto > 26 )); then
  echo "repeat counts above 26 exhaust the single-letter tags" >&2
  exit 2
fi

# clearing raw/ is what keeps provenance coherent: a leftover file from an
# older harness merges silently and is compared for stability against runs
# measured differently. do_merge warns on a wide mtime spread for the same
# reason, but not clearing here is the way that hazard usually arrives
rm -f raw/results-*.json

echo "===== threads=1, ${n_one} repeats IN PARALLEL ($(nproc) cores available) ====="
pids=()
for ((i = 0; i < n_one; i++)); do
  rep=${letters[$i]}
  julia --project=. -t 1 run_all.jl run "t1-${rep}" > "sweep-t1-${rep}.log" 2>&1 &
  pids+=($!)
done
# NOT `wait $pid && echo ...`: set -e ignores a failing non-final command of an
# AND-OR list, so a died run was swallowed and the sweep carried on to merge an
# incomplete raw/ set — which then triggered a vacuously "stable" ordering table
for ((i = 0; i < n_one; i++)); do
  wait "${pids[$i]}"
  echo "  t1-${letters[$i]} done"
done

# serial: each of these wants the whole machine
for ((i = 0; i < n_auto; i++)); do
  rep=${letters[$i]}
  echo "===== threads=auto repeat=${rep} ($((i + 1))/${n_auto}, serial — needs all cores) ====="
  julia --project=. -t auto run_all.jl run "tauto-${rep}"
  echo
done

julia --project=. run_all.jl merge

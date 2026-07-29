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
# CONCURRENCY WIDTH IS CAPPED, NOT SET BY THE REPEAT COUNT. the claim above —
# that concurrent `-t 1` runs do not contend measurably — was established for
# TWO of them. six concurrent processes each streaming 1M-row tables contend on
# memory bandwidth rather than on cores, and idle cores do not help with that.
# if such contention inflated every read mode equally it would be harmless to an
# ordering, but `materialized` builds a whole DataFrame while `stream_first`
# touches one chunk, so there is no reason to expect it to land evenly — and the
# ordering is the deliverable. so repeats above the verified width run as
# sequential batches OF that width. raise PARALLEL_1T only with a measurement.
#
# usage: ./run_sweep.sh [n_repeats_1t] [n_repeats_auto]
#        defaults: 2 6
set -euo pipefail
cd "$(dirname "$0")"

n_one=${1:-2}
n_auto=${2:-6}
PARALLEL_1T=${PARALLEL_1T:-2}
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

echo "===== threads=1, ${n_one} repeats in batches of ${PARALLEL_1T} ($(nproc) cores) ====="
for ((base = 0; base < n_one; base += PARALLEL_1T)); do
  pids=()
  batch=()
  for ((j = 0; j < PARALLEL_1T && base + j < n_one; j++)); do
    rep=${letters[$((base + j))]}
    batch+=("$rep")
    julia --project=. -t 1 run_all.jl run "t1-${rep}" > "sweep-t1-${rep}.log" 2>&1 &
    pids+=($!)
  done
  # NOT `wait $pid && echo ...`: set -e ignores a failing non-final command of an
  # AND-OR list, so a died run was swallowed and the sweep carried on to merge an
  # incomplete raw/ set — which then triggered a vacuously "stable" ordering table
  for ((j = 0; j < ${#pids[@]}; j++)); do
    wait "${pids[$j]}"
    echo "  t1-${batch[$j]} done"
  done
done

# serial: each of these wants the whole machine
for ((i = 0; i < n_auto; i++)); do
  rep=${letters[$i]}
  echo "===== threads=auto repeat=${rep} ($((i + 1))/${n_auto}, serial — needs all cores) ====="
  julia --project=. -t auto run_all.jl run "tauto-${rep}"
  echo
done

julia --project=. run_all.jl merge

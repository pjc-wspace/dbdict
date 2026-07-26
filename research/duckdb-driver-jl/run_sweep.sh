#!/usr/bin/env bash
# full benchmark sweep for this directory.
#
# two thread configurations x two repeats, then merge:
#   - two configurations because DuckDB takes its thread count from Julia's
#     (database.jl:81-82), so a 1-thread run measures the registered-scan tier
#     with its parallelism switched off
#   - two repeats per configuration because the deliverable is the per-cell path
#     ORDERING, and an ordering that does not reproduce is not a result
#
# SCHEDULING — why this is only partly parallel:
#   the two `-t 1` runs use one thread each, so on a many-core box they run
#   CONCURRENTLY with no measurable contention.
#   the two `-t auto` runs each claim every core. running those two at once
#   would oversubscribe the machine 2x and inflate both — and since the whole
#   deliverable is a timing ORDERING, contention noise could flip cells
#   spuriously. so those two run one after the other.
#
# usage: ./run_sweep.sh
set -euo pipefail
cd "$(dirname "$0")"

rm -f raw/results-*.json

echo "===== threads=1, both repeats IN PARALLEL ($(nproc) cores available) ====="
julia --project=. -t 1 run_all.jl run t1-a > sweep-t1-a.log 2>&1 &
pid_a=$!
julia --project=. -t 1 run_all.jl run t1-b > sweep-t1-b.log 2>&1 &
pid_b=$!
wait $pid_a && echo "  t1-a done"
wait $pid_b && echo "  t1-b done"

# serial: each of these wants the whole machine
for rep in a b; do
  echo "===== threads=auto repeat=${rep} (serial — needs all cores) ====="
  julia --project=. -t auto run_all.jl run "tauto-${rep}"
  echo
done

julia --project=. run_all.jl merge

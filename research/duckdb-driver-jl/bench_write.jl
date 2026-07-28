# bench_write.jl
#
# times the bulk-write paths per type profile x scale:
#   appender      — per-cell DuckDB.append loop
#   register      — register_table + INSERT INTO ... SELECT
#   register_flat — struct leaves registered flat, struct rebuilt in SQL
#   literal       — batched INSERT INTO ... VALUES of generated SQL literals
#
# the deliverable is the per-cell path ORDERING, which is stable across runs;
# absolute numbers are indicative and machine-specific (goal.md constraints).
#
# every applicable cell is content-verified (not just row-counted) before it is
# timed — see bench_common.jl `check_written` and findings.md §2b for why a
# count check alone would not catch a misaligned write.
#
# standalone: julia --project=. bench_write.jl [scale ...]
# as a library: include it, then call bench_writes(con)

using BenchmarkTools
using DuckDB

include("bench_common.jl")

# benchmark one (profile, scale, path) cell.
#
# `setup` recreates the destination table before every sample so each sample
# measures a write into an empty table, never an append onto the previous
# sample's rows. evals=1 keeps setup paired 1:1 with the timed expression —
# with evals>1 the setup would run once for several writes and the table would
# accumulate. the $-interpolation lifts these out of global scope, without
# which we would be timing julia's slow global lookups rather than duckdb
function bench_cell(con, pname, path, n)
  p = profile(pname)
  cols = getdata(pname, n)
  tbl = "w_$(pname)_$(path)"
  view = "v_$(pname)_$(path)"

  # correctness gate first: a fast number for a path that writes wrong data is
  # worse than no number at all
  recreate_table!(con, tbl, p.ddl)
  run_write!(con, path, tbl, cols, view)
  bad = check_written(con, tbl, cols)
  bad === nothing || return (ok = false, reason = "CONTENT MISMATCH: $bad")

  b = @benchmarkable run_write!($con, $path, $tbl, $cols, $view) setup =
    (recreate_table!($con, $tbl, $(p.ddl))) evals = 1
  t = run(b)

  med = median(t).time                       # nanoseconds
  return (ok = true,
          reason = nothing,
          median_ns = med,
          min_ns = minimum(t).time,
          samples = length(t.times),
          allocs = t.allocs,
          memory_bytes = t.memory,
          rows_per_sec = n / (med / 1e9))
end

# sweep every profile x scale x path, returning one row per cell (including the
# skipped ones — a silently missing cell would read as "not measured" when it
# is actually "cannot be measured, for this reason")
function bench_writes(con; scales = SCALES, profiles = [p.name for p in PROFILES], verbose = true)
  out = NamedTuple[]
  for n in scales
    for pname in profiles, path in WRITE_PATHS
      reason = skip_reason(pname, path)
      if reason !== nothing
        push!(out, (kind = "write", profile = pname, scale = n, path = path,
                    status = "skipped", reason = reason))
        continue
      end
      verbose && print(rpad("  write $pname/$path @ $n", 46))
      r = bench_cell(con, pname, path, n)
      if !r.ok
        verbose && println("FAILED — ", r.reason)
        push!(out, (kind = "write", profile = pname, scale = n, path = path,
                    status = "failed", reason = r.reason))
        continue
      end
      verbose && println(rpad(BenchmarkTools.prettytime(r.median_ns), 14),
                         "  ", round(Int, r.rows_per_sec), " rows/s  (",
                         r.samples, " samples)")
      push!(out, (kind = "write", profile = pname, scale = n, path = path,
                  status = "ok", median_ns = r.median_ns, min_ns = r.min_ns,
                  samples = r.samples, allocs = r.allocs,
                  memory_bytes = r.memory_bytes, rows_per_sec = r.rows_per_sec))
      # drop the cell's table before the next one. recreate_table! is CREATE OR
      # REPLACE and never dropped anything, so the later cells of a scale ran
      # with every earlier cell's table still resident — by list/literal at 1M
      # that was a dozen-odd tables of a million rows each. cells within a sweep
      # have to be measured under the same conditions to be comparable
      DBInterface.execute(con, "DROP TABLE IF EXISTS w_$(pname)_$(path)")
    end
    # drop this scale's data before building the next — four profiles at 1M
    # rows held simultaneously is a few hundred MB
    free_data!()
  end
  return out
end

if abspath(PROGRAM_FILE) == @__FILE__
  scales = isempty(ARGS) ? SCALES : parse.(Int, ARGS)
  con = DBInterface.connect(DuckDB.DB)
  println("write benchmarks — threads=", Threads.nthreads(), " scales=", scales)
  results = bench_writes(con; scales = scales)
  nskip = count(r -> r.status == "skipped", results)
  println("\n", length(results), " cells: ",
          count(r -> r.status == "ok", results), " measured, ",
          nskip, " skipped, ",
          count(r -> r.status == "failed", results), " failed")
end

# bench_read.jl
#
# times reads of the same tables the write benchmarks build:
#   materialized — DBInterface.execute + DataFrame (all chunks fetched, then
#                  converted column-at-a-time; result.jl:543-567)
#   streaming    — DuckDB.StreamResult + Tables.partitions, consuming every
#                  chunk (<= VECTOR_SIZE = 2048 rows each; result.jl:784-822)
#   stream_first — time to FIRST chunk only. this is the number that justifies
#                  streaming at all: if a caller can start work on chunk 1, the
#                  latency that matters is not the full-table time
#
# standalone: julia --project=. bench_read.jl [scale ...]

using BenchmarkTools
using DataFrames
using DuckDB
using Tables

include("bench_common.jl")

const READ_MODES = ["materialized", "streaming", "stream_first"]

# populate a table with a path that is known to work for this profile, so read
# benchmarks never depend on a write path's availability
function populate!(con, pname, n)
  p = profile(pname)
  tbl = "r_$(pname)"
  cols = getdata(pname, n)
  recreate_table!(con, tbl, p.ddl)
  path = skip_reason(pname, "register") === nothing ? "register" :
         skip_reason(pname, "register_flat") === nothing ? "register_flat" : "literal"
  run_write!(con, path, tbl, cols, "rv_$(pname)")
  bad = check_written(con, tbl, cols)
  bad === nothing || error("read fixture for $pname is wrong: $bad")
  return tbl
end

# ALL THREE modes close their QueryResult, and that symmetry is the point.
#
# an earlier revision closed only read_first_chunk, which was worse than closing
# none of them: the three modes are ranked against each other, so a bias they
# all share largely cancels, while a bias only one of them carries does not.
# stream_first was paying a deterministic duckdb_destroy_result inside its timed
# region while materialized and streaming still leaked to finalizers whose GC
# landed in whichever window ran next. that is an asymmetry manufactured by a
# half-fix, and the ordering is the deliverable.
#
# verified empirically that closing after consuming is safe: a DataFrame built
# from a QueryResult, a fully-consumed stream, and a first chunk all keep
# correct values after close! plus two forced GCs, because the chunk converter
# allocates owned julia arrays rather than viewing duckdb memory.
function read_materialized(con, sql)
  q = DBInterface.execute(con, sql)
  try
    return DataFrame(q)
  finally
    DBInterface.close!(q)
  end
end

# consume every partition — without consuming, a streaming benchmark would time
# the query's setup and nothing else
function read_streaming(con, sql)
  q = DBInterface.execute(con, sql, DuckDB.StreamResult)
  try
    rows = 0
    for chunk in Tables.partitions(q)
      # a chunk is a column table (NamedTuple of vectors, result.jl:771-796);
      # Tables.rows(chunk) has no length method, so count via the first column
      cols = Tables.columns(chunk)
      rows += length(first(cols))
    end
    return rows
  finally
    DBInterface.close!(q)
  end
end

# first chunk only — results are strictly single-pass (result.jl:800-807), so
# the rest of the result is deliberately not consumed.
#
# the close is NOT optional. an earlier version returned the first chunk and
# let the QueryResult fall to its finalizer; BenchmarkTools then ran thousands
# of samples per cell (up to its 10,000 cap), so thousands of un-finalized
# duckdb result handles piled up and their eventual GC landed inside later
# samples' timing windows. that turned "time to first chunk" partly into a
# measure of finalizer backlog.
#
# closing here puts a bounded, deterministic duckdb_destroy_result inside the
# timed region, which slightly overstates first-chunk latency. that is the
# right trade: a small known overhead beats an unbounded deferred one. the
# alternative — closing in BenchmarkTools' `teardown`, outside the timing —
# does not work without reaching into its internal `__return_val` binding,
# because the core expression is compiled as its own @noinline function
# (BenchmarkTools execution.jl:646-666) and its locals are not in teardown's
# scope. StreamResult is only a type tag (DuckDB.jl:16); execute returns a
# QueryResult, which is what close! accepts (result.jl:766).
function read_first_chunk(con, sql)
  q = DBInterface.execute(con, sql, DuckDB.StreamResult)
  try
    return first(Tables.partitions(q))
  finally
    DBInterface.close!(q)
  end
end

function bench_read_cell(con, mode, sql)
  b = if mode == "materialized"
    @benchmarkable read_materialized($con, $sql)
  elseif mode == "streaming"
    @benchmarkable read_streaming($con, $sql)
  else
    @benchmarkable read_first_chunk($con, $sql)
  end
  t = run(b)
  med = median(t).time
  return (median_ns = med, min_ns = minimum(t).time, samples = length(t.times),
          allocs = t.allocs, memory_bytes = t.memory)
end

function bench_reads(con; scales = SCALES, profiles = [p.name for p in PROFILES], verbose = true)
  out = NamedTuple[]
  for n in scales
    for pname in profiles
      tbl = populate!(con, pname, n)
      sql = "SELECT * FROM $tbl"
      for mode in READ_MODES
        verbose && print(rpad("  read $pname/$mode @ $n", 46))
        r = bench_read_cell(con, mode, sql)
        # rows/sec is meaningless for stream_first (it reads one chunk), so it
        # is reported as missing rather than as a misleading number
        rps = mode == "stream_first" ? nothing : n / (r.median_ns / 1e9)
        verbose && println(rpad(BenchmarkTools.prettytime(r.median_ns), 14), "  ",
                           rps === nothing ? "(first chunk)" : "$(round(Int, rps)) rows/s",
                           "  (", r.samples, " samples)")
        push!(out, (kind = "read", profile = pname, scale = n, path = mode,
                    status = "ok", median_ns = r.median_ns, min_ns = r.min_ns,
                    samples = r.samples, allocs = r.allocs,
                    memory_bytes = r.memory_bytes, rows_per_sec = rps))
      end
      # drop this profile's fixture before building the next. without it the
      # loop accumulates: at the 1M scale, reading r_list ran with r_flat,
      # r_rich and r_struct all still holding 1M rows. that is the same
      # leftover-data confound the write->read boundary was fixed for, one
      # level down, and it made the four profiles' cells non-comparable
      DBInterface.execute(con, "DROP TABLE IF EXISTS $tbl")
    end
    free_data!()
  end
  return out
end

if abspath(PROGRAM_FILE) == @__FILE__
  scales = isempty(ARGS) ? SCALES : parse.(Int, ARGS)
  con = DBInterface.connect(DuckDB.DB)
  println("read benchmarks — threads=", Threads.nthreads(), " scales=", scales)
  results = bench_reads(con; scales = scales)
  println("\n", length(results), " cells measured")
end

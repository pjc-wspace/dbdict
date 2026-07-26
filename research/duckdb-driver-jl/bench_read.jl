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

read_materialized(con, sql) = DataFrame(DBInterface.execute(con, sql))

# consume every partition. `count` forces the iteration — without consuming,
# a streaming benchmark would time the query's setup and nothing else
function read_streaming(con, sql)
  q = DBInterface.execute(con, sql, DuckDB.StreamResult)
  rows = 0
  for chunk in Tables.partitions(q)
    # a chunk is a column table (NamedTuple of vectors, result.jl:771-796);
    # Tables.rows(chunk) has no length method, so count via the first column
    cols = Tables.columns(chunk)
    rows += length(first(cols))
  end
  return rows
end

# first chunk only — results are strictly single-pass (result.jl:800-807), so
# this deliberately abandons the rest of the result
function read_first_chunk(con, sql)
  q = DBInterface.execute(con, sql, DuckDB.StreamResult)
  return first(Tables.partitions(q))
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

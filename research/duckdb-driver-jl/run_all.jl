# run_all.jl — the single entry point for this directory
#
# two modes:
#
#   julia --project=. run_all.jl run <tag> [scale...]
#                                            run verifications + benchmarks for
#                                            THIS process's thread count, write
#                                            raw/results-<tag>.json
#   julia --project=. run_all.jl merge       merge every raw/results-*.json into
#                                            results.md + results.json
#
# split this way because the thread count is fixed at process start: comparing
# 1-thread against -t auto means two processes, and "run the suite twice to
# confirm the orderings are stable" means two of each. the merge step is what
# actually checks that stability claim.
#
# typical full sweep (see run_sweep.sh):
#   julia --project=. -t 1    run_all.jl run t1-a
#   julia --project=. -t 1    run_all.jl run t1-b
#   julia --project=. -t auto run_all.jl run tauto-a
#   julia --project=. -t auto run_all.jl run tauto-b
#   julia --project=. run_all.jl merge

using BenchmarkTools
using DuckDB
using JSON
using Pkg

include("bench_common.jl")
include("bench_write.jl")
include("bench_read.jl")

const RAW_DIR = joinpath(@__DIR__, "raw")

# ---------------------------------------------------------------------------
# environment capture — every number is only meaningful with this attached
# ---------------------------------------------------------------------------
function environment()
  deps = Pkg.dependencies()
  ver(name) = begin
    hit = findfirst(d -> d.name == name, deps)
    hit === nothing ? "absent" : string(deps[hit].version)
  end
  cpus = Sys.cpu_info()
  return Dict(
    "julia_version" => string(VERSION),
    "threads" => Threads.nthreads(),
    "duckdb_jl" => ver("DuckDB"),
    "duckdb_jll" => ver("DuckDB_jll"),
    "benchmarktools" => ver("BenchmarkTools"),
    "dataframes" => ver("DataFrames"),
    "cpu_model" => isempty(cpus) ? "unknown" : cpus[1].model,
    "cpu_count" => length(cpus),
    "total_memory_gb" => round(Sys.total_memory() / 2^30, digits = 1),
    "kernel" => string(Sys.KERNEL),
    "word_size" => Sys.WORD_SIZE,
  )
end

# ---------------------------------------------------------------------------
# verifications — the phase 1 scripts, re-run as subprocesses
# ---------------------------------------------------------------------------
# subprocesses rather than `include` so one script's globals cannot leak into
# another's, and so a crash cannot take the benchmark run with it.
#
# verify_list_appender_gc.jl is NOT in this list: its `natural` mode segfaults
# on purpose and takes several minutes. run it by hand (findings.md §5).
const VERIFY_SCRIPTS = ["verify_blob_appender.jl", "verify_enum_appender.jl",
                        "verify_appender_transaction.jl", "verify_structarray_register.jl"]

function run_verifications()
  out = Dict{String, Any}()
  for s in VERIFY_SCRIPTS
    print(rpad("  verify $s", 46))
    p = run(pipeline(`$(Base.julia_cmd()) --project=$(@__DIR__) $(joinpath(@__DIR__, s))`,
                     stdout = devnull, stderr = devnull), wait = false)
    wait(p)
    ok = p.exitcode == 0
    out[s] = Dict("exit_code" => p.exitcode, "ok" => ok)
    println(ok ? "ok" : "FAILED (exit $(p.exitcode))")
  end
  return out
end

# ---------------------------------------------------------------------------
# run mode
# ---------------------------------------------------------------------------
function do_run(tag; scales = SCALES)
  mkpath(RAW_DIR)
  env = environment()
  println("=== run '", tag, "' — julia ", env["julia_version"],
          ", DuckDB.jl ", env["duckdb_jl"], ", threads=", env["threads"], " ===\n")

  println("verifications:")
  verifs = run_verifications()

  con = DBInterface.connect(DuckDB.DB)
  println("\nwrite benchmarks:")
  writes = bench_writes(con; scales = scales)
  println("\nread benchmarks:")
  reads = bench_reads(con; scales = scales)

  path = joinpath(RAW_DIR, "results-$(tag).json")
  open(path, "w") do io
    JSON.print(io, Dict("tag" => tag, "environment" => env,
                        "verifications" => verifs,
                        "cells" => vcat(writes, reads)), 2)
  end
  println("\nwrote ", path)
  return path
end

# ---------------------------------------------------------------------------
# merge mode
# ---------------------------------------------------------------------------
cellkey(c) = (c["kind"], c["profile"], c["scale"], c["path"])

fmt_time(ns) = ns === nothing ? "—" : BenchmarkTools.prettytime(float(ns))
fmt_int(x) = x === nothing ? "—" : string(round(Int, x))

# the deliverable: for one (kind, profile, scale), which path was fastest,
# second, ... — this ordering is what must reproduce across runs
function ordering(cells, kind, prof, scale)
  ok = [c for c in cells if c["kind"] == kind && c["profile"] == prof &&
        c["scale"] == scale && c["status"] == "ok"]
  sort!(ok, by = c -> c["median_ns"])
  return [c["path"] for c in ok]
end

function do_merge()
  files = sort(filter(f -> endswith(f, ".json"), readdir(RAW_DIR, join = true)))
  isempty(files) && error("no raw/results-*.json found — run the sweep first")
  runs = [JSON.parsefile(f) for f in files]
  println("merging ", length(runs), " runs: ", join([r["tag"] for r in runs], ", "))

  # group runs by thread count; ordering stability is checked WITHIN a thread
  # count (across threads the ordering is expected to differ — that is the
  # question the two configurations were run to answer)
  bythreads = Dict{Int, Vector{Any}}()
  for r in runs
    push!(get!(bythreads, r["environment"]["threads"], []), r)
  end

  io = IOBuffer()
  println(io, "# DuckDB.jl 1.5.2 — benchmark results\n")
  println(io, "Generated by `run_all.jl merge`. The deliverable is the per-cell path")
  println(io, "**ordering**, which is stable across runs; absolute times are indicative and")
  println(io, "machine-specific (goal.md constraints).\n")

  e = first(runs)["environment"]
  println(io, "## Environment\n")
  println(io, "| Field | Value |")
  println(io, "|---|---|")
  for (k, label) in [("julia_version", "Julia"), ("duckdb_jl", "DuckDB.jl"),
                     ("duckdb_jll", "DuckDB_jll"), ("benchmarktools", "BenchmarkTools"),
                     ("dataframes", "DataFrames"), ("cpu_model", "CPU"),
                     ("cpu_count", "CPU threads"), ("total_memory_gb", "RAM (GB)"),
                     ("kernel", "Kernel"), ("word_size", "Word size")]
    println(io, "| ", label, " | ", e[k], " |")
  end
  println(io, "\nThread configurations measured: ",
          join(sort(collect(keys(bythreads))), ", "), " (`Threads.nthreads()`).")
  println(io, "DuckDB takes its thread count from Julia's (`database.jl:81-82`), so this")
  println(io, "controls DuckDB's parallelism too.\n")

  # verification status
  println(io, "## Verification scripts\n")
  for (name, v) in sort(collect(first(runs)["verifications"]), by = first)
    println(io, "- `", name, "` — ", v["ok"] ? "pass" : "FAIL (exit $(v["exit_code"]))")
  end
  println(io, "\n`verify_list_appender_gc.jl` is excluded from automated runs: its")
  println(io, "`natural` mode segfaults by design (findings.md §5).\n")

  # per thread-config result tables
  for nthreads in sort(collect(keys(bythreads)))
    group = bythreads[nthreads]
    cells = vcat([r["cells"] for r in group]...)
    println(io, "## Results — ", nthreads, " thread", nthreads == 1 ? "" : "s", "\n")

    for kind in ["write", "read"]
      println(io, "### ", titlecase(kind), "s\n")
      println(io, "| profile | scale | path | median | rows/s | allocs | memory | samples |")
      println(io, "|---|---|---|---|---|---|---|---|")
      for prof in [p.name for p in PROFILES], scale in SCALES
        sel = [c for c in cells if c["kind"] == kind && c["profile"] == prof && c["scale"] == scale]
        # collapse repeat runs: report the FIRST run's numbers per path
        seen = String[]
        for c in sel
          c["path"] in seen && continue
          push!(seen, c["path"])
          if c["status"] != "ok"
            println(io, "| ", prof, " | ", scale, " | ", c["path"], " | _", c["status"],
                    "_ | — | — | — | ", get(c, "reason", ""), " |")
          else
            println(io, "| ", prof, " | ", scale, " | ", c["path"], " | ",
                    fmt_time(c["median_ns"]), " | ", fmt_int(get(c, "rows_per_sec", nothing)),
                    " | ", fmt_int(c["allocs"]), " | ",
                    Base.format_bytes(c["memory_bytes"]), " | ", c["samples"], " |")
          end
        end
      end
      println(io)
    end
  end

  # ordering stability — the actual verify gate for phase 2
  println(io, "## Path ordering stability\n")
  println(io, "Per (kind, profile, scale), paths sorted fastest-first. The orderings must")
  println(io, "agree between repeat runs at the same thread count; that agreement — not the")
  println(io, "absolute times — is what this session promises.\n")
  unstable = 0
  println(io, "| threads | kind | profile | scale | ordering (fastest first) | stable |")
  println(io, "|---|---|---|---|---|---|")
  for nthreads in sort(collect(keys(bythreads)))
    group = bythreads[nthreads]
    for kind in ["write", "read"], prof in [p.name for p in PROFILES], scale in SCALES
      ords = [ordering(r["cells"], kind, prof, scale) for r in group]
      filter!(!isempty, ords)
      isempty(ords) && continue
      stable = all(o -> o == ords[1], ords)
      stable || (unstable += 1)
      println(io, "| ", nthreads, " | ", kind, " | ", prof, " | ", scale, " | ",
              join(ords[1], " < "), " | ", stable ? "yes" :
              "**NO** — also saw " * join([join(o, " < ") for o in ords[2:end]], " / "), " |")
    end
  end
  println(io, "\n", unstable == 0 ?
          "All orderings reproduced across repeat runs." :
          "**$unstable ordering(s) did not reproduce** — treat those cells as too close to call.")

  write(joinpath(@__DIR__, "results.md"), String(take!(io)))
  open(joinpath(@__DIR__, "results.json"), "w") do f
    JSON.print(f, Dict("runs" => runs), 2)
  end
  println("wrote results.md and results.json (", unstable, " unstable ordering(s))")
  return unstable
end

if abspath(PROGRAM_FILE) == @__FILE__
  mode = isempty(ARGS) ? "run" : ARGS[1]
  if mode == "run"
    tag = length(ARGS) >= 2 ? ARGS[2] : "default"
    # optional trailing scales, for smoke-testing the pipeline cheaply
    scales = length(ARGS) >= 3 ? parse.(Int, ARGS[3:end]) : SCALES
    do_run(tag; scales = scales)
  elseif mode == "merge"
    do_merge()
  else
    error("usage: run_all.jl run <tag> | run_all.jl merge")
  end
end

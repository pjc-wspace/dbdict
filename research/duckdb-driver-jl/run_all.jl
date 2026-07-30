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

# these scripts are observational PROBES, not pass/fail tests. several of them
# deliberately record broken driver behaviour (a misaligned appender batch, a
# rollback leak) — that observation is the point, so "the script found something
# bad" is not a failure condition. the only real failure is the process dying.
#
# two bugs were fixed here:
#   - `ok = p.exitcode == 0` called a signal-killed run a pass. julia reports
#     exitcode 0 with termsignal set when a child dies on a signal, and Base's
#     own predicate is `proc.exitcode == 0 && proc.termsignal == 0`
#     (base/process.jl). a segfault is a live failure mode for these scripts
#     (§5.1.4), so this mattered. `success(p)` checks both.
#   - output went to devnull, which destroyed the probes' findings — the very
#     thing they exist to produce. it is captured to logs/ now.
function run_verifications(tag)
  out = Dict{String, Any}()
  logdir = joinpath(@__DIR__, "logs")
  mkpath(logdir)
  for s in VERIFY_SCRIPTS
    print(rpad("  verify $s", 46))
    logfile = joinpath(logdir, "verify-$(tag)-$(s).log")
    p = open(logfile, "w") do io
      proc = run(pipeline(`$(Base.julia_cmd()) --project=$(@__DIR__) $(joinpath(@__DIR__, s))`,
                          stdout = io, stderr = io), wait = false)
      wait(proc)
      proc
    end
    ran = success(p)
    out[s] = Dict("exit_code" => p.exitcode, "termsignal" => p.termsignal,
                  "ok" => ran, "log" => relpath(logfile, @__DIR__))
    println(ran ? "ran" :
            "CRASHED (exit $(p.exitcode), signal $(p.termsignal)) — see $(relpath(logfile, @__DIR__))")
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
  verifs = run_verifications(tag)

  con = DBInterface.connect(DuckDB.DB)
  println("\nwrite benchmarks:")
  writes = bench_writes(con; scales = scales)

  # reads get a FRESH database. the write sweep leaves its tables resident —
  # recreate_table! is CREATE OR REPLACE (bench_common.jl:171), nothing drops
  # anything, and the table names carry no scale (bench_write.jl:35), so after
  # the sweep every w_* table holds its largest scale. reads run last, so on the
  # shared connection even the 10k read cells were measured against gigabytes of
  # leftover write data. reads build their own r_* fixtures (bench_read.jl:25-36)
  # and never touch the write tables, so a clean database is the honest baseline.
  DBInterface.close!(con)
  con = DBInterface.connect(DuckDB.DB)
  println("\nread benchmarks:")
  reads = bench_reads(con; scales = scales)
  DBInterface.close!(con)

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

  # disclose the repeat-collapse rule, because nothing in the tables reveals it.
  # every number below comes from ONE repeat per thread config, and which repeat
  # is decided by the filename sort at `files` above — so the `-a` tag wins for
  # no reason other than that "a" sorts first. that is a naming coincidence doing
  # load-bearing work: rename the tags and every figure in this file changes
  # without any measurement changing
  println(io, "**Absolute times below are from a single repeat per thread configuration**,")
  println(io, "not an average over the $(length(runs)) runs merged here. `raw/*.json` is")
  println(io, "sorted by filename and the first value seen for each path is the one")
  println(io, "reported, so the `-a` run supplies every number in the tables — for no")
  println(io, "better reason than that `a` sorts before the other tags. The remaining")
  println(io, "repeats feed only the ordering-stability table at the end of this file;")
  println(io, "they never average or widen the figures.\n")

  # the environment table describes ALL runs, so drift between them must not be
  # silently papered over by reporting run 1's values. same for verifications
  # below: a failure in run 3 was previously invisible
  for r in runs[2:end]
    for (k, v) in first(runs)["environment"]
      k == "threads" && continue      # the sweep varies this deliberately
      # haskey first: a raw file written before a field was added to
      # environment() would otherwise raise a bare KeyError instead of the
      # drift message this block exists to produce
      if !haskey(r["environment"], k)
        error("environment drift between runs $(first(runs)["tag"]) and " *
              "$(r["tag"]): $k is missing entirely — raw files from different " *
              "harness versions cannot be merged")
      end
      r["environment"][k] == v || error(
        "environment drift between runs $(first(runs)["tag"]) and $(r["tag"]): " *
        "$k is $(repr(v)) vs $(repr(r["environment"][k]))")
    end
  end

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
  println(io, "These are observational probes, not pass/fail tests — several deliberately")
  println(io, "record broken driver behaviour. \"ran\" means the process completed without")
  println(io, "crashing; it does **not** mean the behaviour it probed was correct. Findings")
  println(io, "are in `logs/`. Reported across all $(length(runs)) runs.\n")
  # union across runs, not just the first: keying off run 1 would silently drop
  # a probe that only later runs executed, while going to the trouble of
  # printing "absent" for the reverse case
  allprobes = sort(collect(union([Set(keys(r["verifications"])) for r in runs]...)))
  for name in allprobes
    outcomes = String[]
    for r in runs
      v = get(r["verifications"], name, nothing)
      if v === nothing
        push!(outcomes, "$(r["tag"]): absent")
      elseif v["ok"]
        push!(outcomes, "$(r["tag"]): ran")
      else
        push!(outcomes, "$(r["tag"]): **CRASHED** (exit $(v["exit_code"]), " *
                        "signal $(get(v, "termsignal", "?")))")
      end
    end
    println(io, "- `", name, "` — ", join(outcomes, " · "))
  end
  println(io, "\n`verify_list_appender_gc.jl` is excluded from automated runs: its")
  println(io, "`natural` mode segfaults by design (findings.md §5).\n")

  # per thread-config result tables
  # a raw file left over from an older harness is the real hazard here, and it
  # is INVISIBLE: if its cells match the current PROFILES/SCALES they merge
  # silently and get compared for stability against runs measured differently.
  # nothing in the JSON records which harness produced it, so the best available
  # signal is the spread of file mtimes — a raw/ whose files were not written by
  # the same sweep deserves a look.
  #
  # (an earlier version of this warning claimed out-of-range cells "still feed
  # the stability table". that was wrong: the render loop and the stability loop
  # filter identically on PROFILES/SCALES, so such a cell feeds neither. it is
  # still worth reporting as a sign of a stale file, but it corrupts nothing.)
  known_profiles = Set(p.name for p in PROFILES)
  for r in runs
    for c in r["cells"]
      if !(c["profile"] in known_profiles) || !(c["scale"] in SCALES)
        @warn "raw cell outside the current PROFILES/SCALES — not rendered and not " *
              "compared, but a sign of a stale run in raw/: tag=$(r["tag"]) " *
              "profile=$(c["profile"]) scale=$(c["scale"]) path=$(c["path"])"
      end
    end
  end

  mtimes = [mtime(f) for f in files]
  spread = maximum(mtimes) - minimum(mtimes)
  if spread > 6 * 3600
    @warn "raw/*.json span $(round(spread / 3600, digits = 1)) hours — are these " *
          "all from the same sweep? a file from an older harness merges silently " *
          "and is compared for stability against the others"
  end

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
  unchecked = 0
  println(io, "| threads | kind | profile | scale | ordering (fastest first) | stable |")
  println(io, "|---|---|---|---|---|---|")
  for nthreads in sort(collect(keys(bythreads)))
    group = bythreads[nthreads]
    for kind in ["write", "read"], prof in [p.name for p in PROFILES], scale in SCALES
      ords = [ordering(r["cells"], kind, prof, scale) for r in group]
      filter!(!isempty, ords)
      isempty(ords) && continue
      # a single ordering compares equal to itself, so `all` is vacuously true
      # when a thread group holds one run — or when a cell was skipped in one
      # repeat and the empty ordering was filtered out above. reporting that as
      # "yes" claims a reproduction that never happened, in the one column this
      # document calls its deliverable
      if length(ords) < 2
        unchecked += 1
        verdict = "**not checked** — only $(length(ords)) run reported this cell"
      else
        stable = all(o -> o == ords[1], ords)
        stable || (unstable += 1)
        verdict = stable ? "yes" :
                  "**NO** — also saw " *
                  join([join(o, " < ") for o in ords[2:end]], " / ")
      end
      println(io, "| ", nthreads, " | ", kind, " | ", prof, " | ", scale, " | ",
              join(ords[1], " < "), " | ", verdict, " |")
    end
  end
  # the headline must not read as a clean bill of health when cells went
  # unchecked — that is how a one-run sweep used to print "all reproduced"
  headline = unstable == 0 ? "All compared orderings reproduced across repeat runs." :
             "**$unstable ordering(s) did not reproduce** — treat those cells as too close to call."
  if unchecked > 0
    headline *= "\n\n**$unchecked cell(s) were NOT checked for stability** — fewer than " *
                "two runs reported them, so no reproduction was tested."
  end
  println(io, "\n", headline)

  write(joinpath(@__DIR__, "results.md"), String(take!(io)))
  open(joinpath(@__DIR__, "results.json"), "w") do f
    JSON.print(f, Dict("runs" => runs), 2)
  end
  println("wrote results.md and results.json (", unstable, " unstable ordering(s), ",
          unchecked, " unchecked)")
  return (unstable = unstable, unchecked = unchecked)
end

if abspath(PROGRAM_FILE) == @__FILE__
  mode = isempty(ARGS) ? "run" : ARGS[1]
  if mode == "run"
    tag = length(ARGS) >= 2 ? ARGS[2] : "default"
    # optional trailing scales, for smoke-testing the pipeline cheaply
    scales = length(ARGS) >= 3 ? parse.(Int, ARGS[3:end]) : SCALES
    do_run(tag; scales = scales)
  elseif mode == "merge"
    # a cell nobody checked for stability is not a pass. exiting 0 regardless of
    # `unchecked` is the same silent-success shape as the run_sweep.sh `wait`
    # bug: set -euo pipefail can only catch what reports failure
    r = do_merge()
    if r.unchecked > 0
      error("$(r.unchecked) cell(s) had fewer than two runs and were never " *
            "checked for ordering stability — the sweep is incomplete")
    end
  else
    error("usage: run_all.jl run <tag> | run_all.jl merge")
  end
end

# verify_enum_appender.jl
#
# QUESTION (open behavior 2 of 4): can the appender write ENUM columns by
# appending plain strings? the driver study (notes/20260725-1007 §3a, gotcha 12)
# marked this *Inferred*, reasoning: appender.jl:93 stringifies UUIDs and relies
# on the C appender casting VARCHAR->UUID, so VARCHAR->ENUM should work the same
# way. that is an analogy, not a measurement — and `verify_blob_appender.jl`
# just showed the VARCHAR->BLOB cast succeeds only for a narrow slice of inputs,
# so the analogy is not safe to trust.
#
# this script measures the whole "stringify and let the C appender cast" family:
# ENUM (the open question) plus UUID and DECIMAL (the two paths the driver
# already ships, appender.jl:93 and :95) as controls. it also probes what
# happens on an INVALID enum value, because appender return codes are discarded
# (gotcha 2) and a generated writer must know whether bad data fails loudly,
# fails silently, or corrupts.
#
# run: julia --project=. verify_enum_appender.jl

using DuckDB
using UUIDs
using FixedPointDecimals

section(title) = println("\n== ", title)

function attempt(f)
  try
    return (ok = true, value = f(), err = nothing)
  catch e
    return (ok = false, value = nothing, err = sprint(showerror, e))
  end
end

# the C error slot the julia wrapper never reads (see findings.md §1). declared
# with our own types: Ptr{UInt8} makes the null check unambiguous
function appender_error(handle)
  p = ccall((:duckdb_appender_error, DuckDB.libduckdb), Ptr{UInt8}, (Ptr{Cvoid},), handle)
  return p == C_NULL ? nothing : unsafe_string(p)
end

# append a single value into a fresh single-column table and report everything
# that happened: julia exception, C-level errors after each step, rows landed,
# and the value read back.
#
# one table per case so a failure can never mask a later one, and the C error
# is sampled after EVERY step because duckdb_appender_error only keeps the
# latest — sampling once at the end attributes the wrong cause
function probe_append(con, tbl, sqltype, value)
  DBInterface.execute(con, "CREATE OR REPLACE TABLE $tbl (c $sqltype)")
  ap = DuckDB.Appender(con, tbl)
  cerrs = String[]
  threw = nothing

  for (name, f) in (("append", () -> DuckDB.append(ap, value)),
                    ("end_row", () -> DuckDB.end_row(ap)),
                    ("flush", () -> DuckDB.flush(ap)))
    r = attempt(f)
    e = appender_error(ap.handle)
    # the error slot persists, so the same message reappears on later steps —
    # only record transitions
    if e !== nothing && (isempty(cerrs) || !endswith(cerrs[end], e))
      push!(cerrs, "$name → $e")
    end
    if !r.ok
      threw = "$name → " * something(r.err, "")
      break
    end
  end
  attempt(() -> DuckDB.close(ap))

  n = only(only(DBInterface.execute(con, "SELECT count(*) AS n FROM $tbl")))
  got = n == 1 ? only(only(DBInterface.execute(con, "SELECT c FROM $tbl"))) : nothing
  return (threw = threw, cerrs = cerrs, rows = n, got = got)
end

function report(label, expected, r)
  println("\n  case: ", label)
  println("    julia exception : ", something(r.threw, "none"))
  println("    C errors        : ", isempty(r.cerrs) ? "none" : join(r.cerrs, " | "))
  println("    rows landed     : ", r.rows)
  if r.rows == 1
    println("    read back       : ", repr(r.got), "  ::", typeof(r.got))
    println("    matches expected: ", isequal(r.got, expected) ? "YES" : "NO (expected $(repr(expected)))")
  end
  # the dangerous quadrant for generated code: nothing threw, nothing landed
  if r.threw === nothing && r.rows == 0
    println("    >> SILENT DATA LOSS: no julia exception, row did not land")
  end
end

con = DBInterface.connect(DuckDB.DB)
DBInterface.execute(con, "CREATE TYPE mood AS ENUM ('sad', 'ok', 'happy')")

println("DuckDB.jl appender ENUM / stringify-cast verification")
println("driver source: ", dirname(pathof(DuckDB)))

# ---------------------------------------------------------------------------
# 1. the open question: VARCHAR -> ENUM
# ---------------------------------------------------------------------------
section("1. appending strings into an ENUM column")

# 1a. a value that is in the enum — the happy path codegen depends on
report("valid enum label \"happy\"", "happy",
       probe_append(con, "e_valid", "mood", "happy"))

# 1b. a value that is NOT in the enum. this is the case that decides whether a
# generated loader needs its own validation: does duckdb reject loudly, or does
# the row vanish silently the way the non-UTF-8 blob did?
report("invalid enum label \"banana\"", nothing,
       probe_append(con, "e_invalid", "mood", "banana"))

# 1c. right letters, wrong case. duckdb enum labels are literal strings, so this
# should behave like 1b — worth pinning down because dbdict dictionaries could
# easily disagree with the database on case
report("wrong-case label \"Happy\"", nothing,
       probe_append(con, "e_case", "mood", "Happy"))

# 1d. NULL into an enum column (appender.jl:91 routes Missing to append_null)
report("missing → NULL", missing,
       probe_append(con, "e_null", "mood", missing))

# ---------------------------------------------------------------------------
# 2. controls: the stringify-cast paths the driver already ships
# ---------------------------------------------------------------------------
# the study's ENUM inference was extrapolated from these. measuring them turns
# the extrapolation into two independent data points rather than an assumption
section("2. controls — the other stringify-then-cast paths")

u = UUID("6ba7b810-9dad-11d1-80b4-00c04fd430c8")   # fixed, not uuid4(): deterministic reruns
report("UUID value (appender.jl:93)", u,
       probe_append(con, "c_uuid", "UUID", u))

d = FixedDecimal{Int64, 4}(12.3456)
report("FixedDecimal (appender.jl:95)", d,
       probe_append(con, "c_decimal", "DECIMAL(18, 4)", d))

# a decimal with more fractional digits than the column holds: does the C
# appender round, truncate, or reject? relevant because dbdict typedefs pin
# DECIMAL(w,s) and generated code may hold a wider FixedDecimal
report("FixedDecimal over-precision → DECIMAL(18,2)", nothing,
       probe_append(con, "c_decimal_narrow", "DECIMAL(18, 2)", d))

# ---------------------------------------------------------------------------
# 3. does the enum cast survive a multi-row batch?
# ---------------------------------------------------------------------------
# single-row probes can hide buffering effects: the appender batches rows and
# only materialises them at flush. append a mix of good and bad labels and see
# what the table contains — this is what a real load looks like
section("3. multi-row batch with one bad label in the middle")

DBInterface.execute(con, "CREATE OR REPLACE TABLE e_batch (c mood)")
ap = DuckDB.Appender(con, "e_batch")
labels = ["sad", "ok", "banana", "happy"]
for lbl in labels
  attempt(() -> DuckDB.append(ap, lbl))
  attempt(() -> DuckDB.end_row(ap))
end
r_flush = attempt(() -> DuckDB.flush(ap))
println("    appended labels : ", labels)
println("    flush threw?    : ", r_flush.ok ? "no" : "YES: " * something(r_flush.err, ""))
println("    C error         : ", something(appender_error(ap.handle), "none"))
attempt(() -> DuckDB.close(ap))
rows = [r.c for r in DBInterface.execute(con, "SELECT c FROM e_batch")]
println("    rows in table   : ", repr(rows))
println("    >> ", length(rows) == length(labels) - 1 ? "bad row dropped, good rows kept" :
                   length(rows) == 0 ? "ENTIRE BATCH LOST" :
                   "partial: $(length(rows)) of $(length(labels))")

# ---------------------------------------------------------------------------
# 4. the real hazard: does a failed cell SHIFT the remaining values?
# ---------------------------------------------------------------------------
# section 3 looked like "bad row dropped, good rows kept" — but that table had
# one column, which hides the mechanism. a failed append does not advance the
# appender's internal column counter, so the *next* value is written into the
# slot the failed one was supposed to fill. with two or more columns that would
# misalign every subsequent value: silent corruption, far worse than row loss.
# measure it before recommending any appender-based writer.
section("4. multi-column table with one failing cell — does data shift?")

DBInterface.execute(con, "CREATE OR REPLACE TABLE e_shift (id INTEGER, m mood)")
ap4 = DuckDB.Appender(con, "e_shift")
batch = [(Int32(1), "sad"), (Int32(2), "banana"), (Int32(3), "ok"), (Int32(4), "happy")]
for (id, m) in batch
  attempt(() -> DuckDB.append(ap4, id))
  attempt(() -> DuckDB.append(ap4, m))
  attempt(() -> DuckDB.end_row(ap4))
end
attempt(() -> DuckDB.flush(ap4))
println("    appended        : ", batch)
println("    C error         : ", something(appender_error(ap4.handle), "none"))
attempt(() -> DuckDB.close(ap4))
got4 = [(r.id, r.m) for r in DBInterface.execute(con, "SELECT id, m FROM e_shift")]
println("    rows in table   : ", repr(got4))
expected_drop = [(Int32(1), "sad"), (Int32(3), "ok"), (Int32(4), "happy")]
println("    >> ", got4 == expected_drop ? "clean drop of the bad row — no shifting" :
                   isempty(got4) ? "ENTIRE BATCH LOST" :
                   "MISALIGNED — values shifted across rows/columns")

println("\ndone.")

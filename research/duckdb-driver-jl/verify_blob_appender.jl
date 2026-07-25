# verify_blob_appender.jl
#
# QUESTION (open behavior 1 of 4): the capability spike
# (.claude-work/notes/20260723-1530 §2) measured appender × blob = ERR, but the
# driver study (.claude-work/notes/20260725-1007 §3a) found `duckdb_append_blob`
# wired up at appender.jl:94. those two claims disagree, and they imply very
# different codegen:
#   - "the path does not exist"  -> blob columns must use another writer tier
#   - "the path exists but is broken" -> it is a driver bug we can pin down,
#     work around, and file upstream
#
# this script isolates the blob append with no other columns or types in play,
# then walks *down* the stack (julia dispatch -> julia wrapper -> raw C API) to
# find the exact layer that fails.
#
# run: julia --project=. verify_blob_appender.jl

using DuckDB

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# every verdict line is prefixed so findings.md can quote it verbatim
say(label, verdict) = println("  ", rpad(label, 44), " : ", verdict)
section(title) = println("\n== ", title)

# in this script errors are DATA, not failures — we are characterising them.
# `sprint(showerror, e)` renders the exception the way the REPL would, without
# the stacktrace noise
function attempt(f)
  try
    return (ok = true, value = f(), err = nothing)
  catch e
    return (ok = false, value = nothing, err = sprint(showerror, e))
  end
end

# the driver drops every appender return code (study §3a / gotcha 2), so we go
# get the error message ourselves. we declare this ccall with our OWN argument
# types rather than calling `DuckDB.duckdb_appender_error`, because that wrapper
# returns a `Cstring` and (appender.jl:46) is itself suspect — it passes the
# Ref box instead of the handle. Ptr{UInt8} keeps the null check unambiguous.
function appender_error(handle)
  p = ccall((:duckdb_appender_error, DuckDB.libduckdb), Ptr{UInt8}, (Ptr{Cvoid},), handle)
  return p == C_NULL ? nothing : unsafe_string(p)
end

con = DBInterface.connect(DuckDB.DB)

# nastiest realistic payload: embedded NUL (0x00) would truncate anything that
# treats blobs as C strings, and 0x27 is an ASCII single quote, which would
# break a naive literal-SQL serializer
payload = UInt8[0xaa, 0x00, 0x27, 0xff]

println("DuckDB.jl blob-appender verification")
println("driver source: ", dirname(pathof(DuckDB)))

# ---------------------------------------------------------------------------
# probe 1: which julia method actually handles Vector{UInt8}?
# ---------------------------------------------------------------------------
# appender.jl has BOTH `append(::Appender, ::Vector{UInt8})` (line 94, the blob
# path) and `append(::Appender, ::AbstractVector{T})` (line 106, the LIST path).
# julia picks the most specific applicable method, and Vector{UInt8} is strictly
# more specific than AbstractVector{T} — but "should" is not "does", so measure.
# `which` reports the method plus its defining file:line, which is exactly the
# citation impl.md asks for.
section("probe 1: julia method dispatch for Vector{UInt8}")
m = which(DuckDB.append, Tuple{DuckDB.Appender, Vector{UInt8}})
say("dispatched method", string(m))
say("blob path (appender.jl:94) selected?",
    occursin("appender.jl:94", string(m)) ? "YES" : "NO — fell through to another method")

# ---------------------------------------------------------------------------
# probe 2: the append itself, exactly as generated code would do it
# ---------------------------------------------------------------------------
section("probe 2: DuckDB.append(appender, ::Vector{UInt8}) into a BLOB column")
DBInterface.execute(con, "CREATE OR REPLACE TABLE t_blob (c BLOB)")
ap = DuckDB.Appender(con, "t_blob")

r_append = attempt(() -> DuckDB.append(ap, payload))
say("append() threw?", r_append.ok ? "no" : "YES")
if !r_append.ok
  say("  error", r_append.err)
end

# only continue the row if the append survived — end_row on a poisoned appender
# would confuse the diagnosis
if r_append.ok
  r_row = attempt(() -> DuckDB.end_row(ap))
  say("end_row() threw?", r_row.ok ? "no" : "YES: " * something(r_row.err, ""))
  r_flush = attempt(() -> DuckDB.flush(ap))
  say("flush() threw?", r_flush.ok ? "no" : "YES: " * something(r_flush.err, ""))
end

# the C-level message the julia wrapper discarded — this is the *real* verdict
# when the julia layer stayed silent
say("duckdb_appender_error()", something(appender_error(ap.handle), "(none)"))
attempt(() -> DuckDB.close(ap))

# row count + byte-level round trip. note BLOB reads back as
# Base.CodeUnits{UInt8,String} (study §2), so compare bytes via collect
n = only(only(DBInterface.execute(con, "SELECT count(*) AS n FROM t_blob")))
say("rows landed in table", string(n))
if n == 1
  got = only(only(DBInterface.execute(con, "SELECT c FROM t_blob")))
  say("read-back julia type", string(typeof(got)))
  say("bytes round-trip exactly?", collect(got) == payload ? "YES" : "NO — got " * string(collect(got)))
end

# ---------------------------------------------------------------------------
# probe 3: is the failure in the julia WRAPPER or in the C API?
# ---------------------------------------------------------------------------
# api.jl:7257-7266 declares duckdb_append_blob's data argument as `Ref{Cvoid}`.
# a blob is a *pointer to bytes*, i.e. `void*`, which in julia's ccall ABI is
# `Ptr{Cvoid}` — `Ref{Cvoid}` means "pointer to a Cvoid-typed slot" and does not
# accept an arbitrary byte array. so we re-declare the same C entry point with
# the argument type the C header implies and call it directly. if THIS works
# while probe 2 failed, the bug is localised to one word in api.jl:7261.
section("probe 3: raw C API with Ptr{Cvoid} (bypassing the api.jl wrapper)")
DBInterface.execute(con, "CREATE OR REPLACE TABLE t_blob_raw (c BLOB)")
ap2 = DuckDB.Appender(con, "t_blob_raw")

# GC.@preserve pins `payload` for the duration of the call. julia would normally
# keep it alive here anyway, but once you hand a raw pointer to C the compiler
# is no longer tracking the reference for you — this is the idiom that makes the
# lifetime explicit rather than accidental
r_raw = attempt(() -> GC.@preserve payload begin
  ccall((:duckdb_append_blob, DuckDB.libduckdb),
        Cint,                                   # duckdb_state (ctypes.jl:52)
        (Ptr{Cvoid}, Ptr{Cvoid}, UInt64),       # appender, data, length
        ap2.handle, pointer(payload), sizeof(payload))
end)
if r_raw.ok
  # 0 == DuckDBSuccess (ctypes.jl:53)
  say("raw duckdb_append_blob state", r_raw.value == 0 ? "DuckDBSuccess (0)" : "DuckDBError ($(r_raw.value))")
else
  say("raw duckdb_append_blob threw", r_raw.err)
end
attempt(() -> DuckDB.end_row(ap2))
attempt(() -> DuckDB.flush(ap2))
say("duckdb_appender_error()", something(appender_error(ap2.handle), "(none)"))
attempt(() -> DuckDB.close(ap2))

n_raw = only(only(DBInterface.execute(con, "SELECT count(*) AS n FROM t_blob_raw")))
say("rows landed via raw ccall", string(n_raw))
if n_raw == 1
  got_raw = only(only(DBInterface.execute(con, "SELECT c FROM t_blob_raw")))
  say("bytes round-trip exactly?", collect(got_raw) == payload ? "YES" : "NO — got " * string(collect(got_raw)))
end

# ---------------------------------------------------------------------------
# probe 4: workaround candidates for the generated writer
# ---------------------------------------------------------------------------
# if the appender path is unusable, codegen needs a blob tier that works. two
# candidates that cost nothing to measure here.
section("probe 4: workarounds for blob writes")

# 4a. append a String into the BLOB column and let the C appender cast it — the
# same trick the driver itself uses for UUID and FixedDecimal (appender.jl:93,95).
#
# TWO payloads on purpose. a julia String may legally contain a NUL byte, but
# `duckdb_append_varchar` takes a Cstring, and julia refuses to build a Cstring
# from NUL-bearing data. so running only the NUL payload would confound two
# different failures: "the VARCHAR->BLOB cast is unsupported" and "julia
# rejected the argument before duckdb ever saw it". the NUL-free control
# separates them.
# three payloads, peeling one confound at a time:
#   ASCII     — valid UTF-8, no NUL. the ONLY clean test of the VARCHAR->BLOB cast
#   non-UTF8  — no NUL, but not valid UTF-8: does duckdb accept arbitrary bytes?
#   with NUL  — the realistic binary case julia's Cstring conversion must handle
for (tag, bytes) in (("ASCII", UInt8[0x68, 0x69, 0x27]),
                     ("non-UTF8", UInt8[0xaa, 0x27, 0xff]),
                     ("with NUL", payload))
  tbl = "t_blob_str_" * replace(tag, "-" => "_", " " => "_")
  DBInterface.execute(con, "CREATE OR REPLACE TABLE $tbl (c BLOB)")
  ap3 = DuckDB.Appender(con, tbl)

  # check the C error slot after EVERY step, not just at the end.
  # duckdb_appender_error returns the LATEST error, so a later failure
  # overwrites an earlier one — checking only once at the end attributes the
  # wrong cause. this stepwise pattern is also the workaround a generated
  # writer would use to defeat gotcha 2 (silent appender errors)
  function step!(name, f)
    r = attempt(f)
    e = appender_error(ap3.handle)
    say("    after $name", (r.ok ? "no throw" : "THREW: " * something(r.err, "")) *
                           (e === nothing ? "" : "  |  C error: " * e))
    return r.ok
  end

  say("4a. append(::String) into BLOB [$tag]", "")
  if step!("append ", () -> DuckDB.append(ap3, String(copy(bytes))))  # copy: String() takes ownership
    step!("end_row", () -> DuckDB.end_row(ap3))
    step!("flush  ", () -> DuckDB.flush(ap3))
  end
  attempt(() -> DuckDB.close(ap3))

  n_str = only(only(DBInterface.execute(con, "SELECT count(*) AS n FROM $tbl")))
  say("    rows landed", string(n_str))
  if n_str == 1
    got_str = only(only(DBInterface.execute(con, "SELECT c FROM $tbl")))
    say("    bytes round-trip exactly?", collect(got_str) == bytes ? "YES" : "NO — got " * string(collect(got_str)))
  end
end

# 4b. prepared-statement bind — statement.jl:66 wires Vector{UInt8} to
# duckdb_bind_blob. the spike measured this as ok; re-confirm in isolation so
# the reference doc can recommend it as the blob fallback with a live citation
DBInterface.execute(con, "CREATE OR REPLACE TABLE t_blob_bind (c BLOB)")
r_bind = attempt(() -> begin
  stmt = DBInterface.prepare(con, "INSERT INTO t_blob_bind VALUES (?)")
  DBInterface.execute(stmt, (payload,))
end)
say("4b. prepared bind of Vector{UInt8} threw?", r_bind.ok ? "no" : "YES: " * something(r_bind.err, ""))
n_bind = only(only(DBInterface.execute(con, "SELECT count(*) AS n FROM t_blob_bind")))
say("    rows landed", string(n_bind))
if n_bind == 1
  got_bind = only(only(DBInterface.execute(con, "SELECT c FROM t_blob_bind")))
  say("    bytes round-trip exactly?", collect(got_bind) == payload ? "YES" : "NO — got " * string(collect(got_bind)))
end

println("\ndone.")

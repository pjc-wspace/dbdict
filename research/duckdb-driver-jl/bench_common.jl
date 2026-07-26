# bench_common.jl
#
# shared material for bench_write.jl and bench_read.jl:
#   - the SQL literal serializer a generated writer would emit (lifted from the
#     spike's literal_matrix.jl, which round-trip-verified it over 27 type cells)
#   - four type profiles x three scales of deterministic test data
#   - the applicability matrix: which write path can carry which profile, and
#     the measured reason for every skip
#
# included (not imported) by the bench scripts: `include("bench_common.jl")`.
# a plain include keeps every name visible without module qualification, which
# is the simpler thing to read when the point of the file is shared helpers.

using Dates
using Tables
using FixedPointDecimals
using Printf
using Random
using UUIDs

# ---------------------------------------------------------------------------
# the literal serializer (spike edition — see notes/20260723-1530 §2b)
# ---------------------------------------------------------------------------
# NOTE this dispatches on the *julia* value type. a real dbdict generator must
# be directed by the column's DuckType instead, because e.g. Vector{UInt8}
# (blob) and a UTINYINT[] column are indistinguishable here. good enough for a
# benchmark, where the shape of the work — not the dispatch — is what we time.

sqllit(::Missing) = "NULL"
sqllit(v::Bool) = v ? "TRUE" : "FALSE"
sqllit(v::Integer) = string(v)
function sqllit(v::AbstractFloat)
  isnan(v) && return "'nan'::DOUBLE"
  v == Inf && return "'infinity'::DOUBLE"
  v == -Inf && return "'-infinity'::DOUBLE"
  # MUST use exponent notation. duckdb parses a bare decimal literal like
  # `0.11914626526441173` as DECIMAL, not DOUBLE, and 17 fractional digits
  # cannot uniquely identify a Float64 — so the value arrives 1 ULP light.
  # appending ::DOUBLE does NOT help, because the DECIMAL parse happens first.
  # `%.17e` forces the DOUBLE parser directly; verified exact over 2005 values
  # incl. 0.0, -0.0, 1e308, 5e-324, 1/3. (caught by the content gate at
  # flat/1M/literal — see findings.md §6)
  return @sprintf("%.17e", v)
end
sqllit(v::FixedDecimal) = string(v)
sqllit(v::AbstractString) = "'" * replace(v, "'" => "''") * "'"
sqllit(v::Date) = "DATE '" * Dates.format(v, "yyyy-mm-dd") * "'"
sqllit(v::Time) = "TIME '" * Dates.format(v, "HH:MM:SS.sss") * "'"
sqllit(v::DateTime) = "TIMESTAMP '" * Dates.format(v, "yyyy-mm-dd HH:MM:SS.sss") * "'"
sqllit(v::Base.UUID) = "'" * string(v) * "'::UUID"
sqllit(v::AbstractVector) = "[" * join((sqllit(x) for x in v), ", ") * "]"
sqllit(v::NamedTuple) =
  "{" * join(("'" * String(k) * "': " * sqllit(getfield(v, k)) for k in keys(v)), ", ") * "}"

# ---------------------------------------------------------------------------
# deterministic data generation
# ---------------------------------------------------------------------------
# fixed seed so reruns compare like with like. (RNG streams are only stable
# within a julia version — the results header records the version so a future
# rerun on a different julia can be spotted rather than silently compared.)
const SEED = 20260726

# ~12-char ascii words, with an apostrophe in 1-in-20 so the literal path pays
# realistic escaping costs rather than a best case that never occurs in real data
function gen_strings(rng, n)
  alpha = collect('a':'z')
  out = Vector{String}(undef, n)
  for i in 1:n
    w = String(rand(rng, alpha, 12))
    out[i] = (i % 20 == 0) ? (w[1:5] * "'" * w[7:end]) : w
  end
  return out
end

# each profile: the real table's DDL, and a generator returning a NamedTuple of
# column vectors — the "natural julia" shape a caller would hand to codegen
const PROFILES = [
  (name = "flat",
   ddl = "id INTEGER, flag BOOLEAN, n BIGINT, x DOUBLE, s VARCHAR",
   gen = (rng, n) -> (id = Int32.(1:n),
                      flag = rand(rng, Bool, n),
                      n = rand(rng, Int64(0):Int64(10^9), n),
                      x = randn(rng, n),
                      s = gen_strings(rng, n))),

  (name = "rich",
   ddl = "id INTEGER, u UUID, d DECIMAL(18,4), s VARCHAR",
   gen = (rng, n) -> (id = Int32.(1:n),
                      # uuid4(rng) keeps the stream deterministic
                      u = [uuid4(rng) for _ in 1:n],
                      d = [FixedDecimal{Int64, 4}(round(rand(rng) * 10^4, digits = 4)) for _ in 1:n],
                      s = gen_strings(rng, n))),

  (name = "struct",
   ddl = "id INTEGER, loc STRUCT(x DOUBLE, y DOUBLE)",
   gen = (rng, n) -> (id = Int32.(1:n),
                      loc = [(x = randn(rng), y = randn(rng)) for _ in 1:n])),

  (name = "list",
   ddl = "id INTEGER, xs INTEGER[]",
   # 1..4 non-empty elements: appender.jl:108-111 turns an EMPTY vector into
   # NULL, and value.jl:52-56 rejects lists containing `missing`, so neither
   # can appear in data meant to exercise the list write path
   gen = (rng, n) -> (id = Int32.(1:n),
                      xs = [rand(rng, Int32(1):Int32(1000), rand(rng, 1:4)) for _ in 1:n])),
]

profile(name) = PROFILES[findfirst(p -> p.name == name, PROFILES)]

const SCALES = [10_000, 100_000, 1_000_000]

# generate once per (profile, scale) and reuse across paths and benchmark
# samples — data generation must never land inside a timed region
const _DATA_CACHE = Dict{Tuple{String, Int}, Any}()

function getdata(pname::AbstractString, n::Int)
  get!(_DATA_CACHE, (pname, n)) do
    p = profile(pname)
    p.gen(MersenneTwister(SEED), n)
  end
end

# 1M rows across four profiles held at once is a few hundred MB; run_all drops
# each scale before moving to the next
free_data!() = (empty!(_DATA_CACHE); GC.gc(); nothing)

# ---------------------------------------------------------------------------
# the applicability matrix
# ---------------------------------------------------------------------------
# every skip carries the measurement or source line that justifies it, so
# results.md can state WHY a cell is empty instead of leaving a blank.
#
# paths:
#   appender      — per-cell DuckDB.append + end_row (appender.jl:77-124)
#   register      — register_table + INSERT INTO ... SELECT (table_scan.jl:200)
#   register_flat — leaf fields registered flat, struct rebuilt in SQL
#                   (spike path E; verified end to end in findings.md §4d)
#   literal       — batched INSERT INTO ... VALUES of generated SQL literals

const WRITE_PATHS = ["appender", "register", "register_flat", "literal"]

# returns nothing when applicable, or a reason string when it must be skipped
function skip_reason(pname::AbstractString, path::AbstractString)
  if path == "appender"
    pname == "struct" && return "no NamedTuple method — appender.jl:116-119 throws NotImplementedException"
    # NOT a capability limit: this path WORKS and then segfaults the process at
    # ~1M list appends (verify_list_appender_gc.jl, findings.md §5). it cannot
    # be benchmarked, and codegen must not emit it
    pname == "list" && return "SEGFAULTS at ~1M appends — see verify_list_appender_gc.jl / findings.md §5"
    return nothing
  elseif path == "register"
    pname == "rich" && return "UUID column rejected by create_logical_type — logical_type.jl:64-66 (findings.md §4)"
    pname == "struct" && return "NamedTuple column rejected by create_logical_type — logical_type.jl:64-66 (findings.md §4)"
    pname == "list" && return "Vector column rejected by create_logical_type — logical_type.jl:64-66 (findings.md §4)"
    return nothing
  elseif path == "register_flat"
    # only meaningful where a struct must be decomposed; for flat profiles it
    # would be identical to `register`, so measuring it twice would be noise
    pname == "struct" || return "not applicable — profile has no struct column to decompose"
    return nothing
  elseif path == "literal"
    return nothing
  end
  return "unknown path"
end

# ---------------------------------------------------------------------------
# the three write paths, as functions
# ---------------------------------------------------------------------------

recreate_table!(con, table, ddl) =
  DBInterface.execute(con, "CREATE OR REPLACE TABLE $table ($ddl)")

# path A: appender. one append per cell, end_row per row, flush+close at the
# end — and per findings.md §3 the appender must be closed inside whatever
# transaction scope the caller established, so we close it here, always
function write_appender!(con, table, cols)
  n = length(first(cols))
  ap = DuckDB.Appender(con, table)
  try
    for i in 1:n
      for c in cols
        DuckDB.append(ap, c[i])
      end
      DuckDB.end_row(ap)
    end
    DuckDB.flush(ap)
  finally
    DuckDB.close(ap)
  end
  return n
end

# path B: register the julia columns as a view, then let duckdb scan it.
# registration is alias-based (findings.md §4c) but the scan copies per query
function write_register!(con, table, cols, view)
  DuckDB.register_table(con, cols, view)
  try
    DBInterface.execute(con, "INSERT INTO $table SELECT * FROM \"$view\"")
  finally
    DuckDB.unregister_table(con, view)
  end
  return length(first(cols))
end

# path B': struct columns decomposed to leaves, reassembled in SQL. the
# StructArray-shaped input a codegen caller would have
function write_register_flat!(con, table, cols, view)
  flat = (id = cols.id,
          loc_x = [p.x for p in cols.loc],
          loc_y = [p.y for p in cols.loc])
  DuckDB.register_table(con, flat, view)
  try
    DBInterface.execute(con,
      "INSERT INTO $table SELECT id, {'x': loc_x, 'y': loc_y} FROM \"$view\"")
  finally
    DuckDB.unregister_table(con, view)
  end
  return length(first(cols))
end

# path C: generated SQL literals, batched. one statement per BATCH rows —
# a single 1M-row VALUES list would be a pathological statement, and batching
# is what a real generator would emit anyway
const LITERAL_BATCH = 1000

function write_literal!(con, table, cols, batch = LITERAL_BATCH)
  n = length(first(cols))
  ncol = length(cols)
  buf = IOBuffer()
  for lo in 1:batch:n
    hi = min(lo + batch - 1, n)
    truncate(buf, 0)
    seekstart(buf)
    print(buf, "INSERT INTO ", table, " VALUES ")
    for i in lo:hi
      i > lo && print(buf, ",")
      print(buf, "(")
      for (j, c) in enumerate(cols)
        j > 1 && print(buf, ",")
        print(buf, sqllit(c[i]))
      end
      print(buf, ")")
    end
    DBInterface.execute(con, String(take!(buf)))
  end
  return n
end

# ---------------------------------------------------------------------------
# correctness gate
# ---------------------------------------------------------------------------
# a row-count check is NOT sufficient: findings.md §2b showed a failed appender
# cell can misalign columns across rows while leaving a plausible count. so the
# harness verifies CONTENT once per (profile, path) before any timing runs —
# a benchmark of a path that silently writes wrong data is worse than no number.

loose_eq(a, b) = isequal(a, b)
loose_eq(a::NamedTuple, b::NamedTuple) =
  keys(a) == keys(b) && all(loose_eq(getfield(a, k), getfield(b, k)) for k in keys(a))
loose_eq(a::AbstractVector, b::AbstractVector) =
  length(a) == length(b) && all(loose_eq(x, y) for (x, y) in zip(a, b))

# returns nothing when the table matches the source columns, else a reason.
# spot-checks head/middle/tail rather than all n — enough to catch the
# off-by-one shifting failure mode without making the gate itself a benchmark
function check_written(con, table, cols)
  n = length(first(cols))
  got = Tables.columntable(DBInterface.execute(con, "SELECT * FROM $table ORDER BY id"))
  ngot = length(first(got))
  ngot == n || return "row count $ngot != $n"
  for k in keys(cols)
    for i in unique([1, max(1, n ÷ 2), n])
      loose_eq(cols[k][i], got[k][i]) ||
        return "column :$k row $i — expected $(repr(cols[k][i])), got $(repr(got[k][i]))"
    end
  end
  return nothing
end

# dispatch a write by path name; `view` is only used by the register paths
function run_write!(con, path, table, cols, view)
  if path == "appender"
    return write_appender!(con, table, cols)
  elseif path == "register"
    return write_register!(con, table, cols, view)
  elseif path == "register_flat"
    return write_register_flat!(con, table, cols, view)
  elseif path == "literal"
    return write_literal!(con, table, cols)
  end
  error("unknown write path: $path")
end

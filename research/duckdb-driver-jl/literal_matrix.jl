# spike addendum (review finding 3): the literal write path, measured
# properly this time.
#
#   part 1: type-directed sql literal serializer over the full read-table
#           type matrix, each type x {value, missing}, plus NaN/Inf.
#           round-trip verified per cell.
#   part 2: timestamptz policy (a) — julia DateTime is UTC by contract;
#           literals carry an explicit +00 offset so the session timezone
#           (here Pacific/Auckland, +12 — a good tripwire) cannot change
#           the stored instant. also probes what the *binding* paths do
#           with a naive DateTime, where a 12h skew exposes local-time
#           interpretation.
#
# run: julia --project=<spike dir> literal_matrix.jl

using DuckDB
using DataFrames
using Dates
using UUIDs
using FixedPointDecimals

con = DBInterface.connect(DuckDB.DB)
DBInterface.execute(con, "CREATE TYPE mood AS ENUM ('sad', 'ok', 'happy')")

# --- the serializer a generated writer would emit (spike edition) ---

sqllit(::Missing) = "NULL"
sqllit(v::Bool) = v ? "TRUE" : "FALSE"
sqllit(v::Integer) = string(v)
function sqllit(v::AbstractFloat)
    isnan(v) && return "'nan'::DOUBLE"
    v == Inf && return "'infinity'::DOUBLE"
    v == -Inf && return "'-infinity'::DOUBLE"
    return string(v)
end
sqllit(v::FixedDecimal) = string(v)
sqllit(v::AbstractString) = "'" * replace(v, "'" => "''") * "'"
sqllit(v::Date) = "DATE '" * Dates.format(v, "yyyy-mm-dd") * "'"
sqllit(v::Time) = "TIME '" * Dates.format(v, "HH:MM:SS.sss") * "'"
sqllit(v::DateTime) =
    "TIMESTAMP '" * Dates.format(v, "yyyy-mm-dd HH:MM:SS.sss") * "'"
sqllit(v::Base.UUID) = "'" * string(v) * "'::UUID"
# note: blob spelling claims AbstractVector{UInt8}; a real generator is
# type-directed by the column's DuckType, so a UTINYINT[] column cannot
# collide with this the way bare dispatch could
sqllit(v::AbstractVector{UInt8}) =
    "'" * join(("\\x" * uppercase(string(b, base = 16, pad = 2)) for b in v)) *
    "'::BLOB"
sqllit(v::Base.CodeUnits) = sqllit(collect(v))
sqllit(v::AbstractVector) = "[" * join((sqllit(x) for x in v), ", ") * "]"
sqllit(v::NamedTuple) =
    "{" *
    join(("'" * String(k) * "': " * sqllit(getfield(v, k)) for k in keys(v)),
         ", ") * "}"
sqllit(v::AbstractDict) =
    "MAP([" * join((sqllit(k) for k in keys(v)), ", ") * "], [" *
    join((sqllit(x) for x in values(v)), ", ") * "])"

# policy (a): timestamptz/timetz literals always carry an explicit +00,
# making the julia value's UTC meaning independent of session timezone
tstzlit(v::DateTime) =
    "TIMESTAMPTZ '" * Dates.format(v, "yyyy-mm-dd HH:MM:SS.sss") * "+00'"
timetzlit(v::Time) = "TIMETZ '" * Dates.format(v, "HH:MM:SS.sss") * "+00'"

# --- part 1: full matrix x {value, missing} ---

cases = [
    ("bool",     "BOOLEAN",        true,                          sqllit),
    ("tinyint",  "TINYINT",        Int8(7),                       sqllit),
    ("smallint", "SMALLINT",       Int16(7),                      sqllit),
    ("int",      "INTEGER",        Int32(42),                     sqllit),
    ("bigint",   "BIGINT",         Int64(420),                    sqllit),
    ("hugeint",  "HUGEINT",        Int128(2)^100,                 sqllit),
    ("utinyint", "UTINYINT",       UInt8(7),                      sqllit),
    ("ubigint",  "UBIGINT",        UInt64(420),                   sqllit),
    ("float",    "FLOAT",          Float32(1.5),                  sqllit),
    ("double",   "DOUBLE",         1.5,                           sqllit),
    ("dbl_nan",  "DOUBLE",         NaN,                           sqllit),
    ("dbl_inf",  "DOUBLE",         Inf,                           sqllit),
    ("dbl_ninf", "DOUBLE",         -Inf,                          sqllit),
    ("decimal",  "DECIMAL(18, 4)", FixedDecimal{Int64, 4}(12.3456), sqllit),
    ("varchar",  "VARCHAR",        "o'brien\n\ttab",              sqllit),
    ("blob",     "BLOB",           UInt8[0xaa, 0x00, 0x27],       sqllit),
    ("date",     "DATE",           Date(2026, 7, 23),             sqllit),
    ("time",     "TIME",           Time(11, 22, 33, 123),         sqllit),
    ("ts",       "TIMESTAMP",      DateTime(2026, 7, 23, 11, 22, 33, 123), sqllit),
    ("tstz",     "TIMESTAMPTZ",    DateTime(2026, 7, 23, 11, 22, 33), tstzlit),
    ("timetz",   "TIMETZ",         Time(11, 22, 33),              timetzlit),
    ("uuid",     "UUID",           uuid4(),                       sqllit),
    ("enum",     "mood",           "happy",                       sqllit),
    ("list",     "INTEGER[]",      Union{Missing, Int32}[1, missing, 3], sqllit),
    ("struct",   "STRUCT(street VARCHAR, num INTEGER)",
                 (street = "o'brien rd", num = Int32(7)),          sqllit),
    ("map",      "MAP(VARCHAR, INTEGER)", Dict("a" => Int32(1)),   sqllit),
    ("nested",   "STRUCT(tags VARCHAR[], loc STRUCT(x DOUBLE, y DOUBLE))",
                 (tags = ["x", "y"], loc = (x = 1.0, y = 2.0)),    sqllit),
]

failures = String[]
for (label, sqltype, value, lit) in cases
    t = "m_" * label
    DBInterface.execute(con, "CREATE TABLE " * t * " (c " * sqltype * ")")
    status = try
        # row 1: the value; row 2: NULL via the same serializer
        DBInterface.execute(con,
            "INSERT INTO " * t * " VALUES (" * lit(value) * "), (" *
            sqllit(missing) * ")")
        df = DataFrame(DBInterface.execute(con, "SELECT c FROM " * t))
        got, gotnull = df[1, :c], df[2, :c]
        if !ismissing(gotnull)
            "NULL FAIL: got " * repr(gotnull)
        elseif isequal(got, value)
            "ok"
        else
            "VALUE FAIL: got " * repr(got)
        end
    catch e
        "ERR: " * first(replace(sprint(showerror, e), "\n" => " "), 70)
    end
    status == "ok" || push!(failures, label * ": " * status)
    println(rpad(label, 10), status)
end

# --- part 2: what do the binding paths do with a naive DateTime in a
# TIMESTAMPTZ column? (session tz here is +12; skew exposes local
# interpretation) ---

println("\ntimestamptz via binding paths (session tz = local, +12):")
written = DateTime(2026, 7, 23, 11, 22, 33)

DBInterface.execute(con, "CREATE TABLE z_app (c TIMESTAMPTZ)")
r = try
    ap = DuckDB.Appender(con, "z_app")
    DuckDB.append(ap, written)
    DuckDB.end_row(ap)
    DuckDB.close(ap)
    got = DataFrame(DBInterface.execute(con, "SELECT c FROM z_app"))[1, :c]
    "wrote " * repr(written) * " read " * repr(got) *
        (got == written ? "  (treated as UTC)" : "  (SKEWED: local interp)")
catch e
    "ERR: " * first(sprint(showerror, e), 60)
end
println("  appender:    ", r)

DBInterface.execute(con, "CREATE TABLE z_reg (c TIMESTAMPTZ)")
r = try
    DuckDB.register_data_frame(con, DataFrame(c = [written]), "v_z")
    DBInterface.execute(con, "INSERT INTO z_reg SELECT c FROM v_z")
    got = DataFrame(DBInterface.execute(con, "SELECT c FROM z_reg"))[1, :c]
    "wrote " * repr(written) * " read " * repr(got) *
        (got == written ? "  (treated as UTC)" : "  (SKEWED: local interp)")
catch e
    "ERR: " * first(sprint(showerror, e), 60)
end
println("  register_df: ", r)

println("\n", isempty(failures) ? "ALL CELLS OK" :
    string(length(failures), " FAILURES:\n  ", join(failures, "\n  ")))

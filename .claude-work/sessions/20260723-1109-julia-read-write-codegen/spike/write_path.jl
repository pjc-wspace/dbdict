# spike question 2: which write paths handle which duckdb types?
#
# three candidate paths for the generated writer:
#   A: appender api            (fastest per docs)
#   B: register_data_frame     + INSERT INTO ... SELECT
#   C: prepared INSERT         with ? parameters
#
# each (type, path) combination gets its own single-column table so one
# failure cannot mask another. errors are data here, not problems.
#
# run: julia --project=<spike dir> write_path.jl

using DuckDB
using DataFrames
using Dates
using UUIDs
using FixedPointDecimals

con = DBInterface.connect(DuckDB.DB)
DBInterface.execute(con, "CREATE TYPE mood AS ENUM ('sad', 'ok', 'happy')")

# (label, duckdb column type, julia value in driver-native form)
cases = [
    ("bool",    "BOOLEAN",        true),
    ("int",     "INTEGER",        Int32(42)),
    ("bigint",  "BIGINT",         Int64(420)),
    ("hugeint", "HUGEINT",        Int128(4200)),
    ("double",  "DOUBLE",         1.5),
    ("decimal", "DECIMAL(18, 4)", FixedDecimal{Int64, 4}(12.3456)),
    ("varchar", "VARCHAR",        "hi"),
    ("blob",    "BLOB",           UInt8[0xaa, 0xbb]),
    ("date",    "DATE",           Date(2026, 7, 23)),
    ("time",    "TIME",           Time(11, 22, 33)),
    ("ts",      "TIMESTAMP",      DateTime(2026, 7, 23, 11, 22, 33)),
    ("uuid",    "UUID",           uuid4()),
    ("enum",    "mood",           "happy"),
    ("list",    "INTEGER[]",      Int32[1, 2, 3]),
    ("array",   "INTEGER[3]",     Int32[1, 2, 3]),
    ("struct",  "STRUCT(street VARCHAR, num INTEGER)",
                (street = "main st", num = Int32(7))),
    ("map",     "MAP(VARCHAR, INTEGER)", Dict("a" => Int32(1))),
    ("nested",  "STRUCT(tags VARCHAR[], loc STRUCT(x DOUBLE, y DOUBLE))",
                (tags = ["x", "y"], loc = (x = 1.0, y = 2.0))),
]

# truncate an error to a one-line cell for the report matrix
shorterr(e) = first(replace(sprint(showerror, e), "\n" => " "), 60)

# read the single value back so "wrote without error" also means
# "round-trips" — a silent corruption counts as failure
function check_roundtrip(table, expected)
    df = DataFrame(DBInterface.execute(con, "SELECT c FROM $table"))
    nrow(df) == 1 || return "FAIL (rows=$(nrow(df)))"
    got = df[1, :c]
    # values may come back as a different-but-equal representation
    # (e.g. enum as String); isequal is the honest comparison
    return isequal(got, expected) ? "ok" : "ok? got $(repr(got))"
end

results = Dict{Tuple{String, String}, String}()

for (label, sqltype, value) in cases
    # path A: appender
    ta = "a_$label"
    DBInterface.execute(con, "CREATE TABLE $ta (c $sqltype)")
    results[(label, "appender")] = try
        appender = DuckDB.Appender(con, ta)
        DuckDB.append(appender, value)
        DuckDB.end_row(appender)
        DuckDB.close(appender)
        check_roundtrip(ta, value)
    catch e
        "ERR: " * shorterr(e)
    end

    # path B: register a one-column DataFrame, INSERT ... SELECT from it
    tb = "b_$label"
    DBInterface.execute(con, "CREATE TABLE $tb (c $sqltype)")
    results[(label, "register_df")] = try
        df = DataFrame(c = [value])
        view_name = "v_$label"
        DuckDB.register_data_frame(con, df, view_name)
        DBInterface.execute(con, "INSERT INTO $tb SELECT c FROM $view_name")
        check_roundtrip(tb, value)
    catch e
        "ERR: " * shorterr(e)
    end

    # path C: prepared INSERT with a parameter
    tc = "c_$label"
    DBInterface.execute(con, "CREATE TABLE $tc (c $sqltype)")
    results[(label, "prepared")] = try
        stmt = DBInterface.prepare(con, "INSERT INTO $tc VALUES (?)")
        DBInterface.execute(stmt, (value,))
        check_roundtrip(tc, value)
    catch e
        "ERR: " * shorterr(e)
    end
end

println(rpad("type", 9), rpad("appender", 24), rpad("register_df", 24),
        "prepared")
println("-"^100)
for (label, _, _) in cases
    println(rpad(label, 9),
            rpad(results[(label, "appender")], 24),
            rpad(results[(label, "register_df")], 24),
            results[(label, "prepared")])
end

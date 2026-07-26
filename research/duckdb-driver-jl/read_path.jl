# spike question 1: what julia type does DuckDB.jl hand back for each
# duckdb type when a query result is materialized into a DataFrame?
#
# run: julia --project=<spike dir> read_path.jl

using DuckDB
using DataFrames

con = DBInterface.connect(DuckDB.DB)  # in-memory database

# an enum type must exist before a column can use it
DBInterface.execute(con, "CREATE TYPE mood AS ENUM ('sad', 'ok', 'happy')")

# one column per duckdb type we care about, matching the dict's rich-path
# coverage: primitives, decimal, temporal, uuid, blob, enum, and the
# nested types (list, fixed-size array, struct, map, struct-in-struct)
DBInterface.execute(con, """
    CREATE TABLE t (
        c_bool     BOOLEAN,
        c_int      INTEGER,
        c_bigint   BIGINT,
        c_hugeint  HUGEINT,
        c_double   DOUBLE,
        c_decimal  DECIMAL(18, 4),
        c_varchar  VARCHAR,
        c_blob     BLOB,
        c_date     DATE,
        c_time     TIME,
        c_ts       TIMESTAMP,
        c_tstz     TIMESTAMPTZ,
        c_uuid     UUID,
        c_enum     mood,
        c_list     INTEGER[],
        c_struct   STRUCT(street VARCHAR, num INTEGER),
        c_map      MAP(VARCHAR, INTEGER),
        c_nested   STRUCT(tags VARCHAR[], loc STRUCT(x DOUBLE, y DOUBLE))
    )
""")

DBInterface.execute(con, """
    INSERT INTO t VALUES (
        true, 42, 420, 4200, 1.5, 12.3456, 'hi', '\\xAA'::BLOB,
        DATE '2026-07-23', TIME '11:22:33', TIMESTAMP '2026-07-23 11:22:33',
        TIMESTAMPTZ '2026-07-23 11:22:33+12', uuid(),
        'happy', [1, 2, 3],
        {'street': 'main st', 'num': 7},
        MAP(['a', 'b'], [1, 2]),
        {'tags': ['x', 'y'], 'loc': {'x': 1.0, 'y': 2.0}}
    )
""")

# also a row of NULLs to see how missing combines with each type
DBInterface.execute(con, """
    INSERT INTO t VALUES (
        NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
        NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
    )
""")

df = DataFrame(DBInterface.execute(con, "SELECT * FROM t"))

println("column        eltype")
println("-"^72)
for name in names(df)
    println(rpad(name, 12), "  ", eltype(df[!, name]))
end

println()
println("row 1 values:")
for name in names(df)
    v = df[1, name]
    println(rpad(name, 12), "  ", repr(v))
end

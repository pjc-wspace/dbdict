# spike questions 3 + 4:
#   3. path D — writing nested values as generated SQL literals: the
#      fallback when no binding path supports STRUCT/MAP. read_path.jl
#      already inserted literals by hand; here we build them from julia
#      values, which is what a generated writer would do
#   4. StructArrays — does a STRUCT column read back as NamedTuples
#      convert cleanly to a StructArray, and does it behave as a
#      DataFrame column?
#
# run: julia --project=<spike dir> literal_and_structarrays.jl

using DuckDB
using DataFrames
using StructArrays

con = DBInterface.connect(DuckDB.DB)

# --- question 3: sql literal construction from julia values ---

# minimal literal builder for the value shapes the writer must handle.
# a real generator would emit a per-column version of this with proper
# escaping; the spike only needs to prove the shape works
sqllit(v::AbstractString) = "'" * replace(v, "'" => "''") * "'"
sqllit(v::Real) = string(v)
sqllit(v::AbstractVector) = "[" * join(sqllit.(v), ", ") * "]"
sqllit(v::NamedTuple) =
    "{" * join(["'$k': $(sqllit(getfield(v, k)))" for k in keys(v)], ", ") * "}"
sqllit(v::AbstractDict) =
    "MAP([" * join(sqllit.(collect(keys(v))), ", ") * "], [" *
    join(sqllit.(collect(values(v))), ", ") * "])"

DBInterface.execute(con, """
    CREATE TABLE lit (
        c_struct STRUCT(street VARCHAR, num INTEGER),
        c_map    MAP(VARCHAR, INTEGER),
        c_nested STRUCT(tags VARCHAR[], loc STRUCT(x DOUBLE, y DOUBLE))
    )
""")

vals = (
    (street = "o'brien rd", num = 7),          # embedded quote on purpose
    Dict("a" => 1, "b" => 2),
    (tags = ["x", "y"], loc = (x = 1.0, y = 2.0)),
)
sql = "INSERT INTO lit VALUES (" * join(sqllit.(collect(vals)), ", ") * ")"
println("generated: ", sql)
DBInterface.execute(con, sql)

df = DataFrame(DBInterface.execute(con, "SELECT * FROM lit"))
println("read back: ", NamedTuple(df[1, :]))
println("struct roundtrip: ", isequal(df[1, :c_struct], vals[1]) ? "OK" : "MISMATCH")
println("nested roundtrip: ", isequal(df[1, :c_nested], vals[3]) ? "OK" : "MISMATCH")

# --- question 4: structarrays over a struct column ---

DBInterface.execute(con,
    "CREATE TABLE pts (p STRUCT(x DOUBLE, y DOUBLE))")
DBInterface.execute(con,
    "INSERT INTO pts VALUES ({'x': 1.0, 'y': 2.0}), ({'x': 3.0, 'y': 4.0})")
pts = DataFrame(DBInterface.execute(con, "SELECT p FROM pts"))

col = pts[!, :p]
println("\ncolumn eltype: ", eltype(col))

# missing-tolerant conversion: StructArray wants concrete element types,
# duckdb hands back Union{Missing, NamedTuple}. skipmissing for the spike;
# the real generator must decide how nullable struct columns behave
sa = StructArray(collect(skipmissing(col)))
println("structarray: ", sa)
println("field access sa.x: ", sa.x)     # struct-of-arrays column access

# as a dataframe column
df2 = DataFrame(p = sa)
println("as df column: ", typeof(df2[!, :p]))
println("df2.p.y: ", df2[!, :p].y)

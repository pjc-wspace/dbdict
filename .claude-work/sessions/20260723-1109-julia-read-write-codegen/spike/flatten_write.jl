# spike question 6 (follow-up): write struct columns by registering the
# structarray's *field arrays* as flat columns, then reassembling the
# struct sql-side — avoiding literal serialization entirely.
#
#   julia memory (structarray):  x = [1.0, 3.0]   y = [2.0, 4.0]
#   register as view v:          v.x, v.y  (plain DOUBLE columns — bindable)
#   INSERT INTO pts SELECT {'x': x, 'y': y} FROM v
#
# run: julia --project=<spike dir> flatten_write.jl

using DuckDB
using DataFrames
using StructArrays

con = DBInterface.connect(DuckDB.DB)

# --- flat struct from a typed structarray ---
DBInterface.execute(con, "CREATE TABLE pts (p STRUCT(x DOUBLE, y DOUBLE))")

sa = StructArray(x = [1.0, 3.0], y = [2.0, 4.0])  # typed field arrays
DuckDB.register_data_frame(con, DataFrame(x = sa.x, y = sa.y), "v_pts")
DBInterface.execute(con, "INSERT INTO pts SELECT {'x': x, 'y': y} FROM v_pts")

back = DataFrame(DBInterface.execute(con, "SELECT p FROM pts"))
println("flat struct: ", back[!, :p])
println("roundtrip: ",
    isequal(collect(skipmissing(back[!, :p])),
            [(x = 1.0, y = 2.0), (x = 3.0, y = 4.0)]) ? "OK" : "MISMATCH")

# --- null struct rows: flattening loses "whole struct is NULL" unless a
# validity column comes along; CASE WHEN rebuilds it ---
DBInterface.execute(con, "CREATE TABLE pts2 (p STRUCT(x DOUBLE, y DOUBLE))")
DuckDB.register_data_frame(con,
    DataFrame(x = [1.0, 0.0], y = [2.0, 0.0], p_valid = [true, false]),
    "v_pts2")
DBInterface.execute(con, """
    INSERT INTO pts2
    SELECT CASE WHEN p_valid THEN {'x': x, 'y': y} ELSE NULL END FROM v_pts2
""")
back2 = DataFrame(DBInterface.execute(con, "SELECT p FROM pts2"))
println("null handling: ", back2[!, :p])

# --- nested struct-of-struct: recursive flattening (loc.x -> loc_x) ---
DBInterface.execute(con,
    "CREATE TABLE nest (s STRUCT(name VARCHAR, loc STRUCT(x DOUBLE, y DOUBLE)))")
DuckDB.register_data_frame(con,
    DataFrame(name = ["a", "b"], loc_x = [1.0, 3.0], loc_y = [2.0, 4.0]),
    "v_nest")
DBInterface.execute(con, """
    INSERT INTO nest
    SELECT {'name': name, 'loc': {'x': loc_x, 'y': loc_y}} FROM v_nest
""")
back3 = DataFrame(DBInterface.execute(con, "SELECT s FROM nest"))
println("nested: ", back3[!, :s])

# --- the known limit: a LIST-typed field array cannot be registered
# (spike §2: create_logical_type fails for vector columns) — confirm that
# still holds so the boundary of this technique is recorded ---
try
    DuckDB.register_data_frame(con,
        DataFrame(tags = [["x", "y"], ["z"]]), "v_lists")
    df = DataFrame(DBInterface.execute(con, "SELECT tags FROM v_lists"))
    println("list field register: unexpectedly OK: ", df[!, :tags])
catch e
    println("list field register: ERR (expected): ",
        first(sprint(showerror, e), 60))
end

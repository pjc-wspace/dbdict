# does duckdb allow CREATE TYPE with a builtin type name?
using DuckDB
con = DBInterface.connect(DuckDB.DB)
for name in ["decimal", "DECIMAL", "varchar", "int", "text", "mood"]
    r = try
        DBInterface.execute(con, "CREATE TYPE $name AS ENUM ('a', 'b')")
        "ACCEPTED"
    catch e
        "REJECTED: " * first(replace(sprint(showerror, e), "\n" => " "), 90)
    end
    println(rpad(name, 9), r)
end
# if any were accepted, can a column actually use the shadowed name?
r = try
    DBInterface.execute(con, "CREATE TABLE t (c mood)")
    "mood column OK"
catch e
    "mood column ERR"
end
println(r)

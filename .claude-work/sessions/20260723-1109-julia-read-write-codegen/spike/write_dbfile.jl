# spike question 5a: write a .duckdb file with julia's DuckDB (jll 1.5.2)
# so the rust side (bundled 1.5.4) can try to open it
using DuckDB

isfile("julia_written.duckdb") && rm("julia_written.duckdb")
con = DBInterface.connect(DuckDB.DB, "julia_written.duckdb")
DBInterface.execute(con,
    "CREATE TABLE t (a INTEGER, s STRUCT(x DOUBLE, y DOUBLE), e VARCHAR)")
DBInterface.execute(con,
    "INSERT INTO t VALUES (1, {'x': 1.0, 'y': 2.0}, 'hi')")
DBInterface.close(con)
println("written julia_written.duckdb")

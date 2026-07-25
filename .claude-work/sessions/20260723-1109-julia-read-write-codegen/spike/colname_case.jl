# column-name case behavior: match insensitively, preserve original case
using DuckDB, DataFrames
con = DBInterface.connect(DuckDB.DB)
DBInterface.execute(con, "CREATE TABLE t (TradePrice DOUBLE)")
DBInterface.execute(con, "INSERT INTO t VALUES (1.5)")
# query with a different spelling — and a quoted different spelling
df1 = DataFrame(DBInterface.execute(con, "SELECT tradeprice FROM t"))
df2 = DataFrame(DBInterface.execute(con, "SELECT \"TRADEPRICE\" FROM t"))
println("unquoted different case: ", names(df1))
println("quoted different case:   ", names(df2))
# select * returns the preserved original spelling
df3 = DataFrame(DBInterface.execute(con, "SELECT * FROM t"))
println("select *:                ", names(df3))

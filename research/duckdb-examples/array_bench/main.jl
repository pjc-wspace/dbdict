#!/usr/bin/env julia
#
# time reading a DOUBLE[] list column against an equivalent table with K flat
# columns, separating duckdb engine cost from the julia boundary cost
#
# LIST rather than ARRAY: DuckDB.jl 1.5.2 cannot resolve DUCKDB_TYPE_ARRAY and
# throws while constructing the QueryResult, before any data moves
#
# deps: DuckDB, DBInterface, DataFrames, Printf

using DuckDB, DBInterface, DataFrames, Printf

const N       = 2_000_000
const K       = 8
const REPS    = 3
const LIST_DB = "list.db"
const WIDE_DB = "wide.db"

flatcols() = join(("v$j" for j in 1:K), ", ")

function build(path::String, sql::String)
  # fixtures are expensive, reuse them across runs
  # delete the files by hand if N or K changes, this only checks existence
  isfile(path) && return
  @info "building $path"
  con = DBInterface.connect(DuckDB.DB, path)
  DBInterface.execute(con, sql)
  DBInterface.execute(con, "checkpoint")
  DBInterface.close!(con)
end

function build_fixtures()
  rands = join(("random()" for _ in 1:K), ", ")
  build(LIST_DB, """
    create table t as
    select i as id, cast([$rands] as double[]) as v
    from range($N) tbl(i)
  """)

  cols = join(("random() as v$j" for j in 1:K), ", ")
  build(WIDE_DB, """
    create table t as
    select i as id, $cols
    from range($N) tbl(i)
  """)
end

# min of REPS, reporting wall time and julia allocations
function bench(f::Function, label::String)
  f()  # warm: compilation and page cache
  best_t, best_b = Inf, 0
  for _ in 1:REPS
    r = @timed f()
    if r.time < best_t
      best_t, best_b = r.time, r.bytes
    end
  end
  @printf("  %-38s %8.1f ms  %9.1f MiB\n", label, best_t * 1000, best_b / 2^20)
  return best_t
end

# engine only: result is sunk into a temp table so nothing crosses into julia
# note this includes the cost of WRITING the sink table, so it is not a
# subtractable baseline for the crossing numbers below, only a same-shape
# comparison between the three query forms
sink(con, sql) = () -> DBInterface.execute(con, "create or replace temp table sink as " * sql)

# boundary: materialise the full result as a DataFrame
pull(con, sql) = () -> DataFrame(DBInterface.execute(con, sql))

function threads(con)
  first(first(DBInterface.execute(con, "select current_setting('threads')")))
end

function main()
  build_fixtures()

  lst  = DBInterface.connect(DuckDB.DB, LIST_DB)
  wide = DBInterface.connect(DuckDB.DB, WIDE_DB)
  fc   = flatcols()

  @printf("\nN = %d  K = %d  duckdb threads = %s\n", N, K, threads(lst))

  q_list       = "select id, v from t"
  q_wide       = "select id, $fc from t"
  q_wide_aslst = "select id, list_value($fc) as v from t"

  println("\nengine only (sink to temp table)")
  bench(sink(lst,  q_list),       "list:   select id, v")
  bench(sink(wide, q_wide),       "wide:   select id, v1..v$K")
  bench(sink(wide, q_wide_aslst), "wide:   list_value(v1..v$K)")

  println("\ncrossing into julia (DataFrame)")
  bench(pull(lst,  q_list),       "list:   select id, v")
  bench(pull(wide, q_wide),       "wide:   select id, v1..v$K")
  bench(pull(wide, q_wide_aslst), "wide:   list_value(v1..v$K)")

  # touch every value so the representation is actually consumed, not just held
  # this is the number that decides the layout: materialising happens once,
  # iterating happens repeatedly
  println("\nconsume all values in julia")
  df_list = DataFrame(DBInterface.execute(lst,  q_list))
  df_wide = DataFrame(DBInterface.execute(wide, q_wide))
  bench(() -> mapreduce(x -> sum(skipmissing(x)), +, df_list.v),
        "list:   sum over Vector{Vector}")
  bench(() -> sum(sum(df_wide[!, "v$j"]) for j in 1:K),
        "wide:   sum over K columns")

  println("\ncolumn eltypes")
  println("  list: ", eltype(df_list.v))
  println("  wide: ", eltype(df_wide.v1))

  DBInterface.close!(lst)
  DBInterface.close!(wide)
end

main()

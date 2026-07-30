#!/usr/bin/env julia
#
# time reading a DOUBLE[K] array column against an equivalent table with K
# flat columns, separating duckdb engine cost from the julia boundary cost
#
# deps: DuckDB, DataFrames

using DuckDB, DBInterface, DataFrames, Printf

const N       = 2_000_000
const K       = 8
const REPS    = 3
const ARR_DB  = "arr.db"
const WIDE_DB = "wide.db"

flatcols() = join(("v$j" for j in 1:K), ", ")

function build(path::String, sql::String)
  # fixtures are expensive, reuse them across runs
  isfile(path) && return
  @info "building $path"
  con = DBInterface.connect(DuckDB.DB, path)
  DBInterface.execute(con, sql)
  DBInterface.execute(con, "checkpoint")
  DBInterface.close!(con)
end

function build_fixtures()
  rands = join(("random()" for _ in 1:K), ", ")
  build(ARR_DB, """
    create table t as
    select i as id, cast([$rands] as double[$K]) as v
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
sink(con, sql) = () -> DBInterface.execute(con, "create or replace temp table sink as " * sql)

# boundary: materialise the full result as a DataFrame
pull(con, sql) = () -> DataFrame(DBInterface.execute(con, sql))

function main()
  build_fixtures()

  arr  = DBInterface.connect(DuckDB.DB, ARR_DB)
  wide = DBInterface.connect(DuckDB.DB, WIDE_DB)
  fc   = flatcols()

  # q_arr        = "select id, v from t"
  q_arr        = "select id, cast(v as double[]) as v from t"
  q_wide       = "select id, $fc from t"
  q_wide_asarr = "select id, array_value($fc) as v from t"

  println("\nengine only (sink to temp table)")
  e_arr  = bench(sink(arr,  q_arr),        "array:  select id, v")
  e_wide = bench(sink(wide, q_wide),       "wide:   select id, v1..v$K")
  e_asm  = bench(sink(wide, q_wide_asarr), "wide:   array_value(v1..v$K)")

  println("\ncrossing into julia (DataFrame)")
  b_arr  = bench(pull(arr,  q_arr),        "array:  select id, v")
  b_wide = bench(pull(wide, q_wide),       "wide:   select id, v1..v$K")
  b_asm  = bench(pull(wide, q_wide_asarr), "wide:   array_value(v1..v$K)")

  println("\nboundary cost (crossing minus engine)")
  @printf("  %-38s %8.1f ms\n", "array", (b_arr  - e_arr)  * 1000)
  @printf("  %-38s %8.1f ms\n", "wide",  (b_wide - e_wide) * 1000)
  @printf("  %-38s %8.1f ms\n", "wide, assembled", (b_asm - e_asm) * 1000)

  # touch every value so the representation is actually consumed, not just held
  println("\nconsume all values in julia")
  df_arr  = DataFrame(DBInterface.execute(arr,  q_arr))
  df_wide = DataFrame(DBInterface.execute(wide, q_wide))
  bench(() -> mapreduce(x -> sum(skipmissing(x)), +, df_arr.v),
        "array:  sum over Vector{Vector}")
  bench(() -> sum(sum(df_wide[!, "v$j"]) for j in 1:K),
        "wide:   sum over K columns")

  println("\ncolumn eltypes")
  println("  array: ", eltype(df_arr.v))
  println("  wide:  ", eltype(df_wide.v1))

  DBInterface.close!(arr)
  DBInterface.close!(wide)
end

main()

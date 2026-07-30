#!/usr/bin/env julia
#
# round-trip a StructArray of 8 Float64 fields through duckdb and through jld2,
# timing write and read separately
#
# the StructArray is already struct-of-arrays: 8 contiguous Vector{Float64}
# backing fields, which maps one-to-one onto a wide duckdb table
#
# deps: DuckDB, DBInterface, Tables, StructArrays, JLD2, Printf

using DuckDB, DBInterface, Tables, StructArrays, JLD2, Printf

const N        = 2_000_000
const REPS     = 3
const DUCK_DB  = "roundtrip.db"
const JLD_FILE = "roundtrip.jld2"

struct Row
  v1::Float64
  v2::Float64
  v3::Float64
  v4::Float64
  v5::Float64
  v6::Float64
  v7::Float64
  v8::Float64
end

const K = fieldcount(Row)

# min of REPS, with a setup hook run untimed before each repetition
function bench(f::Function, label::String; setup = () -> nothing)
  setup(); f()  # warm: compilation and page cache
  best_t, best_b = Inf, 0
  for _ in 1:REPS
    setup()
    r = @timed f()
    if r.time < best_t
      best_t, best_b = r.time, r.bytes
    end
  end
  @printf("  %-34s %8.1f ms  %9.1f MiB\n", label, best_t * 1000, best_b / 2^20)
  return best_t
end

rm_if(path) = isfile(path) && rm(path)

# duckdb: register the StructArray directly as a table scan, then materialise
# checkpoint is included so the comparison against jld2 is disk-to-disk
function write_duckdb(sa)
  con = DBInterface.connect(DuckDB.DB, DUCK_DB)
  DuckDB.register_table(con, sa, "sa")
  DBInterface.execute(con, "create or replace table t as select * from sa")
  DBInterface.execute(con, "checkpoint")
  DBInterface.close!(con)
  return
end

function read_duckdb()
  con = DBInterface.connect(DuckDB.DB, DUCK_DB)
  nt = Tables.columntable(DBInterface.execute(con, "select * from t"))
  sa = StructArray(nt)
  DBInterface.close!(con)
  return sa
end

write_jld2(sa) = jldsave(JLD_FILE; sa = sa)
read_jld2()    = JLD2.load(JLD_FILE, "sa")

# sum every field, used to check the round trips agree
checksum(sa) = sum(sum(getproperty(sa, f)) for f in fieldnames(Row))

function main()
  cols = NamedTuple(f => rand(N) for f in fieldnames(Row))
  sa = StructArray{Row}(cols)
  @printf("\nN = %d  K = %d  payload = %.1f MiB\n", N, K, N * K * 8 / 2^20)
  @printf("backing field type: %s\n", typeof(getproperty(sa, :v1)))

  println("\nwrite (cold file, includes fsync/checkpoint)")
  bench(() -> write_duckdb(sa), "duckdb: register + create table",
        setup = () -> rm_if(DUCK_DB))
  bench(() -> write_jld2(sa), "jld2:   jldsave",
        setup = () -> rm_if(JLD_FILE))

  println("\nread (to StructArray)")
  bench(read_duckdb, "duckdb: columntable + StructArray")
  bench(read_jld2,   "jld2:   load")

  println("\nfile size")
  @printf("  %-34s %8.1f MiB\n", "duckdb", filesize(DUCK_DB) / 2^20)
  @printf("  %-34s %8.1f MiB\n", "jld2",   filesize(JLD_FILE) / 2^20)

  println("\nround trip check (should all match)")
  ref = checksum(sa)
  @printf("  %-34s %.6f\n", "in memory", ref)
  @printf("  %-34s %.6f\n", "via duckdb", checksum(read_duckdb()))
  @printf("  %-34s %.6f\n", "via jld2",   checksum(read_jld2()))
end

main()

# verify_list_appender_gc.jl
#
# DISCOVERED IN PHASE 2, not planned: benchmarking `list/appender` segfaulted
# inside duckdb's C++ after ~15M julia allocations, in
# `LogicalType::LogicalType(LogicalType const&)` — a copy constructor reading a
# LogicalType that is no longer valid.
#
# WHAT IS ESTABLISHED (measured here):
#
#   natural  — appender + LIST: SEGFAULT, reproducibly, at ~1.0-1.2M list
#              appends. crash site varies between `LogicalType::LogicalType(
#              LogicalType const&)` and `StructType::GetChildTypes`.
#   bind     — prepared-statement + LIST: SURVIVES 4M list values. this is the
#              discriminator: statement.jl:69-72 routes through the SAME
#              `create_value`, so the defect is NOT in create_value alone.
#
# CONSEQUENCE (the part that matters for codegen): do not emit the appender for
# LIST columns in DuckDB.jl 1.5.2. It does not fail loudly or degrade — it takes
# the process down. Use the prepared bind or the literal path.
#
# HYPOTHESES TESTED AND *NOT* CONFIRMED — recorded so nobody re-runs them:
#
#   H1 "GC finalizes `type`/`values` during the ccall". value.jl:52-56 reads
#      `type.handle` and the child handles with no `GC.@preserve`, and both are
#      finalizer-owned (logical_type.jl:10, value.jl:9). Test: force GC between
#      batches (`gc` mode, now removed) and disable GC (`nogc`). Both survived —
#      but both arms were UNINFORMATIVE: a forced collection at a safe point
#      cannot exercise a race inside a ccall, and disabling GC removes
#      finalizers entirely. Neither supports nor refutes H1.
#
#   H2 "the appender retains the duckdb_value past `append`, but julia destroys
#      it at scope exit". Would explain why bind survives (execute consumes the
#      value immediately) and the appender does not. Test: `midbatch` forces GC
#      while rows are still buffered, before flush. Survived — but that run did
#      only ~40k appends, far below the ~1M threshold, so it is UNDERPOWERED
#      rather than refuting.
#
# Root-causing further means C++-level debugging of libduckdb, which is out of
# scope for this session (goal.md: "out: ... patching DuckDB.jl itself"). The
# measured behaviour and its codegen consequence are what this file records.
#
# run one mode per process — a segfault takes the process with it:
#   julia --project=. verify_list_appender_gc.jl natural   # GC fires naturally
#   julia --project=. verify_list_appender_gc.jl nogc      # GC disabled
#   julia --project=. verify_list_appender_gc.jl bind      # prepared-stmt path
#   julia --project=. verify_list_appender_gc.jl midbatch  # GC before flush
#
# `bind` matters because statement.jl:69-72 routes list binds through the SAME
# create_value function, so the defect should not be appender-specific.

using DuckDB

mode = isempty(ARGS) ? "natural" : ARGS[1]
mode in ("natural", "nogc", "bind", "midbatch") ||
  error("mode must be natural|nogc|bind|midbatch")

const ROWS = 10_000
const BATCHES = 400

con = DBInterface.connect(DuckDB.DB)
DBInterface.execute(con, "CREATE OR REPLACE TABLE t (id INTEGER, xs INTEGER[])")

# varying lengths, as in the benchmark profile
lists = [Int32.(1:(1 + (i % 4))) for i in 1:ROWS]

println("mode=", mode, "  rows/batch=", ROWS, "  batches=", BATCHES,
        "  (", ROWS * BATCHES, " list values total)")
println("a batch line that never prints is where the process died.")
flush(stdout)

mode == "nogc" && GC.enable(false)

for b in 1:BATCHES
  if mode == "midbatch"
    # H2's test (see header). the appender buffers rows until flush, so it may
    # still reference each list's duckdb_value after `append` returned, while
    # the julia `Value` from appender.jl:107 is already unreachable — so a
    # collection here would destroy values duckdb still needs.
    # OUTCOME: survived, but only ~40k appends vs the ~1M crash threshold, so
    # this is underpowered, not a refutation. raise the row count before
    # drawing any conclusion from it
    ap = DuckDB.Appender(con, "t")
    for i in 1:100
      DuckDB.append(ap, Int32(i))
      DuckDB.append(ap, lists[i])
      DuckDB.end_row(ap)
    end
    GC.gc()                    # collect while the rows are STILL BUFFERED
    DuckDB.flush(ap)
    DuckDB.close(ap)
  elseif mode == "bind"
    # prepared-statement route: statement.jl:69-72 -> create_value, same defect
    stmt = DBInterface.prepare(con, "INSERT INTO t VALUES (?, ?)")
    for i in 1:ROWS
      DBInterface.execute(stmt, (Int32(i), lists[i]))
    end
  else
    ap = DuckDB.Appender(con, "t")
    for i in 1:ROWS
      DuckDB.append(ap, Int32(i))
      DuckDB.append(ap, lists[i])
      DuckDB.end_row(ap)
    end
    DuckDB.flush(ap)
    DuckDB.close(ap)
  end

  # deliberately NOT calling GC.gc() here — see the method note above
  # midbatch appends 100 rows per batch, the others ROWS — report the real
  # count so an underpowered run cannot be mistaken for a passing one
  if b % 20 == 0
    per = mode == "midbatch" ? 100 : ROWS
    println("  batch ", lpad(b, 4), " ok  (", b * per, " list values appended)")
    flush(stdout)
  end
end

mode == "nogc" && GC.enable(true)

n = only(only(DBInterface.execute(con, "SELECT count(*) AS c FROM t")))
println("SURVIVED all ", BATCHES, " batches; rows=", n)

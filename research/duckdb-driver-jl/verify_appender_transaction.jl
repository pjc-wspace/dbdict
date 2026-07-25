# verify_appender_transaction.jl
#
# QUESTION (open behavior 3 of 4): does appender output participate in the
# connection's open transaction? the driver study (notes/20260725-1007 §5)
# recorded this as *Inferred* — "standard DuckDB appender behavior" — and the
# codegen plan depends on it: the bulk-replace pattern is
#   BEGIN; DELETE FROM t; <append rows>; COMMIT
# which is only atomic if the appended rows are inside the transaction. if they
# are not, a failure mid-load leaves the table empty (the DELETE rolled back but
# the rows already visible, or vice versa) — a data-loss bug in generated code.
#
# the buffering makes this subtle: the appender holds rows until flush/close
# (appender.jl:126-129), so "when did the rows become visible" and "which
# transaction were they in" are separate questions. both are measured here.
#
# run: julia --project=. verify_appender_transaction.jl

using DuckDB

section(title) = println("\n== ", title)
say(label, verdict) = println("  ", rpad(label, 46), " : ", verdict)

function attempt(f)
  try
    return (ok = true, value = f(), err = nothing)
  catch e
    return (ok = false, value = nothing, err = sprint(showerror, e))
  end
end

count_rows(c, tbl) = only(only(DBInterface.execute(c, "SELECT count(*) AS n FROM $tbl")))

# append n rows through a fresh appender, optionally skipping the explicit flush
# so we can isolate flush-vs-close semantics
function append_rows!(c, tbl, ids; flush = true, close = true)
  ap = DuckDB.Appender(c, tbl)
  for i in ids
    DuckDB.append(ap, Int32(i))
    DuckDB.end_row(ap)
  end
  flush && DuckDB.flush(ap)
  close && DuckDB.close(ap)
  return ap    # returned so the caller can close it later when close=false
end

db = DBInterface.connect(DuckDB.DB)

println("DuckDB.jl appender / transaction verification")
println("driver source: ", dirname(pathof(DuckDB)))

# ---------------------------------------------------------------------------
# 1. commit path — rows appended inside a transaction survive COMMIT
# ---------------------------------------------------------------------------
section("1. append + flush inside DBInterface.transaction, then commit")
DBInterface.execute(db, "CREATE OR REPLACE TABLE t1 (id INTEGER)")
r = attempt(() -> DBInterface.transaction(db) do
  append_rows!(db, "t1", 1:5)
end)
say("transaction threw?", r.ok ? "no" : "YES: " * something(r.err, ""))
say("rows after commit", string(count_rows(db, "t1")))
say("VERDICT", count_rows(db, "t1") == 5 ? "rows survive commit" : "rows LOST")

# ---------------------------------------------------------------------------
# 2. rollback path — the decisive test
# ---------------------------------------------------------------------------
# if appended rows participate in the transaction, ROLLBACK must remove them.
# if they were written outside it, they will still be there. explicit
# begin/rollback (transaction.jl:25-28, 47-48) rather than the
# DBInterface.transaction wrapper, because that wrapper only rolls back on an
# exception and we want a clean, deliberate rollback
section("2. append + flush inside a transaction, then ROLLBACK")
DBInterface.execute(db, "CREATE OR REPLACE TABLE t2 (id INTEGER)")
DuckDB.begin_transaction(db)
append_rows!(db, "t2", 1:5)
say("rows visible before rollback", string(count_rows(db, "t2")))
DuckDB.rollback(db)
n2 = count_rows(db, "t2")
say("rows after rollback", string(n2))
say("VERDICT", n2 == 0 ? "appender rows ARE in the transaction (rolled back)" :
                         "appender rows are OUTSIDE the transaction ($n2 survived)")

# ---------------------------------------------------------------------------
# 3. the buffering trap: COMMIT before the appender is flushed
# ---------------------------------------------------------------------------
# a generated writer that forgets to flush inside the transaction — or relies on
# close() to flush — is the realistic bug. what happens to rows still sitting in
# the appender's buffer when COMMIT runs?
section("3. COMMIT while rows are still buffered (no flush inside the txn)")
DBInterface.execute(db, "CREATE OR REPLACE TABLE t3 (id INTEGER)")
DuckDB.begin_transaction(db)
ap3 = append_rows!(db, "t3", 1:5; flush = false, close = false)
say("rows visible before commit", string(count_rows(db, "t3")))
r3 = attempt(() -> DuckDB.commit(db))
say("commit threw?", r3.ok ? "no" : "YES: " * something(r3.err, ""))
say("rows right after commit", string(count_rows(db, "t3")))
r3c = attempt(() -> DuckDB.close(ap3))     # close flushes (appender.jl:64-75)
say("close threw?", r3c.ok ? "no" : "YES: " * something(r3c.err, ""))
n3 = count_rows(db, "t3")
say("rows after closing the appender", string(n3))
say("VERDICT", n3 == 5 ? "unflushed rows land AFTER commit — outside the txn" :
               n3 == 0 ? "unflushed rows are LOST at commit" :
                         "partial: $n3 of 5")

# ---------------------------------------------------------------------------
# 4. the same trap under ROLLBACK
# ---------------------------------------------------------------------------
# worse version of 3: if unflushed rows land *after* the transaction ends, they
# would survive a rollback that was supposed to discard them
section("4. ROLLBACK while rows are still buffered")
DBInterface.execute(db, "CREATE OR REPLACE TABLE t4 (id INTEGER)")
DuckDB.begin_transaction(db)
ap4 = append_rows!(db, "t4", 1:5; flush = false, close = false)
r4 = attempt(() -> DuckDB.rollback(db))
say("rollback threw?", r4.ok ? "no" : "YES: " * something(r4.err, ""))
say("rows right after rollback", string(count_rows(db, "t4")))
r4c = attempt(() -> DuckDB.close(ap4))
say("close threw?", r4c.ok ? "no" : "YES: " * something(r4c.err, ""))
n4 = count_rows(db, "t4")
say("rows after closing the appender", string(n4))
say("VERDICT", n4 == 0 ? "buffered rows discarded with the rollback" :
                         "$n4 rows SURVIVED a rollback — leak")

# ---------------------------------------------------------------------------
# 5. the bulk-replace pattern end to end
# ---------------------------------------------------------------------------
# this is the shape dbdict's generated writer would emit. it must be atomic: an
# exception partway through must leave the ORIGINAL rows intact
section("5. bulk-replace: BEGIN; DELETE; append; <error>; ROLLBACK")
DBInterface.execute(db, "CREATE OR REPLACE TABLE t5 (id INTEGER)")
append_rows!(db, "t5", 100:104)                    # pre-existing data
say("rows before replace", string(count_rows(db, "t5")))
r5 = attempt(() -> DBInterface.transaction(db) do
  DBInterface.execute(db, "DELETE FROM t5")
  append_rows!(db, "t5", 1:3)
  error("simulated failure partway through the load")
end)
say("transaction threw (expected)?", r5.ok ? "no — unexpected" : "yes")
n5 = count_rows(db, "t5")
say("rows after failed replace", string(n5))
say("VERDICT", n5 == 5 ? "atomic — original data intact" :
                         "NOT atomic — $n5 rows (original data destroyed)")

# ---------------------------------------------------------------------------
# 6. isolation: can another connection see uncommitted appender rows?
# ---------------------------------------------------------------------------
# transactions are per-connection (study §5, database.jl:36-42). a second
# connection must not observe rows from an open transaction on the first
section("6. second connection's view of an open transaction")
DBInterface.execute(db, "CREATE OR REPLACE TABLE t6 (id INTEGER)")
con2 = DBInterface.connect(db)                     # own Connection (database.jl:113)
DuckDB.begin_transaction(db)
append_rows!(db, "t6", 1:5)
say("writer connection sees", string(count_rows(db, "t6")))
say("second connection sees", string(count_rows(con2, "t6")))
n6_other = count_rows(con2, "t6")
DuckDB.commit(db)
say("second connection after commit", string(count_rows(con2, "t6")))
say("VERDICT", n6_other == 0 ? "properly isolated — no uncommitted reads" :
                               "LEAK — uncommitted rows visible ($n6_other)")

# ---------------------------------------------------------------------------
# 7. the mitigation for §4 — does it actually hold?
# ---------------------------------------------------------------------------
# there is no "discard" in the C appender API: duckdb_appender_destroy is
# documented (api.jl:6820) as "Closes the appender by flushing all intermediate
# states to the table and destroying it". so buffered rows CANNOT be thrown
# away — the only lever is *when* the flush happens relative to the transaction.
#
# proposed rule for generated code: the appender's whole lifetime lives inside
# the transaction body, with try/finally guaranteeing close() runs before the
# transaction unwinds. then a rollback discards the rows because they were
# flushed while the transaction was still open. measure it, don't assume it.
section("7. mitigation: appender closed in a finally INSIDE the txn body")
DBInterface.execute(db, "CREATE OR REPLACE TABLE t7 (id INTEGER)")
r7 = attempt(() -> DBInterface.transaction(db) do
  ap = DuckDB.Appender(db, "t7")
  try
    for i in 1:5
      DuckDB.append(ap, Int32(i))
      DuckDB.end_row(ap)
    end
    error("simulated failure before the caller could flush")
  finally
    # runs while the transaction is still open, so the flush lands inside it
    DuckDB.close(ap)
  end
end)
say("transaction threw (expected)?", r7.ok ? "no — unexpected" : "yes")
n7 = count_rows(db, "t7")
say("rows after rollback", string(n7))
say("VERDICT", n7 == 0 ? "mitigation HOLDS — no leak" : "mitigation FAILS — $n7 rows leaked")

# 7b. the counter-example: same failure, appender left to the GC finalizer
# (appender.jl:59). this is what naive generated code would do. the rows may
# appear at an arbitrary later time, which is worse than appearing immediately
section("7b. counter-example: appender abandoned to the finalizer")
DBInterface.execute(db, "CREATE OR REPLACE TABLE t7b (id INTEGER)")
r7b = attempt(() -> DBInterface.transaction(db) do
  ap = DuckDB.Appender(db, "t7b")
  for i in 1:5
    DuckDB.append(ap, Int32(i))
    DuckDB.end_row(ap)
  end
  error("simulated failure, appender never closed")
end)
say("transaction threw (expected)?", r7b.ok ? "no — unexpected" : "yes")
say("rows right after rollback", string(count_rows(db, "t7b")))
GC.gc(); GC.gc()      # force the finalizer that close() would otherwise have run
n7b = count_rows(db, "t7b")
say("rows after forced GC", string(n7b))
say("VERDICT", n7b == 0 ? "no leak observed via finalizer" :
                          "LEAK — $n7b rows appeared at GC time, after the rollback")

println("\ndone.")

# verify_structarray_register.jl
#
# QUESTION (open behavior 4 of 4): does `register_table` accept a StructArray
# via the Tables.jl route, and where exactly does it stop?
#
# why it matters: the spike's writer-tier plan (notes/20260723-1530 §2, path E)
# writes STRUCT columns by registering the struct's *field arrays* as flat
# columns and reassembling them in SQL. a StructArray stores its fields as
# separate arrays already, so it should hand those over for free — if the
# Tables.jl plumbing really is pass-through and not a copy. that "for free" is
# an assumption worth measuring, because it is the whole argument for the tier.
#
# study §3c: register_table stores `columntable(tbl)` (table_scan.jl:201) and
# column types are limited to `create_logical_type` coverage
# (logical_type.jl:28-66), with failure at *bind* time (first query), not at
# registration. both halves of that are checked here.
#
# run: julia --project=. verify_structarray_register.jl

using DuckDB
using StructArrays
using Tables
using UUIDs

section(title) = println("\n== ", title)
say(label, verdict) = println("  ", rpad(label, 46), " : ", verdict)

function attempt(f)
  try
    return (ok = true, value = f(), err = nothing)
  catch e
    return (ok = false, value = nothing, err = sprint(showerror, e))
  end
end

# short one-line error text for the report table. showerror output for these
# QueryExceptions carries a stacktrace tail we don't want in the record — cut at
# the first "Stacktrace" marker, then collapse to one line
function short(e)
  head = first(split(e, "Stacktrace"))
  return first(replace(strip(head), "\n" => " "), 110)
end

# register a table-like object, then actually query it — study §3c says an
# unsupported column type throws at bind time, so registration alone proves
# nothing. we report the two phases separately to confirm that claim
function probe_register(db, obj, name; select = "*")
  reg = attempt(() -> DuckDB.register_table(db, obj, name))
  if !reg.ok
    return (registered = false, reg_err = short(reg.err), queried = false, q_err = nothing, rows = 0)
  end
  q = attempt(() -> collect(DBInterface.execute(db, "SELECT $select FROM \"$name\"")))
  if !q.ok
    return (registered = true, reg_err = nothing, queried = false, q_err = short(q.err), rows = 0)
  end
  return (registered = true, reg_err = nothing, queried = true, q_err = nothing, rows = length(q.value))
end

function report(label, r)
  println("\n  case: ", label)
  say("  register_table", r.registered ? "ok" : "THREW: " * something(r.reg_err, ""))
  if r.registered
    say("  SELECT from the view", r.queried ? "ok, $(r.rows) rows" : "THREW: " * something(r.q_err, ""))
  end
  if r.registered && !r.queried
    println("      >> failure is at BIND time, not registration (study §3c confirmed)")
  end
end

db = DBInterface.connect(DuckDB.DB)

println("DuckDB.jl StructArray / register_table verification")
println("driver source: ", dirname(pathof(DuckDB)))

# ---------------------------------------------------------------------------
# 1. flat StructArray of primitives — the case the tier plan depends on
# ---------------------------------------------------------------------------
section("1. flat StructArray of primitives")
sa_flat = StructArray((id = Int32[1, 2, 3],
                       name = ["a", "b", "c"],
                       score = [1.5, 2.5, 3.5]))
say("is it a Tables.jl table?", string(Tables.istable(typeof(sa_flat))))
report("StructArray(id::Int32, name::String, score::Float64)",
       probe_register(db, sa_flat, "v_flat"))

# INSERT ... SELECT into a real table — the actual write path, not just a read
DBInterface.execute(db, "CREATE OR REPLACE TABLE t_flat (id INTEGER, name VARCHAR, score DOUBLE)")
r_ins = attempt(() -> DBInterface.execute(db, "INSERT INTO t_flat SELECT * FROM v_flat"))
say("INSERT INTO ... SELECT threw?", r_ins.ok ? "no" : "YES: " * short(something(r_ins.err, "")))
say("rows written", string(only(only(DBInterface.execute(db, "SELECT count(*) AS n FROM t_flat")))))

# ---------------------------------------------------------------------------
# 2. is the Tables.jl route actually zero-copy?
# ---------------------------------------------------------------------------
# register_table stores `columntable(tbl)` (table_scan.jl:201). a StructArray
# already holds its fields as separate arrays (StructArrays.components), so IF
# columntable hands back those same array objects, registration costs nothing —
# which is the performance argument for the flatten-and-reassemble tier.
# `===` is object identity in julia, so this distinguishes "same array" from
# "equal copy"
section("2. does columntable alias the StructArray's component arrays?")
comps = StructArrays.components(sa_flat)
ct = Tables.columntable(sa_flat)
for k in keys(comps)
  say("component :$k aliased (===)?", string(getproperty(ct, k) === getproperty(comps, k)))
end
say("VERDICT", all(getproperty(ct, k) === getproperty(comps, k) for k in keys(comps)) ?
               "zero-copy — registration hands over the existing arrays" :
               "COPIES made — the tier's 'free' assumption is wrong")

# ---------------------------------------------------------------------------
# 3. nested StructArray — expected to fail; record exactly how
# ---------------------------------------------------------------------------
# a StructArray whose field is itself a StructArray produces a column whose
# eltype is a NamedTuple. create_logical_type has no NamedTuple method
# (logical_type.jl:64-66), so this should throw at bind time
section("3. StructArray with a nested struct field")
sa_nested = StructArray((id = Int32[1, 2],
                         loc = StructArray((x = [1.0, 2.0], y = [3.0, 4.0]))))
say("eltype of the nested column", string(eltype(Tables.columntable(sa_nested).loc)))
report("StructArray(id::Int32, loc::StructArray(x,y))",
       probe_register(db, sa_nested, "v_nested"))

# 3b. the workaround the spike proposed (path E): register the LEAF fields as
# flat columns and reassemble the struct in SQL. measure it end to end so the
# reference doc can recommend it with evidence
section("3b. workaround — register leaf fields, reassemble in SQL")
leaves = StructArray((id = Int32[1, 2],
                      loc_x = [1.0, 2.0],
                      loc_y = [3.0, 4.0]))
r_leaf = probe_register(db, leaves, "v_leaves")
say("leaf view registered + queried", r_leaf.queried ? "ok, $(r_leaf.rows) rows" :
                                      "FAILED: " * something(r_leaf.q_err, something(r_leaf.reg_err, "")))
DBInterface.execute(db, "CREATE OR REPLACE TABLE t_nested (id INTEGER, loc STRUCT(x DOUBLE, y DOUBLE))")
r_re = attempt(() -> DBInterface.execute(db,
  "INSERT INTO t_nested SELECT id, {'x': loc_x, 'y': loc_y} FROM v_leaves"))
say("SQL struct reassembly threw?", r_re.ok ? "no" : "YES: " * short(something(r_re.err, "")))
if r_re.ok
  got = collect(DBInterface.execute(db, "SELECT id, loc FROM t_nested ORDER BY id"))
  say("rows written", string(length(got)))
  say("first row loc", repr(first(got).loc))
end

# ---------------------------------------------------------------------------
# 4. field types at the edge of create_logical_type coverage
# ---------------------------------------------------------------------------
# study §3c lists what create_logical_type supports (logical_type.jl:28-62).
# these decide which columns a StructArray-backed writer can carry at all
section("4. field types at the coverage boundary")

# 4a. nullable field. table_scan.jl:19 strips Missing from the eltype before
# building the logical type, so this should work where a bare Union would not
report("nullable field Union{Missing,Int32}",
       probe_register(db, StructArray((id = Union{Missing, Int32}[Int32(1), missing],)), "v_nullable"))

# 4b. UUID field — not in create_logical_type's list, so expected to fail.
# relevant because dbdict schemas use UUID columns freely
report("UUID field",
       probe_register(db, StructArray((u = [uuid4(), uuid4()],)), "v_uuid"))

# 4c. list field — also outside coverage, and the other common rich type
report("list field Vector{Int32}",
       probe_register(db, StructArray((xs = [Int32[1, 2], Int32[3]],)), "v_list"))

println("\ndone.")

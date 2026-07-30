#!/usr/bin/env julia
#
# store two StructArrays in one JLD2 file as hdf5 groups, one group per table,
# one named dataset per column
#
# every dataset is a native hdf5 type with a simple dataspace and no attributes,
# and no /_types group is created, so the file reads cleanly in h5v, h5ls,
# h5dump, h5py, etc
#
# the column order is driven by fieldnames(T) rather than keys(group), since
# link ordering in a group is not a stable column order
#
# deps: StructArrays, JLD2

using StructArrays, JLD2

const FILE = "tables.jld2"

struct Trip
  id::Int64
  dist::Float64
  dur::Float64
end

struct Stop
  trip_id::Int64
  seq::Int32
  lat::Float64
  lon::Float64
end

# name => element type, drives both write and read
const SCHEMA = (trips = Trip, stops = Stop)

function write_table(f, name, sa)
  g = JLD2.Group(f, string(name))
  for k in propertynames(sa)
    g[string(k)] = getproperty(sa, k)  # backing vector, written as-is
  end
  return g
end

function read_table(f, name, ::Type{T}) where {T}
  g = f[string(name)]
  StructArray{T}(NamedTuple(k => g[string(k)] for k in fieldnames(T)))
end

write_tables(path, tables) =
  jldopen(path, "w") do f
    for (name, sa) in pairs(tables)
      write_table(f, name, sa)
    end
    path
  end

read_tables(path, schema) =
  jldopen(path, "r") do f
    NamedTuple(name => read_table(f, name, T) for (name, T) in pairs(schema))
  end

# walk the group tree the way a non-julia reader would
function show_layout(path)
  jldopen(path, "r") do f
    for name in keys(f)
      obj = f[name]
      if obj isa JLD2.Group
        println("/", name)
        for col in keys(obj)
          v = obj[col]
          println("  ", rpad(col, 10), eltype(v), " (", length(v), ")")
        end
      else
        println("/", rpad(name, 10), typeof(obj))
      end
    end
  end
end

function main()
  ntrip, nstop = 500, 2000

  trips = StructArray{Trip}((
    id   = collect(Int64, 1:ntrip),
    dist = 50 .* rand(ntrip),
    dur  = 90 .* rand(ntrip),
  ))

  stops = StructArray{Stop}((
    trip_id = rand(Int64.(1:ntrip), nstop),
    seq     = rand(Int32.(1:8), nstop),
    lat     = -44 .+ 2 .* rand(nstop),
    lon     = 170 .+ 3 .* rand(nstop),
  ))

  write_tables(FILE, (trips = trips, stops = stops))

  println("layout")
  show_layout(FILE)

  rt = read_tables(FILE, SCHEMA)

  println("\nround trip")
  for (name, T) in pairs(SCHEMA)
    orig = name == :trips ? trips : stops
    ok = all(getproperty(orig, k) == getproperty(rt[name], k) for k in fieldnames(T))
    println("  ", rpad(string(name), 8), eltype(rt[name]), "  n=", length(rt[name]), "  identical=", ok)
  end

  println("\nrow 1 of each")
  println("  ", rt.trips[1])
  println("  ", rt.stops[1])

  println("\nfilesize ", filesize(FILE), " bytes")

  # what a non-julia reader sees:
  #   h5ls -r tables.jld2
  #   h5dump -H tables.jld2
  #   h5v tables.jld2
end

main()

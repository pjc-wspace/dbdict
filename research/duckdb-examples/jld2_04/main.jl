#!/usr/bin/env julia
#
# two StructArrays stored as hdf5 groups in one JLD2 file, one named dataset per
# column, with switchable compression
#
#   :none  no filter pipeline, contiguous layout
#   :zlib  Shuffle (id 2) + Deflate (id 1), both built into libhdf5
#   :zstd  ZstdFilter (id 32015), a registered filter that needs a plugin on the
#          reader side (hdf5plugin for h5py, a compiled filter for libhdf5)
#
# any filter forces the chunked layout branch, so the :none files differ from the
# other two in layout class as well as pipeline
#
# deps: StructArrays, JLD2

using StructArrays, JLD2, Printf

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

const SCHEMA = (trips = Trip, stops = Stop)

# maps a mode keyword onto the compress argument accepted by jldopen
function pipeline(mode::Symbol)
  mode === :none && return false
  mode === :zlib && return [Shuffle(), Deflate(level = 6)]
  mode === :zstd && return ZstdFilter(level = 3)
  throw(ArgumentError("unknown compression mode $(repr(mode)), expected :none, :zlib or :zstd"))
end

function write_table(f, name, sa)
  g = JLD2.Group(f, string(name))
  for k in propertynames(sa)
    g[string(k)] = getproperty(sa, k)
  end
  return g
end

function read_table(f, name, ::Type{T}) where {T}
  g = f[string(name)]
  StructArray{T}(NamedTuple(k => g[string(k)] for k in fieldnames(T)))
end

write_tables(path, tables; compress::Symbol = :none) =
  jldopen(path, "w"; compress = pipeline(compress)) do f
    for (name, sa) in pairs(tables)
      write_table(f, name, sa)
    end
    path
  end

read_tables(path, schema) =
  jldopen(path, "r") do f
    NamedTuple(name => read_table(f, name, T) for (name, T) in pairs(schema))
  end

# per-dataset pipelines instead of per-file, via the explicit dataset api
function write_table_mixed(f, name, sa, modes::NamedTuple)
  g = JLD2.Group(f, string(name))
  for k in propertynames(sa)
    v = getproperty(sa, k)
    fs = pipeline(get(modes, k, :none))
    dset = JLD2.create_dataset(g, string(k); filters = JLD2.Filters.normalize_filters(fs))
    JLD2.write_dataset(dset, v)
  end
  return g
end

function make_tables(ntrip, nstop)
  trips = StructArray{Trip}((
    id   = collect(Int64, 1:ntrip),          # sequential, compresses hard
    dist = 50 .* rand(ntrip),                # full mantissa entropy, barely compresses
    dur  = 90 .* rand(ntrip),
  ))

  stops = StructArray{Stop}((
    trip_id = repeat(collect(Int64, 1:ntrip), inner = nstop ÷ ntrip),  # runs of equal values
    seq     = rand(Int32(1):Int32(8), nstop),                          # low cardinality
    lat     = -44 .+ 2 .* rand(nstop),
    lon     = 170 .+ 3 .* rand(nstop),
  ))

  (trips = trips, stops = stops)
end

function tables_equal(a, b)
  all(pairs(SCHEMA)) do (name, T)
    all(getproperty(a[name], k) == getproperty(b[name], k) for k in fieldnames(T))
  end
end

function main()
  ntrip, nstop = 100_000, 800_000
  tables = make_tables(ntrip, nstop)
  raw = sum(sizeof(getproperty(tables[n], k)) for (n, T) in pairs(SCHEMA) for k in fieldnames(T))

  @printf("payload %.1f MiB\n\n", raw / 2^20)
  @printf("%-6s %10s %8s %8s %8s  %s\n", "mode", "MiB", "ratio", "w ms", "r ms", "round trip")

  for mode in (:none, :zlib, :zstd)
    path = "tables_$(mode).jld2"
    isfile(path) && rm(path)

    tw = @elapsed write_tables(path, tables; compress = mode)
    tr = @elapsed rt = read_tables(path, SCHEMA)
    sz = filesize(path)

    @printf("%-6s %10.1f %8.2fx %8.0f %8.0f  %s\n",
            mode, sz / 2^20, raw / sz, tw * 1000, tr * 1000, tables_equal(tables, rt))
  end

  # per-column pipelines: cheap filter on the integer columns, none on the floats
  path = "tables_mixed.jld2"
  isfile(path) && rm(path)
  jldopen(path, "w") do f
    write_table_mixed(f, "trips", tables.trips, (id = :zlib,))
    write_table_mixed(f, "stops", tables.stops, (trip_id = :zlib, seq = :zlib))
  end
  @printf("\n%-6s %10.1f %8.2fx\n", "mixed", filesize(path) / 2^20, raw / filesize(path))
  println("round trip ", tables_equal(tables, read_tables(path, SCHEMA)))

  # inspect the pipelines a non-julia reader would see:
  #   h5dump -H -p tables_zlib.jld2 | grep -A6 FILTERS
  #   h5ls -v tables_zstd.jld2
end

main()

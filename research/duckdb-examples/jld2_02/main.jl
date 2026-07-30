#!/usr/bin/env julia
#
# round-trip a StructArray through JLD2 as one named dataset per component
#
# writing the StructArray directly (jldsave(file; sa=sa)) produces a scalar
# compound of object references pointing at unnamed, unlinked datasets: the
# data is present but invisible to any hdf5 tool that walks group links
#
# writing the components individually produces plain H5T_IEEE_F64LE datasets
# with simple dataspaces, no attributes, and no /_types group
#
# deps: StructArrays, JLD2

using StructArrays, JLD2

const FILE = "sa.jld2"

struct Row
  x::Float64
  y::Float64
  z::Float64
end

# one named dataset per component, keyed by field name
function write_structarray(path, sa)
  jldopen(path, "w") do f
    for k in propertynames(sa)
      f[string(k)] = getproperty(sa, k)  # backing vector, written as-is
    end
  end
  return path
end

# element type has to be supplied: it is not recoverable from a plain hdf5 file
function read_structarray(path, ::Type{T}) where {T}
  jldopen(path, "r") do f
    StructArray{T}(NamedTuple(k => f[string(k)] for k in fieldnames(T)))
  end
end

function main()
  n = 10_000_000
  sa = StructArray{Row}((x = rand(n), y = rand(n), z = rand(n)))

  write_structarray(FILE, sa)
  rt = read_structarray(FILE, Row)

  println("eltype     ", eltype(rt))
  println("size       ", size(rt))
  println("components ", propertynames(rt))
  println("identical  ", all(getproperty(sa, k) == getproperty(rt, k) for k in fieldnames(Row)))
  println("row 1      ", rt[1])
  println("filesize   ", filesize(FILE), " bytes for ", n * fieldcount(Row) * 8, " bytes of payload")

  # what a non-julia reader sees: three named float64 vectors, nothing else
  #   h5ls -r sa.jld2
  #   h5dump -H sa.jld2
  println("\ndatasets in file: ", jldopen(keys, FILE, "r"))
end

main()

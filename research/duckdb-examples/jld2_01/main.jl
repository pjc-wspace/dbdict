using JLD2

using JLD2


function main()

  
  jldsave("plain.jld2";
    x = collect(0.0:0.1:1.0),   # Vector{Float64} -> H5T_IEEE_F64LE
    n = collect(Int32, 1:10),   # Vector{Int32} -> H5T_STD_I32LE
    m = randn(2, 5)             # 2d, dims appear reversed to non-julia readers
  )            


end



main()

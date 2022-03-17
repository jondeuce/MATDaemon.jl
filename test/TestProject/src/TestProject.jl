module TestProject

using StaticArrays

function dot(x)
    v = SVector(x...)
    return v'v
end

end # module

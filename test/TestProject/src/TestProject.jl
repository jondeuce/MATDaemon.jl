module TestProject

using StaticArrays

function inner(x::AbstractMatrix)
    m, n = size(x)
    x = SMatrix{m,n}(x)
    return Matrix(x' * x)
end

end # module

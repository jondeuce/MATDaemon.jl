using GarishPrint: pprint

#### Recursive, typed equality testing

recurse_is_equal(eq) = (x, y) -> recurse_is_equal(eq, x, y)
recurse_is_equal(eq, x, y) = eq(x, y) #default
recurse_is_equal(eq, x::AbstractDict, y::AbstractDict) = eq(x, y) && all(recurse_is_equal(eq, x[k], y[k]) for k in keys(x))
recurse_is_equal(eq, x::NamedTuple, y::NamedTuple) = eq(x, y) && all(recurse_is_equal(eq, x[k], y[k]) for k in keys(x))

typed_is_equal(eq) = (x, y) -> typed_is_equal(eq, x, y)
typed_is_equal(eq, x, y) = eq(x, y) && typeof(x) == typeof(y)

is_eq(x, y) = recurse_is_equal(typed_is_equal(==), x, y) || pprint_compare((; x, y))
is_eqq(x, y) = recurse_is_equal(typed_is_equal(===), x, y) || pprint_compare((; x, y))

#### Pretty printing for deeply nested arguments

function pprint_compare(args::NamedTuple)
    for (k, v) in pairs(args)
        @info "Argument: $k"
        pprint(v)
        println("")
    end
    return false
end

#### Misc. utils

mxdict(args...) = Dict{String, Any}(args...)
mxtuple(args...) = Any[args...]
mxempty() = zeros(Float64, 0, 0)

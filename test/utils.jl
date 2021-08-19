using Pkg
using GarishPrint: pprint
using JuliaFromMATLAB: JLCallOptions

#### Misc. utils

mxdict(args...) = Dict{String, Any}(args...)
mxtuple(args...) = Any[args...]
mxempty() = zeros(Float64, 0, 0)

function redirect_to_files(f)
    open(tempname() * ".log", "w") do out
        open(tempname() * ".err", "w") do err
            redirect_stdout(out) do
                redirect_stderr(err) do
                    f()
                end
            end
        end
    end
end

#### Temporary workspace

const TEMP_WORKSPACE = mktempdir(; prefix = ".jlcall_", cleanup = true)

function initialize_workspace()
    if !isfile(joinpath(TEMP_WORKSPACE, "Project.toml"))
        curr = Base.active_project()
        redirect_to_files() do
            Pkg.activate(TEMP_WORKSPACE)
            Pkg.develop(PackageSpec(path = realpath(joinpath(@__DIR__, ".."))))
            Pkg.activate(curr)
        end
    end
    return TEMP_WORKSPACE
end

#### Recursive, typed equality testing

recurse_is_equal(eq) = (x, y) -> recurse_is_equal(eq, x, y)
recurse_is_equal(eq, x, y) = eq(x, y) #default
recurse_is_equal(eq, x::AbstractDict, y::AbstractDict) = eq(x, y) && all(recurse_is_equal(eq, x[k], y[k]) for k in keys(x))
recurse_is_equal(eq, x::NamedTuple, y::NamedTuple) = eq(x, y) && all(recurse_is_equal(eq, x[k], y[k]) for k in keys(x))
recurse_is_equal(eq, x::JLCallOptions, y::JLCallOptions) = all(recurse_is_equal(eq, getproperty(x, k), getproperty(y, k)) for k in fieldnames(JLCallOptions))

typed_is_equal(eq) = (x, y) -> typed_is_equal(eq, x, y)
typed_is_equal(eq, x, y) = eq(x, y) && typeof(x) == typeof(y)

is_eq(x, y) = recurse_is_equal(typed_is_equal(==), x, y) || pprint_compare((; x = x, y = y))
is_eqq(x, y) = recurse_is_equal(typed_is_equal(===), x, y) || pprint_compare((; x = x, y = y))

#### Pretty printing for deeply nested arguments

function pprint_compare(args::NamedTuple)
    for (k, v) in pairs(args)
        @info "Argument: $k"
        pprint(v)
        println("")
    end
    return false
end

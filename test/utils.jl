#### Misc. utils

mxdict(args...) = Dict{String, Any}(args...)
mxtuple(args...) = Any[args...]
mxempty() = zeros(Float64, 0, 0)

#### Temporary workspace

const TEMP_WORKSPACE = mktempdir(; prefix = ".jlcall_", cleanup = true)

function initialize_workspace()
    if !isfile(joinpath(TEMP_WORKSPACE, "Project.toml"))
        curr = Base.active_project()
        Pkg.activate(TEMP_WORKSPACE)
        Pkg.develop(PackageSpec(path = realpath(joinpath(@__DIR__, ".."))); io = devnull)
        Pkg.activate(curr)
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
        GarishPrint.pprint(v)
        println("")
    end
    return false
end

#### Convenience method for calling + testing @jlcall

function wrap_jlcall(f, f_args, f_kwargs, f_output; kwargs...)
    opts = JLCallOptions(;
        f         = f,
        args      = f_args,
        kwargs    = f_kwargs,
        workspace = initialize_workspace(),
        debug     = true,
        kwargs...,
    )
    input_file = joinpath(opts.workspace, JuliaFromMATLAB.JL_INPUT)
    output_file = joinpath(opts.workspace, JuliaFromMATLAB.JL_OUTPUT)

    MAT.matwrite(input_file, matlabify(opts))
    @test isfile(input_file)
    @test is_eq(opts, JuliaFromMATLAB.load_options(opts.workspace))

    @eval Main @jlcall($(opts.workspace))

    @test isfile(output_file)
    @test is_eq(f_output, MAT.matread(output_file)["output"])

    rm(input_file; force = true)
    rm(output_file; force = true)
end

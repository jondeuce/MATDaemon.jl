#### Misc. utils

mxdict(args...) = Dict{String, Any}(args...)
mxtuple(args...) = Any[args...]
mxempty() = zeros(Float64, 0, 0)

#### Temporary workspace

function reset_active_project(f)
    curr_proj = Base.active_project()
    try
        return f()
    finally
        Pkg.activate(curr_proj; io = devnull)
    end
end

function jlcall_workspace()
    workspace = ENV["MATDAEMON_WORKSPACE"]
    isfile(joinpath(workspace, "Project.toml")) && return workspace

    reset_active_project() do
        Pkg.activate(workspace; io = devnull)
        Pkg.develop(PackageSpec(path = realpath(joinpath(@__DIR__, ".."))); io = devnull)
        return workspace
    end
end

function jlcall_test_project()
    test_proj = joinpath(@__DIR__, "TestProject")
    isfile(joinpath(test_proj, "Manifest.toml")) && return test_proj

    reset_active_project() do
        Pkg.activate(test_proj; io = devnull)
        Pkg.instantiate(; io = devnull)
        return test_proj
    end
end

#### Recursive, typed equality testing

recurse_is_equal(eq) = (x, y) -> recurse_is_equal(eq, x, y)
recurse_is_equal(eq, x, y) = eq(x, y) #fallback
recurse_is_equal(eq, x::Tuple, y::Tuple) = eq(x, y) && all(recurse_is_equal(eq, x[i], y[i]) for i in 1:length(x))
recurse_is_equal(eq, x::KeyValueContainer, y::KeyValueContainer) = eq(x, y) && all(recurse_is_equal(eq, x[k], y[k]) for k in keys(x))
recurse_is_equal(eq, x::JLCallOptions, y::JLCallOptions) = all(recurse_is_equal(eq, getproperty(x, k), getproperty(y, k)) for k in fieldnames(JLCallOptions))

typed_is_equal(eq) = (x, y) -> typed_is_equal(eq, x, y)
typed_is_equal(eq, x, y) = eq(x, y) && typeof(x) == typeof(y)

verbose_typed_is_equal(eq) = (x, y) -> verbose_typed_is_equal(eq, x, y)
verbose_typed_is_equal(eq, x, y) = typed_is_equal(eq, x, y) || pprint_compare(x, y)

is_eq(x, y) = recurse_is_equal(verbose_typed_is_equal(isequal), x, y)
is_eqq(x, y) = recurse_is_equal(verbose_typed_is_equal(===), x, y)

#### Custom types

# Struct without custom matlabify; fields will not be recursively matlabified
struct A
    x
    y
end

recurse_is_equal(eq, a1::A, a2::A) = recurse_is_equal(eq, (a1.x, a1.y), (a2.x, a2.y))

# Struct with custom matlabify; fields will be recursively matlabified
struct B
    x
    y
end

recurse_is_equal(eq, b1::B, b2::B) = recurse_is_equal(eq, (b1.x, b1.y), (b2.x, b2.y))

MATDaemon.matlabify(b::B) = mxdict("x" => matlabify(b.x), "y" => matlabify(b.y))

#### Building deeply nested types for testing

function deeply_nested_pairs(; roundtrip = false)
    # List of pairs of primitive base cases
    ps = Any[
        nothing                => mxempty(),
        missing                => mxempty(),
        1                      => 1,
        2.0                    => 2.0,
        "string"               => "string",
        :symbol                => "symbol",
        [1.0, 2.0]             => [1.0, 2.0],
        [3.0 4.0]              => [3.0 4.0],
        ones(Float32, 1, 1, 2) => ones(Float32, 1, 1, 2),
        [3.0]                  => roundtrip ? 3.0 : [3.0],
        ones(1, 1, 1)          => roundtrip ? 1.0 : ones(1, 1, 1),
        zeros(1, 1, 2, 1, 1)   => roundtrip ? zeros(1, 1, 2) : zeros(1, 1, 2, 1, 1),
        trues(1, 2)            => roundtrip ? fill(true, 1, 2) : trues(1, 2),
    ]
    nprimitives = length(ps)

    # Iteratively build nested containers from primitives and push them to the list
    for _ in 1:nprimitives
        jl1, mx1 = ps[rand(1:end)]
        jl2, mx2 = ps[rand(1:end)]
        jl3, mx3 = ps[rand(1:end)]
        mxdict_12 = mxdict("x" => mx1, "y" => mx2)

        # tuple -> mxtuple
        push!(ps, (jl1, jl2, jl3) => mxtuple(mx1, mx2, mx3))

        # various associative containers => mxdict
        push!(ps, (; x = jl1, y = jl2) => mxdict_12) # named tuple
        push!(ps, pairs((; x = jl1, y = jl2)) => mxdict_12) # pairs iterator
        push!(ps, Dict{String, Any}("x" => jl1, "y" => jl2) => mxdict_12) # dict with string keys
        push!(ps, Dict{Symbol, Any}(:x => jl1, :y => jl2) => mxdict_12) # dict with symbol keys

        # custom types
        if !roundtrip
            push!(ps, A(jl1, jl2) => A(jl1, jl2)) # default `matlabify` falls back to identity
        end
        push!(ps, B(jl1, jl2) => mxdict_12) # custom `matlabify` recursively converts fields
    end

    return map(deepcopy, ps)
end

#### Pretty printing for deeply nested arguments

struct PrettyCompare
    arg1
    arg2
end

function pprint_compare(x, y)
    GarishPrint.pprint(PrettyCompare(x, y); compact = false, limit = false)
    println("")
    return false
end

#### Convenience method for calling and testing `MATDaemon.jlcall`

function wrap_jlcall(f, f_args, f_kwargs, f_output; kwargs...)
    opts = JLCallOptions(;
        f = f,
        workspace = jlcall_workspace(),
        debug = false,
        kwargs...,
    )
    optsfile = joinpath(opts.workspace, MATDaemon.JL_OPTIONS)

    try
        f_args_dict = Dict(:args => f_args, :kwargs => f_kwargs)
        MAT.matwrite(opts.infile, matlabify(f_args_dict))
        MAT.matwrite(optsfile, matlabify(opts))

        @test isfile(opts.infile)
        @test isfile(optsfile)
        @test is_eq(opts, MATDaemon.load_options(opts.workspace))

        Main.include(MATDaemon.jlcall_script())

        @test isfile(opts.outfile)
        @test is_eq(f_output, MAT.matread(opts.outfile)["output"])
    finally
        rm(optsfile; force = true)
        rm(opts.infile; force = true)
        rm(opts.outfile; force = true)
    end
end

#### Convenience method for calling `jlcall.m` via MATLAB.jl

function mx_wrap_jlcall(
        nargout::Int,
        f::String = "(args...; kwargs...) -> nothing",
        f_args::Tuple = (),
        f_kwargs::NamedTuple = NamedTuple();
        kwargs...
    )

    opts = JLCallOptions(;
        f = f,
        workspace = jlcall_workspace(),
        debug = false,
        gc = true,
        port = 5678,
        kwargs...
    )
    optsfile = joinpath(opts.workspace, MATDaemon.JL_OPTIONS)

    mxargs = Any[
        opts.f,
        matlabify(f_args),
        matlabify(f_kwargs),
    ]

    for k in fieldnames(JLCallOptions)
        k === :f && continue
        push!(mxargs, string(k))
        push!(mxargs, getproperty(opts, k))
    end

    f_output = mxcall(:jlcall, nargout, mxargs...)

    @test xor(isfile(optsfile), opts.gc)
    @test xor(isfile(opts.infile), opts.gc)
    @test xor(isfile(opts.outfile), opts.gc)

    return f_output
end

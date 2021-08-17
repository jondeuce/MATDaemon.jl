using Test
using Pkg
using JuliaFromMATLAB
using JuliaFromMATLAB: JLCallOptions, matlabify
using MATLAB
using GarishPrint: pprint

const TEMP_WORKSPACE = mktempdir(; prefix = ".jlcall_", cleanup = true)

function jlcall(
        nargout::Int,
        f::String = "identity",
        f_args::Tuple = (),
        f_kwargs::NamedTuple = (;);
        kwargs...,
    )
    f_opts = JLCallOptions(;
        f         = f,
        args      = matlabify(f_args),
        kwargs    = matlabify(f_kwargs),
        workspace = TEMP_WORKSPACE,
        debug     = false,
        verbose   = false,
        gc        = true,
        kwargs...,
    )
    mxcall(:jlcall, nargout, matlabify(f_opts)...)
end

mxdict(args...) = Dict{String, Any}(args...)

function pprint_compare(args::NamedTuple)
    for (k,v) in pairs(args)
        @info "Argument: $k"
        pprint(v)
        println("")
    end
    return false
end

recurse_is_equal(eq) = (x, y) -> recurse_is_equal(eq, x, y)
recurse_is_equal(eq, x, y) = eq(x, y) #default
recurse_is_equal(eq, x::AbstractDict, y::AbstractDict) = eq(x, y) && all(recurse_is_equal(eq, x[k], y[k]) for k in keys(x))
recurse_is_equal(eq, x::NamedTuple, y::NamedTuple) = eq(x, y) && all(recurse_is_equal(eq, x[k], y[k]) for k in keys(x))

typed_is_equal(eq) = (x, y) -> typed_is_equal(eq, x, y)
typed_is_equal(eq, x, y) = eq(x, y) && typeof(x) == typeof(y)

is_eq(x, y) = recurse_is_equal(typed_is_equal(==), x, y) || pprint_compare((; x, y))
is_eqq(x, y) = recurse_is_equal(typed_is_equal(===), x, y) || pprint_compare((; x, y))

@testset "Basic functionality" begin
    @testset "Null outputs" begin
        for null in [missing, nothing]
            @test is_eqq(jlcall(0, "(args...; kwargs...) -> $(null)", (rand(3), "abc")), nothing)
            @test is_eq(jlcall(1, "(args...; kwargs...) -> $(null)", (rand(3), "abc")), Float64[])
        end
    end
    @testset "Nested keyword args" begin
        for (kws, ret) in [
            (
                a = 1,
                b = "abc",
                c = [1,2],
                d = ones(Float32, 3, 3)
            ) => mxdict(
                "a" => 1,
                "b" => "abc",
                "c" => [1,2],
                "d" => ones(Float32, 3, 3),
            ),
            (
                a = (
                    b = [1.0 2.0],
                    c = (
                        d = trues(2, 2),
                        e = mxdict(
                            "f" => [1.0],
                        ),
                    )
                ),
            ) => mxdict(
                "a" => mxdict(
                    "b" => [1.0 2.0],
                    "c" => mxdict(
                        "d" => fill(true, 2, 2),
                        "e" => mxdict(
                            "f" => 1.0,
                        ),
                    ),
                ),
            )
        ]
            @test is_eq(jlcall(1, "(args...; kwargs...) -> JuliaFromMATLAB.matlabify(kwargs)", (), kws; modules = ["JuliaFromMATLAB"]), ret)
        end
    end
end

@testset "Local environment" begin
    try
        pushfirst!(LOAD_PATH, joinpath(@__DIR__, "TestProject"))
        @test is_eq(jlcall(1, "TestProject.inner", ([1.0 2.0; 3.0 4.0; 5.0 6.0],); project = joinpath(@__DIR__, "TestProject"), modules = ["TestProject"], restart = true), [35.0 44.0; 44.0 56.0])
    finally
        pop!(LOAD_PATH)
    end
end

@testset "Setting threads" begin
    @test is_eq(jlcall(1, "() -> Base.Threads.nthreads()"; threads = 3, restart = true), 3) # Restart julia with --threads=3
    @test is_eq(jlcall(1, "() -> Base.Threads.nthreads()"; threads = 4), 3) # Setting threads shouldn't change active session
end

@testset "Persistent shared environment" begin
    @test is_eq(jlcall(1, "Setup.mul2", ([1,2],); setup = joinpath(@__DIR__, "shared_setup.jl"), restart = true), [2,4])
    @test is_eq(jlcall(1, "Setup.mul2", ([3.0,4.0],)), [6.0,8.0])
    @test is_eq(jlcall(1, "LinearAlgebra.norm", ([3.0,4.0],); modules = ["LinearAlgebra", "Statistics"]), 5.0)
    @test is_eq(jlcall(1, "LinearAlgebra.det", ([1.0 2.0; 3.0 4.0],)), -2.0)
    @test is_eq(jlcall(1, "x -> Statistics.mean(Setup.mul2(x))", ([1.0, 2.0, 3.0],)), 4.0)
end

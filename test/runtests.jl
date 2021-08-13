using Test
using JuliaFromMATLAB
using JuliaFromMATLAB: JLCallOptions, matlabify
using MATLAB

mxcall(:addpath, 0, realpath(joinpath(@__DIR__, "..", "api")))

function jlcall(
        nargout::Int,
        f::String = "identity",
        f_args::Tuple = (),
        f_kwargs::NamedTuple = (;);
        kwargs...,
    )
    f_opts = JLCallOptions(;
        f = f,
        args = matlabify(f_args),
        kwargs = matlabify(f_kwargs),
        workspace = joinpath(@__DIR__, ".jlcall"),
        debug = false,
        verbose = false,
        kwargs...,
    )
    mxcall(:jlcall, nargout, matlabify(f_opts)...)
end

@testset "Setting threads" begin
    @test jlcall(1, "() -> @show Base.Threads.nthreads()"; threads = 3, restart = true) == 3 # Restart julia with --threads=3
    @test jlcall(1, "() -> @show Base.Threads.nthreads()"; threads = 4) == 3 # Setting threads shouldn't change active session
end

@testset "Persistent setup" begin
    @test jlcall(1, "x -> Setup.wrap_print_args(Setup.mul2, x)", ([1,2],); setup = joinpath(@__DIR__, "setup.jl"), restart = true) == [2,4]
    @test jlcall(1, "x -> Setup.wrap_print_args(Setup.mul2, x)", ([3.0,4.0],)) == [6.0,8.0]
end

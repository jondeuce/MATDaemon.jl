using Test
using Pkg
using JuliaFromMATLAB
using JuliaFromMATLAB: JLCallOptions, matlabify
using MATLAB

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
        debug = true,
        verbose = true,
        gc = false,
        kwargs...,
    )
    mxcall(:jlcall, nargout, matlabify(f_opts)...)
end

@testset "Local environment" begin
    # Instantiate local test project
    curr_proj = Base.active_project()
    test_proj = joinpath(@__DIR__, "TestProject")
    Pkg.activate(test_proj)
    Pkg.instantiate()
    Pkg.activate(curr_proj)

    x = [1.0 2.0 3.0; 4.0 5.0 6.0]
    @test jlcall(1, "TestProject.inner", (x,); project = test_proj, modules = ["TestProject"], restart = true) == x'x
end

@testset "Setting threads" begin
    @test jlcall(1, "() -> @show Base.Threads.nthreads()"; threads = 3, restart = true) == 3 # Restart julia with --threads=3
    @test jlcall(1, "() -> @show Base.Threads.nthreads()"; threads = 4) == 3 # Setting threads shouldn't change active session
end

@testset "Persistent shared environment" begin
    @test jlcall(1, "x -> Setup.wrap_print_args(Setup.mul2, x)", ([1,2],); setup = joinpath(@__DIR__, "shared_setup.jl"), restart = true) == [2,4]
    @test jlcall(1, "x -> Setup.wrap_print_args(Setup.mul2, x)", ([3.0,4.0],)) == [6.0,8.0]
    @test jlcall(1, "LinearAlgebra.norm", ([3.0,4.0],); modules = ["LinearAlgebra", "Statistics"]) == 5.0
    @test jlcall(1, "LinearAlgebra.det", ([1.0 2.0; 3.0 4.0],)) == -2.0
    @test jlcall(1, "Statistics.mean", ([1.0, 2.0, 3.0],)) == 2.0
end

@testset "Persistent setup" begin
    @test jlcall(1, "x -> Setup.wrap_print_args(Setup.mul2, x)", ([1,2],); setup = joinpath(@__DIR__, "shared_setup.jl"), restart = true) == [2,4]
    @test jlcall(1, "x -> Setup.wrap_print_args(Setup.mul2, x)", ([3.0,4.0],)) == [6.0,8.0]
end

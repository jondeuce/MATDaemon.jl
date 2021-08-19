using Test
using MATLAB: MEngineError

####
#### Roundtrip testing jlcall.m
####

@testset "Basic functionality" begin
    @testset "Null outputs" begin
        # `Nothing` output is treated specially: MATLAB `varargout` output is empty, requesting output will error
        @test is_eqq(mx_jl_call(0, "() -> nothing"), nothing)
        @test_throws MEngineError mx_jl_call(1, "() -> nothing")

        # `Missing` output corresponds to empty Matrix{Float64}, i.e. with size 0x0
        @test is_eq(mx_jl_call(1, "() -> missing"), zeros(Float64, 0, 0))
    end

    @testset "Nested (kw)args" begin
        for (jl, mx) in [
            (
                a = 1,
                b = "abc",
                c = [1, 2],
                d = ones(Float32, 3, 3)
            ) => mxdict(
                "a" => 1,
                "b" => "abc",
                "c" => [1, 2],
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
                g = zeros(1, 1, 2, 1),
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
                "g" => zeros(1, 1, 2),
            )
        ]
            kwargs = deepcopy(jl)
            ret = deepcopy(mx)
            @test is_eq(mx_jl_call(1, "(args...; kwargs...) -> JuliaFromMATLAB.matlabify(kwargs)", (), kwargs; modules = ["JuliaFromMATLAB"]), ret)

            args = deepcopy(values(jl))
            ret = deepcopy(Any[mx[string(k)] for k in keys(jl)])
            @test is_eq(mx_jl_call(1, "(args...; kwargs...) -> JuliaFromMATLAB.matlabify(args)", args, (;); modules = ["JuliaFromMATLAB"]), ret)
        end
    end
end

@testset "Local environment" begin
    @test is_eq(mx_jl_call(1, "TestProject.inner", ([1.0 2.0; 3.0 4.0; 5.0 6.0],); project = joinpath(@__DIR__, "TestProject"), modules = ["TestProject"], restart = true), [35.0 44.0; 44.0 56.0])
end

@testset "Setting threads" begin
    @test is_eq(mx_jl_call(1, "() -> Base.Threads.nthreads()"; threads = 3, restart = true), 3) # Restart julia with --threads=3
    @test is_eq(mx_jl_call(1, "() -> Base.Threads.nthreads()"; threads = 4), 3) # Setting threads shouldn't change active session
end

@testset "Persistent shared environment" begin
    # Initialize shared environment
    @test is_eqq(mx_jl_call(0; setup = joinpath(@__DIR__, "shared_setup.jl"), shared = true, restart = true), nothing)

    # Call custom library code in persistent stateful environment
    @test is_eq(mx_jl_call(1, "Setup.mul2", ([1, 2],); shared = true), [2, 4])
    @test is_eq(mx_jl_call(1, "Setup.mul2", ([3.0, 4.0],); shared = true), [6.0, 8.0])
    @test is_eq(mx_jl_call(1, "LinearAlgebra.norm", ([3.0, 4.0],); modules = ["LinearAlgebra", "Statistics"], shared = true), 5.0)
    @test is_eq(mx_jl_call(1, "LinearAlgebra.det", ([1.0 2.0; 3.0 4.0],); shared = true), -2.0)
    @test is_eq(mx_jl_call(1, "x -> Statistics.mean(Setup.mul2(x))", ([1.0, 2.0, 3.0],); shared = true), 4.0)
end

@testset "Unique environments" begin
    # Initialize unique environments
    @test is_eqq(mx_jl_call(0; shared = false, restart = true), nothing)

    # Run custom code in each environment, requiring re-initialization each time
    @test is_eq(mx_jl_call(1, "Setup.mul2", ([1, 2],); setup = joinpath(@__DIR__, "shared_setup.jl"), shared = false), [2, 4])
    @test_throws MEngineError mx_jl_call(1, "Setup.mul2", ([1, 2],); shared = false)

    @test is_eq(mx_jl_call(1, "LinearAlgebra.norm", ([3.0, 4.0],); modules = ["LinearAlgebra", "Statistics"], shared = false), 5.0)
    @test_throws MEngineError mx_jl_call(1, "LinearAlgebra.det", ([1.0 2.0; 3.0 4.0],); shared = false)
    @test_throws MEngineError mx_jl_call(1, "x -> Statistics.mean(Setup.mul2(x))", ([1.0, 2.0, 3.0],); shared = false)
end

@testset "Port number" begin
    for port in [2345, 3456]
        @test is_eqq(mx_jl_call(0, "() -> nothing"; port = port, restart = true), nothing)
    end
end

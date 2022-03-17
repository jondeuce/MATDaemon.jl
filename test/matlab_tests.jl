@testset "basic functionality" begin
    @testset "null outputs" begin
        # `Nothing` output is treated specially: MATLAB `varargout` output is empty, requesting output will error
        @test is_eqq(mx_wrap_jlcall(0, "() -> nothing"), nothing)
        @test_throws MEngineError mx_wrap_jlcall(1, "() -> nothing")

        # `Missing` output corresponds to empty Matrix{Float64}, i.e. with size 0x0
        @test is_eq(mx_wrap_jlcall(1, "() -> missing"), zeros(Float64, 0, 0))
    end

    @testset "nested args/kwargs" begin
        ps = deeply_nested_pairs(; roundtrip = true)
        jl_vec = Any[jl for (jl, mx) in ps]
        mx_vec = Any[mx for (jl, mx) in ps]
        jl_dict = Dict{Symbol, Any}(Symbol("k", i) => v for (i, v) in enumerate(jl_vec))
        mx_dict = Dict{String, Any}("k$i" => v for (i, v) in enumerate(mx_vec))

        @test is_eq(mx_wrap_jlcall(length(jl_vec), "(args...; kwargs...) -> args", (jl_vec...,)), (mx_vec...,))
        @test is_eq(mx_wrap_jlcall(1, "(args...; kwargs...) -> kwargs", (), (; jl_dict...,)), mx_dict)
    end
end

@testset "local project" begin
    @test is_eq(mx_wrap_jlcall(1, "TestProject.dot", ([1.0, 2.0, 3.0],); project = jlcall_test_project(), modules = ["TestProject"], restart = true), 14.0)
    @test is_eq(mx_wrap_jlcall(1, "() -> dirname(Base.active_project())"; restart = false), jlcall_test_project())
end

@testset "setting threads" begin
    @test is_eq(mx_wrap_jlcall(1, "() -> Threads.nthreads()"; threads = 3, restart = true), 3) # Restart Julia with --threads=3
    @test is_eq(mx_wrap_jlcall(1, "() -> Threads.nthreads()"; threads = 4), 3) # Setting threads shouldn't change active session
end

@testset "shared server environments" begin
    # Initialize shared server environment
    @test is_eqq(mx_wrap_jlcall(0; setup = joinpath(@__DIR__, "setup.jl"), shared = true, restart = true), nothing)

    # Call custom library code in persistent stateful environment
    @test is_eq(mx_wrap_jlcall(1, "Setup.mul2", ([1, 2],); shared = true), [2, 4])
    @test is_eq(mx_wrap_jlcall(1, "Setup.mul2", ([3.0, 4.0],); shared = true), [6.0, 8.0])
    @test is_eq(mx_wrap_jlcall(1, "LinearAlgebra.norm", ([3.0, 4.0],); modules = ["LinearAlgebra", "Statistics"], shared = true), 5.0)
    @test is_eq(mx_wrap_jlcall(1, "LinearAlgebra.det", ([1.0 2.0; 3.0 4.0],); shared = true), -2.0)
    @test is_eq(mx_wrap_jlcall(1, "x -> Statistics.mean(Setup.mul2(x))", ([1.0, 2.0, 3.0],); shared = true), 4.0)
end

@testset "unique server environments" begin
    # Initialize unique server environments
    @test is_eqq(mx_wrap_jlcall(0; shared = false, restart = true), nothing)

    # Run custom code in each environment, requiring re-initialization each time
    @test is_eq(mx_wrap_jlcall(1, "Setup.mul2", ([1, 2],); setup = joinpath(@__DIR__, "setup.jl"), shared = false), [2, 4])
    @test_throws MEngineError mx_wrap_jlcall(1, "Setup.mul2", ([1, 2],); shared = false)

    @test is_eq(mx_wrap_jlcall(1, "LinearAlgebra.norm", ([3.0, 4.0],); modules = ["LinearAlgebra", "Statistics"], shared = false), 5.0)
    @test_throws MEngineError mx_wrap_jlcall(1, "LinearAlgebra.det", ([1.0 2.0; 3.0 4.0],); shared = false)
    @test_throws MEngineError mx_wrap_jlcall(1, "x -> Statistics.mean(Setup.mul2(x))", ([1.0, 2.0, 3.0],); shared = false)
end

@testset "server-free" begin
    # Run unique local Julia process for each `jlcall`
    @test is_eq(mx_wrap_jlcall(1, "LinearAlgebra.norm", ([3.0, 4.0],); modules = ["LinearAlgebra"], server = false), 5.0)
    @test_throws MEngineError mx_wrap_jlcall(1, "LinearAlgebra.norm", ([3.0, 4.0],); server = false)
end

@testset "port number" begin
    for port in [2345, 3456]
        @test is_eqq(mx_wrap_jlcall(0, "() -> nothing"; port = port, restart = true), nothing)
    end
end

@testset "extending matlabify" begin
    setup_script = tempname() * ".jl"
    open(setup_script; write = true) do io
        println(io, "MATDaemon.matlabify(v::Base.VersionNumber) = string(v)")
    end
    # Note: restart = true is important, as it tests the ability to call dynamically defined `matlabify` methods
    @test is_eq(mx_wrap_jlcall(1, "() -> Base.VERSION"; restart = true, setup = setup_script), string(Base.VERSION))
end

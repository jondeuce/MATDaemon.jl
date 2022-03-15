@testset "matlabify" begin
    for (jl, mx) in deeply_nested_pairs(; roundtrip = false)
        @test is_eq(matlabify(jl), mx)
    end
end

@testset "start/kill server" begin
    # Add two Julia workers; one for running a Julia server, and one for sending the kill signal
    port = 9876
    addprocs(2)
    @everywhere begin
        using Pkg
        Pkg.activate($(Base.active_project()))
        using MATDaemon
    end

    # Start a DaemonMode server on worker 2
    server_task = @spawnat 2 MATDaemon.start(port; shared = true, verbose = true)

    # Wait until server is running
    server_running = false
    while !server_running
        @test MATDaemon.DaemonMode.runexpr("@eval Main __SERVER_RUNNING__() = :SERVER_RUNNING"; port = port) === nothing
        server_running = fetch(@spawnat 2 isdefined(Main, :__SERVER_RUNNING__))
        sleep(1.0)
    end

    # Kill server and cleanup process
    @test fetch(@spawnat 3 MATDaemon.kill(port; verbose = true)) === nothing
    @test fetch(rmprocs(3)) === nothing

    # Ensure server task has completed and cleanup process
    @test fetch(server_task) === nothing
    @test fetch(rmprocs(2)) === nothing

    # Killing a nonexistent server should be a no-op
    @test MATDaemon.kill(port; verbose = true) === nothing
end

@testset "jlcall" begin
    # Test jlcall, ensuring that function definitions don't leak into Main
    for (i, (f, f_args, f_kwargs, f_output, kwargs)) in enumerate([
        ("f1(x) = LinearAlgebra.norm(x)",    mxtuple([3.0, 4.0]),    mxdict(),           mxtuple(5.0),           (modules = ["LinearAlgebra"],)),
        ("f2(x; y) = x*y",                   mxtuple(5.0),           mxdict("y" => 3),   mxtuple(15.0),          NamedTuple()),
        ("f3() = nothing",                   mxtuple(),              mxdict(),           mxtuple(),              NamedTuple()),
        ("f4() = missing",                   mxtuple(),              mxdict(),           mxtuple(mxempty()),     NamedTuple()),
    ])
        wrap_jlcall(f, f_args, f_kwargs, f_output; kwargs...)
        @test !isdefined(Main, Symbol(:f, i))
    end

    # Test jlcall, explicitly adding methods to Main
    for (f_sym, f_str, f_args, f_kwargs, f_output, kwargs) in [
        (:f5, "@eval Main f5(x,y) = (x,y)",         mxtuple("one", 2),      mxdict(),           mxtuple("one", 2),      NamedTuple()),
        (:f6, "@eval Main f6(x,y) = x*y",           mxtuple(3.0, 2),        mxdict(),           mxtuple(6.0),           NamedTuple()),
        (:f7, "@eval Main f7(x,y) = [x*y]",         mxtuple(3.0, 2),        mxdict(),           mxtuple(6.0),           NamedTuple()),
        (:f8, "@eval Main f8(x,y) = [x,y]",         mxtuple(3.0, 2.0),      mxdict(),           mxtuple([3.0, 2.0]),    NamedTuple()),
        (:f9, "@eval Main f9(x) = Setup.mul2(x)",   mxtuple([2f0 3f0]),     mxdict(),           mxtuple([4f0 6f0]),     (setup = joinpath(@__DIR__, "setup.jl"), project = jlcall_test_project())),
    ]
        wrap_jlcall(f_str, f_args, f_kwargs, f_output; kwargs...)
        @test isdefined(Main, f_sym)
    end

    # This should fail, as Base.VERSION has type VersionNumber and therefore cannot be written to .mat
    @test_throws LoadError wrap_jlcall("@eval Main f10() = Base.VERSION", mxtuple(), mxdict(), mxtuple(string(Base.VERSION)))
    @test isdefined(Main, :f10)

    # Fix `f10` by extending `matlabify` to `VersionNumber`s
    MATDaemon.matlabify(v::Base.VersionNumber) = string(v)
    wrap_jlcall("Main.f10", mxtuple(), mxdict(), mxtuple(string(Base.VERSION)))
end

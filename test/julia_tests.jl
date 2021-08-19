using Test
using Base.Iterators: Pairs
using Distributed
using JuliaFromMATLAB
using JuliaFromMATLAB: DaemonMode, JLCallOptions, jlcall, matlabify
using MAT

struct A
    x
    y
end
recurse_is_equal(eq, x::A, y::A) = recurse_is_equal(eq, x.x, y.x) && recurse_is_equal(eq, x.y, y.y)

struct B
    x
    y
end
recurse_is_equal(eq, x::B, y::B) = recurse_is_equal(eq, x.x, y.x) && recurse_is_equal(eq, x.y, y.y)

JuliaFromMATLAB.matlabify(b::B) = mxdict("x" => matlabify(b.x), "y" => matlabify(b.y))

@testset "matlabify" begin
    for (jl, mx) in [
        nothing             => mxempty(),
        missing             => mxempty(),
        (1, "two", :three)  => mxtuple(1, "two", "three"),
        Dict(:a => 1)       => mxdict("a" => 1),
        (a = 1.0, b = 2)    => mxdict("a" => 1.0, "b" => 2),
        pairs((a = "one",)) => mxdict("a" => "one"),
        A(1//2, big"3")     => A(1//2, big"3"),
        B(1.0, (2, :three)) => mxdict("x" => 1.0, "y" => mxtuple(2, "three")),
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
                        "f" => 1.0,
                    ),
                )
            ),
            g = Dict(:h => zeros(1, 1, 2, 1)),
        ) => mxdict(
            "a" => mxdict(
                "b" => [1.0 2.0],
                "c" => mxdict(
                    "d" => trues(2, 2),
                    "e" => mxdict(
                        "f" => 1.0,
                    ),
                ),
            ),
            "g" => mxdict("h" => zeros(1, 1, 2, 1)),
        )
    ]
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
        using JuliaFromMATLAB
    end

    # Start a DaemonMode server on worker 2
    server_task = @spawnat 2 JuliaFromMATLAB.start(port; shared = true, verbose = true)

    # Wait until server is running
    server_running = false
    while !server_running
        @test DaemonMode.runexpr("@eval Main __SERVER_RUNNING__() = :SERVER_RUNNING"; port = port) === nothing
        server_running = fetch(@spawnat 2 isdefined(Main, :__SERVER_RUNNING__))
        sleep(1.0)
    end

    # Kill server and cleanup process
    @test fetch(@spawnat 3 JuliaFromMATLAB.kill(port; verbose = true)) === nothing
    @test fetch(rmprocs(3)) === nothing

    # Ensure server task has completed and cleanup process
    @test fetch(server_task) === nothing
    @test fetch(rmprocs(2)) === nothing

    # Killing a nonexistent server should be a no-op
    @test JuliaFromMATLAB.kill(port; verbose = true) === nothing
end

@testset "jlcall" begin
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
        @test is_eq(opts, JLCallOptions(input_file))

        jlcall(Main; workspace = opts.workspace)

        @test isfile(output_file)
        @test is_eq(f_output, MAT.matread(output_file)["output"])

        rm(input_file; force = true)
        rm(output_file; force = true)
    end

    # This should fail, as Base.VERSION has type VersionNumber and therefore cannot be written to .mat
    @test_throws ErrorException wrap_jlcall("f0() = Base.VERSION", mxtuple(), mxdict(), mxtuple(string(Base.VERSION)))
    @test isdefined(Main, :f0)

    # Fix `f0` by extending `matlabify` to `VersionNumber`s
    JuliaFromMATLAB.matlabify(v::Base.VersionNumber) = string(v)
    wrap_jlcall("f0", mxtuple(), mxdict(), mxtuple(string(Base.VERSION)))

    # Test various combinations of expected jlcall inputs and outputs
    for (i, (f, f_args, f_kwargs, f_output, kwargs)) in enumerate([
        ("f1(x) = 2x",              mxtuple(3),         mxdict(),           mxtuple(6),          NamedTuple()),
        ("f2(x; y) = x*y",          mxtuple(5.0),       mxdict("y" => 3),   mxtuple(15.0),       NamedTuple()),
        ("f3() = nothing",          mxtuple(),          mxdict(),           mxtuple(),           NamedTuple()),
        ("f4() = missing",          mxtuple(),          mxdict(),           mxtuple(mxempty()),  NamedTuple()),
        ("f5(x,y) = (x,y)",         mxtuple("one", 2),  mxdict(),           mxtuple("one", 2),   NamedTuple()),
        ("f6(x,y) = x*y",           mxtuple(3.0, 2),    mxdict(),           mxtuple(6.0),        NamedTuple()),
        ("f7(x,y) = [x*y]",         mxtuple(3.0, 2),    mxdict(),           mxtuple(6.0),        NamedTuple()),
        ("f8(x,y) = [x,y]",         mxtuple(3.0, 2.0),  mxdict(),           mxtuple([3.0, 2.0]), NamedTuple()),
        ("f9(x) = Setup.mul2(x)",   mxtuple([2f0 3f0]), mxdict(),           mxtuple([4f0 6f0]),  (setup = "setup.jl", project = "TestProject")),
    ])
        wrap_jlcall(f, f_args, f_kwargs, f_output; kwargs...)
        @test isdefined(Main, Symbol(:f, i))
    end

end

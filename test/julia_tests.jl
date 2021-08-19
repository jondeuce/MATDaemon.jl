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
Base.:(==)(a1::A, a2::A) = a1.x == a2.x && a1.y == a2.y

struct B
    x
    y
end
Base.:(==)(b1::B, b2::B) = b1.x == b2.x && b1.y == b2.y

JuliaFromMATLAB.matlabify(b::B) = mxdict(
    "x" => matlabify(b.x),
    "y" => matlabify(b.y),
)

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
    local port = rand(9000:9999)

    # Add two Julia workers; one for running a Julia server, and one for sending the kill signal
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
    function wrap_call(f, args, kwargs, output)
        opts = JLCallOptions(;
            f         = f,
            args      = args,
            kwargs    = kwargs,
            workspace = initialize_workspace(),
            debug     = true,
        )
        input_file = joinpath(opts.workspace, JuliaFromMATLAB.JL_INPUT)
        output_file = joinpath(opts.workspace, JuliaFromMATLAB.JL_OUTPUT)

        MAT.matwrite(input_file, mxdict(string(k) => matlabify(getproperty(opts, k)) for k in fieldnames(typeof(opts))))
        @test isfile(input_file)
        @test opts == JLCallOptions(input_file)

        jlcall(Main; workspace = opts.workspace)

        @test isfile(output_file)
        @test output == MAT.matread(output_file)["output"]

        rm(input_file; force = true)
        rm(output_file; force = true)
    end

    for (i, (f, args, kwargs, output)) in enumerate([
        ("f1(x) = 2x",      mxtuple(3),         mxdict(),           mxtuple(6)),
        ("f2(x; y) = x*y",  mxtuple(5.0),       mxdict("y" => 3),   mxtuple(15.0)),
        ("f3() = nothing",  mxtuple(),          mxdict(),           mxtuple()),
        ("f4() = missing",  mxtuple(),          mxdict(),           mxtuple(mxempty())),
        ("f5(x,y) = (x,y)", mxtuple("one", 2),  mxdict(),           mxtuple("one", 2)),
        ("f6(x,y) = x*y",   mxtuple(3.0, 2),    mxdict(),           mxtuple(6.0)),
        ("f7(x,y) = [x*y]", mxtuple(3.0, 2),    mxdict(),           mxtuple(6.0)),
        ("f8(x,y) = [x,y]", mxtuple(3.0, 2.0),  mxdict(),           mxtuple([3.0, 2.0])),
    ])
        wrap_call(f, args, kwargs, output)
        @test isdefined(Main, Symbol(:f, i))
    end

end

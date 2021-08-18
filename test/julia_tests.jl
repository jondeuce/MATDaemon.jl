using Test
using Base.Iterators: Pairs
using Distributed
using JuliaFromMATLAB
using JuliaFromMATLAB: DaemonMode, JLCallOptions, matlabify

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

@testset "Start/kill server" begin
    local port = rand(9000:9999)

    # Add two Julia workers; one for running a Julia server, and one for sending the kill signal
    nprocs = 2
    addprocs(nprocs; exeflags = ["--project=$(Base.active_project())", "--threads=$(Threads.nthreads())"])
    @everywhere using JuliaFromMATLAB

    # Start a DaemonMode server on worker 2
    server_task = @spawnat 2 JuliaFromMATLAB.start(port; shared = true, verbose = true)

    # Wait until server is running
    server_running = false
    while !server_running
        @test DaemonMode.runexpr("@eval Main __SERVER_RUNNING__() = :SERVER_RUNNING"; port) === nothing
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

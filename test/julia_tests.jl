@testset "code quality (Aqua.jl)" begin
    # TODO: Dependency compat bounds should be tested, but currently[1] there is an issue with how to specify bounds for standard libraries
    #   [1] https://discourse.julialang.org/t/psa-compat-requirements-in-the-general-registry-are-changing/104958#update-november-9th-2023-2
    Aqua.test_all(MATDaemon; deps_compat = false)
end

@testset "version numbers" begin
    project_toml = TOML.parsefile(joinpath(@__DIR__, "..", "Project.toml"))
    jlcall_jl = readchomp(joinpath(@__DIR__, "..", "api", "jlcall.jl"))
    jlcall_m = readchomp(joinpath(@__DIR__, "..", "api", "jlcall.m"))
    readme_md = readchomp(joinpath(@__DIR__, "..", "README.md"))
    index_md = readchomp(joinpath(@__DIR__, "..", "docs", "src", "index.md"))

    version = VersionNumber(project_toml["version"])
    @test MATDaemon.VERSION == version
    @test contains(jlcall_jl, "was written for MATDaemon v$(version)")
    @test contains(jlcall_m, "was written for MATDaemon v$(version)")
    @test contains(jlcall_m, "addParameter(p, 'VERSION', '$(version)'")
    for md in [readme_md, index_md]
        matches = eachmatch(r"jondeuce/MATDaemon\.jl/blob/v(?<version>\d\.\d\.\d)/api/jlcall\.m", md)
        @test !isempty(matches) && all(VersionNumber(m["version"]) == version for m in matches)
    end
end

@testset "download jlcall.m" begin
    # Download from github
    jlcall_path = tempname() * ".m"
    download_jlcall(jlcall_path; latest = true)
    @test isfile(jlcall_path)

    # Copy from api folder
    download_jlcall(jlcall_path; force = true)
    jlcall_local = normpath(@__DIR__, "../api/jlcall.m")
    @test readlines(jlcall_path) == readlines(jlcall_local)
end

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
        Pkg.activate($(Base.active_project()); io = devnull)
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
        ("f1(x) = LinearAlgebra.norm(x)",    mxtuple([3.0, 4.0]),    mxdict(),           mxtuple(5.0),           (; modules = ["LinearAlgebra"],)),
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
        (:f9, "@eval Main f9(x) = Setup.mul2(x)",   mxtuple([2f0 3f0]),     mxdict(),           mxtuple([4f0 6f0]),     (; setup = joinpath(@__DIR__, "setup.jl"),)),
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

    # Check that `jlcall` warns user if called with wrong `jlcall.m` version number, but still tries to run
    wrap_jlcall("x -> 2x", mxtuple(1), mxdict(), mxtuple(2); VERSION = "0.0.0")

    # Test local project
    reset_active_project() do
        wrap_jlcall("@eval Main f11 = TestProject.dot", mxtuple([1.0, 2.0, 3.0]), mxdict(), mxtuple(14.0); project = jlcall_test_project(), modules = ["TestProject"])
        @test dirname(Base.active_project()) == jlcall_test_project()
    end
    @test isdefined(Main, :f11)
end

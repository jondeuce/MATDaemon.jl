using Pkg
using JuliaFromMATLAB: JLCallOptions, matlabify
using MATLAB: mxcall

#### Misc. utils

mxdict(args...) = Dict{String, Any}(args...)
mxtuple(args...) = Any[args...]

#### Wrapper for calling jlcall.m via MATLAB.jl

const TEMP_WORKSPACE = mktempdir(; prefix = ".jlcall_", cleanup = true)

function jlcall(
        nargout::Int,
        f::String = "(args...; kwargs...) -> nothing",
        f_args::Tuple = (),
        f_kwargs::NamedTuple = (;);
        kwargs...,
    )

    if !isfile(joinpath(TEMP_WORKSPACE, "Project.toml"))
        curr = Base.active_project()
        Pkg.activate(TEMP_WORKSPACE; io = devnull)
        Pkg.develop(; path = normpath(joinpath(@__DIR__, "..")), io = devnull)
        Pkg.activate(curr; io = devnull)
    end

    f_opts = JLCallOptions(;
        f         = f,
        args      = matlabify(f_args),
        kwargs    = matlabify(f_kwargs),
        workspace = TEMP_WORKSPACE,
        debug     = false,
        verbose   = false,
        gc        = true,
        port      = 1234,
        kwargs...,
    )

    mxcall(:jlcall, nargout, matlabify(f_opts)...)
end

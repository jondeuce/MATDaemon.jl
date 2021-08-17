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
    f_opts = JLCallOptions(;
        f         = f,
        args      = matlabify(f_args),
        kwargs    = matlabify(f_kwargs),
        workspace = TEMP_WORKSPACE,
        debug     = false,
        verbose   = false,
        gc        = true,
        kwargs...,
    )
    mxcall(:jlcall, nargout, matlabify(f_opts)...)
end

using Pkg
using JuliaFromMATLAB: JLCallOptions, matlabify
using MATLAB: mxcall

#### Wrapper for calling jlcall.m via MATLAB.jl

function mx_jl_call(
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
        workspace = initialize_workspace(),
        debug     = false,
        gc        = true,
        port      = 1234,
        kwargs...,
    )

    mxcall(:jlcall, nargout, matlabify(f_opts)...)
end

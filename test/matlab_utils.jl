using Pkg
using JuliaFromMATLAB: JLCallOptions, matlabify
using MATLAB: mxcall

#### Wrapper for calling jlcall.m via MATLAB.jl

function mx_jl_call(
        nargout::Int,
        f::String = "(args...; kwargs...) -> nothing",
        f_args::Tuple = (),
        f_kwargs::NamedTuple = NamedTuple();
        kwargs...,
    )

    opts = JLCallOptions(;
        f         = f,
        args      = matlabify(f_args),
        kwargs    = matlabify(f_kwargs),
        workspace = initialize_workspace(),
        debug     = false,
        gc        = true,
        port      = 1234,
        kwargs...,
    )

    mx_args = Any[opts.f, opts.args, opts.kwargs]
    for k in fieldnames(JLCallOptions)
        k ∈ (:f, :args, :kwargs) && continue
        push!(mx_args, string(k))
        push!(mx_args, getproperty(opts, k))
    end

    mxcall(:jlcall, nargout, mx_args...)
end

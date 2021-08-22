#### Wrapper for calling jlcall.m via MATLAB.jl

function mx_wrap_jlcall(
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
        debug     = true,
        gc        = true,
        port      = 5678,
        kwargs...,
    )

    mxargs = Any[opts.f, opts.args, opts.kwargs]
    for k in fieldnames(JLCallOptions)
        k ∈ (:f, :args, :kwargs) && continue
        push!(mxargs, string(k))
        push!(mxargs, getproperty(opts, k))
    end

    f_output = mxcall(:jlcall, nargout, mxargs...)

    input_file = joinpath(opts.workspace, JuliaFromMATLAB.JL_INPUT)
    output_file = joinpath(opts.workspace, JuliaFromMATLAB.JL_OUTPUT)
    @test xor(isfile(input_file), opts.gc)
    @test xor(isfile(output_file), opts.gc)

    return f_output
end

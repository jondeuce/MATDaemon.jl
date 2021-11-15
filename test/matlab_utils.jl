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
        workspace = initialize_workspace(),
        debug     = true,
        gc        = true,
        port      = 5678,
        kwargs...,
    )
    optsfile = joinpath(opts.workspace, MATDaemon.JL_OPTIONS)

    mxargs = Any[
        opts.f,
        matlabify(f_args),
        matlabify(f_kwargs),
    ]

    for k in fieldnames(JLCallOptions)
        k === :f && continue
        push!(mxargs, string(k))
        push!(mxargs, getproperty(opts, k))
    end

    f_output = mxcall(:jlcall, nargout, mxargs...)

    @test xor(isfile(optsfile), opts.gc)
    @test xor(isfile(opts.infile), opts.gc)
    @test xor(isfile(opts.outfile), opts.gc)

    return f_output
end

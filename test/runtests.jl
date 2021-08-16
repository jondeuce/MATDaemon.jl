try
    @eval using MATLAB

    # Add jlcall.m to MATLAB path
    mxcall(:addpath, 0, realpath(joinpath(@__DIR__, "..", "api")))

    # Run MATLAB tests
    include(joinpath(@__DIR__, "matlab.jl"))
catch e
    @warn "`using MATLAB` failed; skipping MATLAB tests" exception=(e, catch_backtrace())
end

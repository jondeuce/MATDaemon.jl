# Try loading MATLAB before running tests
RUN_MATLAB_TESTS = false
try
    # Try loading MATLAB and adding jlcall.m to the MATLAB load path
    @eval using MATLAB
    mxcall(:addpath, 0, realpath(joinpath(@__DIR__, "..", "api")))
    global RUN_MATLAB_TESTS = true

catch e
    @warn "`using MATLAB` failed; skipping MATLAB tests" exception=(e, catch_backtrace())
end

if RUN_MATLAB_TESTS
    include(joinpath(@__DIR__, "matlab.jl"))
end

# Try loading MATLAB before running MATLAB tests
RUN_MATLAB_TESTS = false
try
    # Try loading MATLAB and adding jlcall.m to the MATLAB load path
    @eval using MATLAB: mxcall
    mxcall(:addpath, 0, realpath(joinpath(@__DIR__, "..", "api")))
    global RUN_MATLAB_TESTS = true

catch e
    @warn "`import MATLAB` failed; skipping MATLAB tests" exception=(e, catch_backtrace())
end

if RUN_MATLAB_TESTS
    include("utils.jl")
    include("matlab_utils.jl")
    include("matlab_tests.jl")
end

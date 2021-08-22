using Test
using JuliaFromMATLAB
using JuliaFromMATLAB: JLCallOptions, @jlcall, matlabify

using Distributed
using GarishPrint
using MAT
using Pkg

# Try loading MATLAB
RUN_MATLAB_TESTS = false
try
    @eval using MATLAB: MEngineError, mxcall
    mxcall(:addpath, 0, realpath(joinpath(@__DIR__, "..", "api")))
    global RUN_MATLAB_TESTS = true
catch e
    @warn "`import MATLAB` failed; skipping MATLAB tests" exception=(e, catch_backtrace())
end

#### Julia tests

include("utils.jl")
include("julia_tests.jl")

#### MATLAB tests

if RUN_MATLAB_TESTS
    include("matlab_utils.jl")
    include("matlab_tests.jl")
end

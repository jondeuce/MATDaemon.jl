"""
    JuliaFromMATLAB

Utilities module for calling Julia from MATLAB.
"""
module JuliaFromMATLAB

import DaemonMode
import MAT
import MacroTools
import Pkg

# Input/output filenames for communication with MATLAB
const JL_INPUT = "jl_input.mat"
const JL_OUTPUT = "jl_output.mat"

"""
    matlabify(x)

Convert Julia value `x` to equivalent MATLAB representation
"""
matlabify(x) = x # default
matlabify(::Nothing) = zeros(Float64, 0, 0) # represent `Nothing` as MATLAB's `[]`
matlabify(::Missing) = zeros(Float64, 0, 0) # represent `Missing` as MATLAB's `[]`
matlabify(x::Symbol) = string(x)
matlabify(xs::Tuple) = matlabify_iterable(xs)
matlabify(xs::Union{<:AbstractDict, <:NamedTuple, <:Base.Iterators.Pairs}) = matlabify_pairs(xs)

matlabify_iterable(xs) = Any[matlabify(x) for x in xs]
matlabify_pairs(xs) = Dict{String, Any}(string(k) => matlabify(v) for (k, v) in pairs(xs))

matlabify_output(x) = Any[matlabify(x)] # default
matlabify_output(::Nothing) = Any[]
matlabify_output(x::Tuple) = Any[map(matlabify, x)...]

juliafy_kwargs(xs) = Pair{Symbol, Any}[Symbol(k) => v for (k, v) in xs]

"""
    JLCallOptions

Julia struct for storing jlcall.m input parser results
"""
Base.@kwdef struct JLCallOptions
    f::String                 = "(args...; kwargs...) -> nothing"
    args::Vector{Any}         = Any[]
    kwargs::Dict{String, Any} = Dict{String, Any}()
    runtime::String           = abspath(Base.Sys.BINDIR, "julia")
    project::String           = ""
    threads::Int              = Base.Threads.nthreads()
    setup::String             = ""
    modules::Vector{Any}      = Any[]
    cwd::String               = pwd()
    workspace::String         = mktempdir(; prefix = ".jlcall_", cleanup = true)
    server::Bool              = true
    port::Int                 = 3000
    shared::Bool              = true
    restart::Bool             = false
    gc::Bool                  = true
    debug::Bool               = false
end

matlabify(opts::JLCallOptions) = Dict{String, Any}(string(k) => matlabify(getproperty(opts, k)) for k in fieldnames(JLCallOptions))

"""
    start(port::Int; shared::Bool, verbose::Bool = false)

Start Julia server.
"""
function start(port::Int; shared::Bool, verbose::Bool = false)
    DaemonMode.serve(port, shared; print_stack = true, async = true, threaded = false)
    verbose && println("* Julia server started\n")
    return nothing
end

"""
    kill(port::Int; verbose::Bool = false)

Kill Julia server. If server is already killed, do nothing.
"""
function kill(port::Int; verbose::Bool = false)
    try
        DaemonMode.sendExitCode(port)
        verbose && println("* Julia server killed\n")
    catch e
        if (e isa Base.IOError)
            #TODO: Check for proper error code:
            #   on linux: abs(e.code) == abs(Libc.ECONNREFUSED)
            #   on windows: ?
            verbose && println("* Julia server inactive; nothing to kill\n")
        else
            rethrow()
        end
    end
    return nothing
end

"""
    load_options(workspace::String)

Load jlcall.m input parser results from `workspace`
"""
function load_options(workspace::String)
    maybevec(x) = x isa AbstractArray ? vec(x) : x
    mxopts = MAT.matread(abspath(workspace, JL_INPUT))
    kwargs = Dict{Symbol, Any}(Symbol(k) => maybevec(v) for (k, v) in mxopts)
    return JLCallOptions(; kwargs..., workspace = abspath(workspace))
end

"""
    init_environment(opts::JLCallOptions)

Initialize jlcall environment.
"""
function init_environment(opts::JLCallOptions)
    # Change to current MATLAB working directory
    cd(abspath(opts.cwd))

    # Push user project onto top of load path
    if !isempty(opts.project) && abspath(opts.project) ∉ LOAD_PATH
        pushfirst!(LOAD_PATH, abspath(opts.project))
    end

    # Push workspace into back of load path
    if abspath(opts.workspace) ∉ LOAD_PATH
        push!(LOAD_PATH, abspath(opts.workspace))
    end

    return nothing
end

"""
    save_output(output, opts::JLCallOptions)

Save jlcall output results into workspace
"""
function save_output(output, opts::JLCallOptions)
    # Save outputs to workspace
    output_file = abspath(opts.workspace, JL_OUTPUT)

    try
        MAT.matwrite(output_file, Dict{String, Any}("output" => output))
    catch e
        println("* ERROR: Unable to write Julia output to .mat:\n*   ", output_file, "\n")
        rm(output_file; force = true)
        rethrow()
    end

    return nothing
end

"""
    jlcall(f, opts::JLCallOptions)

Run Julia function `f` using jlcall.m input parser results `opts`.
"""
function jlcall(f::F, opts::JLCallOptions) where {F}
    # Since `f` is dynamically defined in a global scope, try to force specialization on `f` (may help performance)
    out = f(opts.args...; juliafy_kwargs(opts.kwargs)...)
    return matlabify_output(out)
end

"""
    jlcall_script()

Location of script for loading code, importing modules, and evaluating the function expression passed from jlcall.m.
"""
jlcall_script() = joinpath(@__DIR__, "..", "api", "jlcall.jl")

end # module JuliaFromMATLAB

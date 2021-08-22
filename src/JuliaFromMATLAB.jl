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
Convert Julia value to equivalent MATLAB representation
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

# Convert MATLAB values to equivalent Julia representation
juliafy_kwargs(xs) = Pair{Symbol, Any}[Symbol(k) => v for (k, v) in xs]

"""
Julia struct for storing jlcall.m input parser results
"""
Base.@kwdef struct JLCallOptions
    f::String                 = "(args...; kwargs...) -> nothing"
    args::Vector{Any}         = Any[]
    kwargs::Dict{String, Any} = Dict{String, Any}()
    julia::String             = abspath(Base.Sys.BINDIR, "julia")
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
Start Julia server.
"""
function start(port::Int; shared::Bool, verbose::Bool = false)
    DaemonMode.serve(port, shared; print_stack = true, async = true, threaded = false)
    verbose && println("* Julia server started\n")
    return nothing
end

"""
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
Load jlcall.m input parser results from `workspace`
"""
function load_options(workspace::String)
    maybevec(x) = x isa AbstractArray ? vec(x) : x
    mxopts = MAT.matread(abspath(workspace, JL_INPUT))
    kwargs = Dict{Symbol, Any}(Symbol(k) => maybevec(v) for (k, v) in mxopts)
    return JLCallOptions(; kwargs..., workspace = abspath(workspace))
end

"""
Initialize jlcall environment.
"""
function init_environment(opts::JLCallOptions)
    # Change to current matlab working directory
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
Save jlcall output results into `workspace`
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
Run Julia function `f` using jlcall.m input parser results `opts`.
"""
function jlcall(f::F, opts::JLCallOptions) where {F}
    out = f(opts.args...; juliafy_kwargs(opts.kwargs)...)
    return matlabify_output(out)
end

"""
Build script for calling jlcall
"""
macro jlcall(workspace)
    esc(quote
        # Input is workspace directory containing jlcall.m input parser results
        local opts = $(load_options)($(workspace))

        # Initialize load path etc.
        $(init_environment)(opts)

        # Print environment for debugging
        if opts.debug
            println("* Environment for evaluating Julia expression:")
            println("*   Working dir: $(pwd())")
            println("*   Module: $(@__MODULE__)")
            println("*   Load path: $(LOAD_PATH)\n")
        end

        # JuliaFromMATLAB is always imported
        import JuliaFromMATLAB

        # Include setup code
        if !isempty(opts.setup)
            include(abspath(opts.setup))
        end

        # Load modules from strings; will fail if not installed (see: https://discourse.julialang.org/t/how-to-include-into-local-scope/34634/11)
        for mod_str in opts.modules
            Core.eval($(__module__), Meta.parse("quote; import $(mod_str); end").args[1])
        end

        # Parse and evaluate `f` from string (see: https://discourse.julialang.org/t/how-to-include-into-local-scope/34634/11)
        local f_expr = Meta.parse("quote; let; $(opts.f); end; end").args[1]

        if opts.debug
            println("* Generated Julia function expression: ")
            println(string($(MacroTools.prettify)(f_expr)), "\n")
        end

        local f = Core.eval($(__module__), f_expr)

        # Call `f` using MATLAB input arguments
        local output = $(jlcall)(f, opts)

        # Save results to workspace
        $(save_output)(output, opts)
    end)
end

# Generate tempnames with numbered prefix for easier debugging
const jlcall_tempname_count = Ref(0)

function jlcall_tempname(parent::String)
    tmp = lpad(jlcall_tempname_count[], 4, '0') * "_" * basename(tempname())
    jlcall_tempname_count[] = mod(jlcall_tempname_count[] + 1, 10_000)
    return abspath(parent, tmp)
end

end # module JuliaFromMATLAB

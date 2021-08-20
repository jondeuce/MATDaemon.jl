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

function JLCallOptions(mxfile::String; kwargs...)
    maybevec(x) = x isa AbstractArray ? vec(x) : x
    opts = Dict{Symbol, Any}(Symbol(k) => maybevec(v) for (k, v) in MAT.matread(mxfile))
    JLCallOptions(; opts..., kwargs...)
end

function matlabify(opts::JLCallOptions)
    return Dict{String, Any}(string(k) => matlabify(getproperty(opts, k)) for k in fieldnames(JLCallOptions))
end

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
Print prettified expression to `io`.
"""
prettyln(io, ex) = println(io, string(MacroTools.prettify(ex)))

"""
Build script for calling jlcall
"""
function build_jlcall_script(opts::JLCallOptions)

    # Build temporary julia script
    jlcall_script = jlcall_tempname(mkpath(abspath(opts.workspace, "tmp"))) * ".jl"

    open(jlcall_script; write = true) do io

        # Change to current matlab working directory
        prettyln(io, quote
            cd($(abspath(opts.cwd)))
        end)

        # Push user project onto top of load path
        if !isempty(opts.project)
            prettyln(io, quote
                if $(abspath(opts.project)) ∉ LOAD_PATH
                    pushfirst!(LOAD_PATH, $(abspath(opts.project)))
                end
            end)
        end

        # Push workspace into back of load path
        prettyln(io, quote
            if $(abspath(opts.workspace)) ∉ LOAD_PATH
                push!(LOAD_PATH, $(abspath(opts.workspace)))
            end
        end)

        # Print environment for debugging
        if opts.debug
            prettyln(io, quote
                println("* Environment for evaluating Julia expression:")
                println("*   Directory: $(pwd())")
                println("*   Module: $(@__MODULE__)")
                println("*   Load path: $(LOAD_PATH)\n")
            end)
        end

        # JuliaFromMATLAB is always imported
        prettyln(io, quote
            import JuliaFromMATLAB
        end)

        # Include setup code
        if !isempty(opts.setup)
            prettyln(io, quote
                include($(abspath(opts.setup)))
            end)
        end

        # Load modules; will fail if not installed
        for mod in opts.modules
            prettyln(io, quote
                import $(Meta.parse(mod))
            end)
        end

        # Call jlcall
        prettyln(io, quote
            JuliaFromMATLAB.jlcall(
                let
                    # See: https://discourse.julialang.org/t/how-to-include-into-local-scope/34634/11?u=jondeuce
                    $(Meta.parse("quote; $(opts.f); end").args[1])
                end;
                workspace = $(abspath(opts.workspace))
            )
        end)

    end

    # Print generated file
    if opts.debug
        println("* Generated Julia script:")
        println("*   $(jlcall_script)\n")
        println(readchomp(jlcall_script) * "\n")
    end

    return jlcall_script
end

"""
Run Julia function `f`, loading jlcall.m input parser results from `workspace`
"""
function jlcall(f; workspace::String)
    # Load input parser results from workspace
    opts = JLCallOptions(abspath(workspace, JL_INPUT); workspace = abspath(workspace))
    jlcall(f, opts)
end

"""
Run Julia function `f` using jlcall.m input parser results `opts`.
"""
function jlcall(f, opts::JLCallOptions)
    # Evaluate expression and call returned function
    output = f(opts.args...; juliafy_kwargs(opts.kwargs)...)
    output =
        output isa Nothing ? Any[] :
        output isa Tuple   ? Any[map(matlabify, output)...] :
        Any[matlabify(output)]

    # Save outputs
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

# Generate tempnames with numbered prefix for easier debugging
const jlcall_tempname_count = Ref(0)

function jlcall_tempname(parent::String)
    tmp = lpad(jlcall_tempname_count[], 4, '0') * "_" * basename(tempname())
    jlcall_tempname_count[] = mod(jlcall_tempname_count[] + 1, 10_000)
    return abspath(parent, tmp)
end

end # module JuliaFromMATLAB

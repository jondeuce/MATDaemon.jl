"""
    JuliaFromMATLAB

Utilities module for calling Julia from MATLAB.
"""
module JuliaFromMATLAB

import DaemonMode
import MAT
import MacroTools
import Pkg

# Server port number. This can be changed to any valid port
const JL_INPUT = "jl_input.mat"
const JL_OUTPUT = "jl_output.mat"

# Convert Julia values to Matlab representation
matlabify(x) = error("Undefined conversion to Matlab type for: $(typeof(x))") # default
matlabify(x::Number) = x
matlabify(x::AbstractArray) = x
matlabify(x::Bool) = x
matlabify(x::String) = x
matlabify(::Nothing) = Any[]
matlabify(::Missing) = Any[]
matlabify(xs::Tuple) = Any[matlabify(x) for x in xs]
matlabify(xs::Union{<:AbstractDict, <:NamedTuple, <:Base.Iterators.Pairs}) = Dict{String,Any}(string(k) => matlabify(v) for (k,v) in xs)

# Convert Matlab values to Julia representation
juliafy(x) = x # default
juliafy(x::AbstractMatrix) = size(x,2) == 1 ? vec(x) : x

# jlcall options
Base.@kwdef struct JLCallOptions
    f::String = "identity"
    args::Vector{Any} = Any[]
    kwargs::Dict{String, Any} = Any[]
    julia::String = joinpath(Base.Sys.BINDIR, "julia")
    project::String = ""
    threads::Int = Base.Threads.nthreads()
    setup::String = ""
    modules::Vector{Any} = Any[]
    workspace::String = mktempdir(; prefix = ".jlcall_", cleanup = true)
    shared::Bool = true
    port::Int = 3000
    restart::Bool = false
    debug::Bool = false
    verbose::Bool = false
end

function JLCallOptions(mxfile::String; kwargs...)
    opts = Dict{Symbol, Any}(Symbol(k) => juliafy(v) for (k,v) in MAT.matread(mxfile))
    JLCallOptions(; opts..., kwargs...)
end

function matlabify(o::JLCallOptions)
    args = Any[o.f, o.args, o.kwargs]
    for k in fieldnames(typeof(o))
        k ∈ (:f, :args, :kwargs) && continue
        v = getproperty(o, k)
        (v isa AbstractArray) && (v = vec(v))
        push!(args, string(k))
        push!(args, v)
    end
    return args
end

function kill(port; verbose = false)
    try
        DaemonMode.sendExitCode(port)
        verbose && println("* Julia server killed")
    catch e
        if !(e isa Base.IOError)
            verbose && println("* Julia server inactive; nothing to kill")
            rethrow(e)
        end
    end
    return nothing
end

function run(mod::Module; workspace)
    opts = JLCallOptions(joinpath(workspace, JL_INPUT); workspace)

    if opts.workspace ∉ LOAD_PATH
        pushfirst!(LOAD_PATH, opts.workspace)
    end

    # Activate user project, if necessary
    if !isempty(opts.project) && normpath(dirname(Base.active_project())) != normpath(opts.project)
        Pkg.activate(opts.project)
        Pkg.instantiate()
    end

    # Build expression to evaluate
    ex = quote
        $(
            if !isempty(opts.setup)
                [:(include($(opts.setup)))]
            else
                []
            end...
        )
        $(
            map(opts.modules) do mod_name
                # Load module; will fail if not installed
                :(import $(Meta.parse(mod_name)))
            end...
        )
        $(Meta.parse(opts.f))
    end

    # Save expression to temp file for debugging
    open(jlcall_tempname(mkpath(joinpath(opts.workspace, "tmp"))) * ".jl"; write = true) do io
        println(io, string(MacroTools.prettify(ex)))
    end

    # Evaluate expression and call returned function
    f = @eval mod $ex
    args = opts.args
    kwargs = Pair{Symbol, Any}[Symbol(k) => v for (k,v) in opts.kwargs]
    output = Base.invokelatest(f, args...; kwargs...)
    output = output isa Tuple ? Any[matlabify.(output)...] : Any[matlabify(output)]

    # Save outputs
    MAT.matwrite(
        joinpath(opts.workspace, JL_OUTPUT),
        Dict{String,Any}("output" => output)
    )

    return nothing
end

const jlcall_tempname_count = Ref(0)
function jlcall_tempname(parent)
    tmp = lpad(jlcall_tempname_count[], 4, '0') * "_" * basename(tempname())
    jlcall_tempname_count[] += 1
    return joinpath(parent, tmp)
end

end # module JuliaFromMATLAB

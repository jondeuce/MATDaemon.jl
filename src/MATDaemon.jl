"""
$(README)
"""
module MATDaemon

const VERSION = v"0.1.2"

import DaemonMode
import MAT
import MacroTools
import Pkg

using DocStringExtensions: README, TYPEDFIELDS, TYPEDSIGNATURES
using Downloads: download

export download_jlcall

# Options file for communicating with MATLAB
const JL_OPTIONS = "jlcall_opts.mat"

# Containers which are matlabified by iterating over `pairs`
const KeyValueContainer = Union{<:AbstractDict, <:NamedTuple, <:Base.Iterators.Pairs}

"""
    $(TYPEDSIGNATURES)

Download or copy the `jlcall.m` MATLAB API function to the file `filename`.

By default, `jlcall.m` is copied into the current working directory from the `api` subfolder of the installed `MATDaemon.jl` source tree.
The latest version of `jlcall.m` can instead be downloaded from GitHub by passing `latest = true`.
The destination `filename` can be overwritten if it exists by passing `force = true`.
"""
function download_jlcall(filename::String = joinpath(pwd(), "jlcall.m"); latest::Bool = false, force::Bool = false)
    if latest
        jlcall_github = "https://raw.githubusercontent.com/jondeuce/MATDaemon.jl/master/api/jlcall.m"
        jlcall_local = download(jlcall_github)
    else
        jlcall_local = normpath(@__DIR__, "../api/jlcall.m")
    end
    cp(jlcall_local, filename; force = force)
end

"""
    matlabify(x)

Convert Julia value `x` to equivalent MATLAB representation.
"""
matlabify(x) = x # default
matlabify(::Nothing) = zeros(Float64, 0, 0) # represent `Nothing` as MATLAB's `[]`
matlabify(::Missing) = zeros(Float64, 0, 0) # represent `Missing` as MATLAB's `[]`
matlabify(x::Symbol) = string(x)
matlabify(xs::Tuple) = matlabify_iterable(xs)
matlabify(xs::KeyValueContainer) = matlabify_pairs(xs)

matlabify_iterable(xs) = Any[matlabify(x) for x in xs]
matlabify_pairs(xs) = Dict{String, Any}(string(k) => matlabify(v) for (k, v) in pairs(xs))

matlabify_output(x) = Any[matlabify(x)] # default
matlabify_output(::Nothing) = Any[]
matlabify_output(x::Tuple) = Any[map(matlabify, x)...]

juliafy_args(xs::Array{Any}) = vec(xs)
juliafy_kwargs(xs::Dict{String, Any}) = Pair{Symbol, Any}[Symbol(k) => v for (k, v) in xs]

"""
    JLCallOptions(; kwargs...)

Julia struct for storing [`jlcall.m`](https://github.com/jondeuce/MATDaemon.jl/blob/master/api/jlcall.m) input parser results.

Struct fields/keyword arguments for constructor:

$(TYPEDFIELDS)
"""
Base.@kwdef struct JLCallOptions
    "User function to be parsed and evaluated"
    f::String               = "(args...; kwargs...) -> nothing"
    "MATLAB `.mat` file containing positional and keyword arguments for calling `f`"
    infile::String          = tempname(; cleanup = true) * ".mat"
    "MATLAB `.mat` file for writing outputs of `f` into"
    outfile::String         = tempname(; cleanup = true) * ".mat"
    "Julia runtime binary location"
    runtime::String         = joinpath(Base.Sys.BINDIR, "julia")
    "Julia project to activate before calling `f`"
    project::String         = ""
    "Number of Julia threads"
    threads::Int            = Threads.nthreads()
    "Julia setup script to include before defining and calling the user function"
    setup::String           = ""
    "Treat `f` as a generic Julia expression, not a function: evaluate `f` and return `nothing`"
    nofun::Bool             = false
    "Julia modules to import before defining and calling the user function"
    modules::Vector{Any}    = Any[]
    "Current working directory. Change path to this directory before loading code"
    cwd::String             = pwd()
    "MATDaemon workspace. Local Julia project and temporary files for communication with MATLAB are stored here"
    workspace::String       = mktempdir(; prefix = ".jlcall_", cleanup = true)
    "Start Julia instance on a local server using `DaemonMode.jl`"
    server::Bool            = true
    "Port to start Julia server on"
    port::Int               = 3000
    "Julia code is loaded into a persistent server environment if true. Otherwise, load code in unique namespace"
    shared::Bool            = true
    "Restart the Julia server before loading code"
    restart::Bool           = false
    "Shut down the julia server and return"
    shutdown::Bool          = false
    "Garbage collect temporary files after each call"
    gc::Bool                = true
    "Print debugging information"
    debug::Bool             = false
    "Suppress Julia I/O"
    quiet::Bool             = false
    "Reinstall MATDaemon workspace"
    reinstall::Bool         = false
    "Version number of jlcall.m"
    VERSION::String         = string(VERSION)
end

matlabify(opts::JLCallOptions) = Dict{String, Any}(string(k) => matlabify(getproperty(opts, k)) for k in fieldnames(JLCallOptions))

"""
    $(TYPEDSIGNATURES)

Start Julia server.
"""
function start(port::Int; shared::Bool, verbose::Bool = false)
    DaemonMode.serve(port, shared; print_stack = true, async = true, threaded = false)
    verbose && println("\n* Julia server started")
    return nothing
end

"""
    $(TYPEDSIGNATURES)

Kill Julia server. If server is already killed, do nothing.
"""
function kill(port::Int; verbose::Bool = false)
    try
        DaemonMode.sendExitCode(port)
        verbose && println("\n* Julia server killed")
    catch e
        if (e isa Base.IOError)
            #TODO: Check for proper error code:
            #   on linux: abs(e.code) == abs(Libc.ECONNREFUSED)
            #   on windows: ?
            verbose && println("\n* Julia server inactive; nothing to kill")
        else
            rethrow()
        end
    end
    return nothing
end

"""
    $(TYPEDSIGNATURES)

Load [`jlcall.m`](https://github.com/jondeuce/MATDaemon.jl/blob/master/api/jlcall.m) input parser results from `workspace`.
"""
function load_options(workspace::String)
    clean_value(k, v) =
        k == "modules" ? vec(v) : # MATLAB vectors are passed as column matrices
        k == "threads" && v == "auto" ? Threads.nthreads() : # Replace --threads=auto with threads from this session
        v

    mxopts = MAT.matread(joinpath(workspace, JL_OPTIONS))
    kwargs = Dict{Symbol, Any}(Symbol(k) => clean_value(k, v) for (k, v) in mxopts)
    opts = JLCallOptions(; kwargs..., workspace = workspace)

    if VersionNumber(opts.VERSION) !== VERSION
        @warn "MATDaemon version (v$(VERSION)) does not match jlcall.m version (v$(opts.VERSION)).\n" *
            "This may lead to errors; please download the appropriate jlcall.m file from: \n" *
            "    https://raw.githubusercontent.com/jondeuce/MATDaemon.jl/v$(VERSION)/api/jlcall.m"
    end

    return opts
end

"""
    $(TYPEDSIGNATURES)

Initialize [`jlcall`](@ref) environment.
"""
function init_environment(opts::JLCallOptions)
    # Change to current MATLAB working directory
    cd(opts.cwd)

    # Activate user project
    if !isempty(opts.project)
        proj_file = abspath(expanduser(opts.project))
        if isdir(proj_file)
            proj_file = joinpath(proj_file, "Project.toml")
        end
        if Base.active_project() != proj_file
            # Passed project is not active; activate it
            Pkg.activate(proj_file; io = devnull)
        end
    end

    return nothing
end

"""
    $(TYPEDSIGNATURES)

Save [`jlcall`](@ref) output results into workspace.
"""
function save_output(output, opts::JLCallOptions)
    # Try writing output to `opts.outfile`
    try
        MAT.matwrite(opts.outfile, Dict{String, Any}("output" => output))
    catch e
        println("\n* ERROR: Unable to write Julia output to .mat:\n*   ", opts.outfile)
        rm(opts.outfile; force = true)
        rethrow()
    end

    return nothing
end

"""
    $(TYPEDSIGNATURES)

Run Julia function `f` using [`jlcall.m`](https://github.com/jondeuce/MATDaemon.jl/blob/master/api/jlcall.m) input parser results `opts`.
"""
function jlcall(f::F, opts::JLCallOptions) where {F}
    # Since `f` is dynamically defined in a global scope, try to force specialization on `f` (may help performance)
    f_args = MAT.matread(opts.infile)
    args = juliafy_args(f_args["args"])
    kwargs = juliafy_kwargs(f_args["kwargs"])
    output = f(args...; kwargs...)

    # Save results to workspace
    save_output(matlabify_output(output), opts)

    return output
end

"""
    $(TYPEDSIGNATURES)

Location of script for loading code, importing modules, and evaluating the function expression passed from [`jlcall.m`](https://github.com/jondeuce/MATDaemon.jl/blob/master/api/jlcall.m).
"""
jlcall_script() = joinpath(@__DIR__, "..", "api", "jlcall.jl")

end # module MATDaemon

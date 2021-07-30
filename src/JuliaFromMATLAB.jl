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

function serve(port)
    DaemonMode.serve(port)
end

function kill(port)
    try
        DaemonMode.sendExitCode(port)
        println("* Julia server killed")
    catch e
        if !(e isa Base.IOError)
            println("* Julia server inactive; nothing to kill")
            rethrow(e)
        end
    end
    return nothing
end

function run(workspace)
    if workspace ∉ LOAD_PATH
        pushfirst!(LOAD_PATH, workspace)
    end

    input = MAT.matread(joinpath(workspace, JL_INPUT))

    # Activate user project, if necessary
    if !isempty(input["project"]) && normpath(dirname(Base.active_project())) != normpath(input["project"])
        Pkg.activate(input["project"])
        Pkg.instantiate()
    end

    # Build expression to evaluate
    ex = quote
        $(
            if !isempty(input["setup"])
                [:(include($(input["setup"])))]
            else
                []
            end...
        )
        $(
            map(input["modules"]) do mod_name
                mod = Meta.parse(mod_name)
                # Load module; will fail if not installed
                :(import $mod)
            end...
        )
        $(Meta.parse(input["f"]))
    end

    # Save expression to temp file for debugging
    open(jlcall_tempname(mkpath(joinpath(input["workspace"], "tmp"))) * ".jl"; write = true) do io
        println(io, string(MacroTools.prettify(ex)))
    end

    # Evaluate expression and call returned function
    f = Main.eval(ex)
    args = input["args"]
    kwargs = input["kwargs"]
    kwargs = Pair{Symbol, Any}[Symbol(k) => v for (k,v) in zip(kwargs[1:2:end], kwargs[2:2:end])]
    output = Base.invokelatest(f, args...; kwargs...)

    # Save outputs
    MAT.matwrite(
        joinpath(workspace, JL_OUTPUT),
        Dict{String,Any}("output" => matlabify(output))
    )

    return nothing
end

matlabify(x) = Any[x] # by default, interpret as single output
matlabify(::Nothing) = Any[]
matlabify(::Missing) = Any[]
matlabify(xs::Tuple) = Any[xs...]
matlabify(xs::NamedTuple) = Any[xs...]

const jlcall_tempname_count = Ref(0)
function jlcall_tempname(parent)
    tmp = lpad(jlcall_tempname_count[], 4, '0') * "_" * basename(tempname())
    jlcall_tempname_count[] += 1
    return joinpath(parent, tmp)
end

end # module JuliaFromMATLAB

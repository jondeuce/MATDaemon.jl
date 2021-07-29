"""
    JuliaFromMATLAB

Utilities module for calling Julia from MATLAB.
"""
module JuliaFromMATLAB

import DaemonMode
import MAT
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
    inputs = MAT.matread(joinpath(workspace, JL_INPUT))
    display(inputs); println("")

    if !isempty(inputs["project"])
        # Activate user project
        Pkg.activate(inputs["project"]; io = devnull)
    else
        # If project is unspecified, default environment in ~/.julia/environments is activated
        Pkg.activate(; io = devnull)
    end

    args = inputs["args"]
    kwargs = inputs["kwargs"]
    kwargs = Pair{Symbol, Any}[Symbol(k) => v for (k,v) in zip(kwargs[1:2:end], kwargs[2:2:end])]

    f = Main.eval(Meta.parse(inputs["f"]))
    outputs = Base.invokelatest(f, args...; kwargs...)
    display(outputs); println("")

    return nothing
end

end # module JuliaFromMATLAB

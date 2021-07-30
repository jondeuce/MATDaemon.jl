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
const JL_FINISHED = "jl_finished.txt"

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
    input = MAT.matread(joinpath(workspace, JL_INPUT))

    if !isempty(input["project"])
        # Activate user project
        Pkg.activate(input["project"]; io = devnull)
    else
        # If project is unspecified, default environment in ~/.julia/environments is activated
        Pkg.activate(; io = devnull)
    end

    # Build expression to evaluate
    ex = quote
        $(
            map(input["modules"]) do mod_name
                mod = Meta.parse(mod_name)
                if !input["install"]
                    # Load module; will fail if not installed
                    :(import $mod)
                else
                    # Try loading module; if module fails to load, try installing and then loading
                    :(
                        try
                            import $mod
                        catch e
                            import Pkg
                            Pkg.add($(mod_name))
                            import $mod
                        end
                    )
                end
            end...
        )
        $(Meta.parse(input["f"]))
    end

    # Save expression to temp file for debugging
    tempfile_dir = mkpath(joinpath(input["workspace"], "tempfiles"))
    open(jlcall_tempname(tempfile_dir) * ".jl"; write = true) do io
        println(io, string(ex))
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
    touch(joinpath(workspace, JL_FINISHED))

    return nothing
end

matlabify(x) = Any[x] # by default, interpret as single output
matlabify(xs::Tuple) = Any[xs...]
matlabify(xs::NamedTuple) = Any[xs...]

const tempname_count = Ref(0)
function jlcall_tempname(parent)
    tmp = lpad(tempname_count[], 4, '0') * "_" * basename(tempname())
    tempname_count[] += 1
    return joinpath(parent, tmp)
end

end # module JuliaFromMATLAB

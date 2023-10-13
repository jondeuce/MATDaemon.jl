# Dynamically include setup code, import modules, and finally evaluate the function expression passed by the user.
# User settings are loaded from the input file `MATDaemon.JL_OPTIONS` located in the jlcall.m workspace folder.
# The workspace folder is passed using the environment variable `MATDAEMON_WORKSPACE`.
#
# This version of jlcall.jl was written for MATDaemon v0.1.3.
# MATDaemon was written by Jonathan Doucette (jdoucette@physics.ubc.ca).

# MATDaemon must be available
import MATDaemon

let
    # Load jlcall.m input parser results from workspace
    local workspace = ENV["MATDAEMON_WORKSPACE"]
    local opts = MATDaemon.load_options(workspace)
    local io = stdout

    # Initialize user project environment etc.
    MATDaemon.init_environment(opts)

    # Print environment for debugging
    if opts.debug
        println(io, "\n* Environment for evaluating Julia expression:")
        println(io, "*   MATDaemon workspace: $(workspace)")
        println(io, "*   Current working dir: $(pwd())")
        println(io, "*   Current module: $(@__MODULE__)")
        println(io, "*   Load path: $(LOAD_PATH)")
        println(io, "*   Active project: $(Base.active_project())")
    end

    # Include setup code
    if !isempty(opts.setup)
        include(opts.setup)
    end

    # Load modules from strings; will fail if not installed
    for mod in opts.modules
        @eval import $(Meta.parse(mod))
    end

    # Parse and evaluate `f` from string
    local f_expr = :(let; $(Meta.parse(opts.f)); end)

    # If not a function call, return a thunk
    if opts.nofun
        f_expr = :(let; $(f_expr); (args...; kwargs...) -> nothing; end)
    end

    if opts.debug
        println(io, "\n* Generated Julia function expression:")
        println(io, string(MATDaemon.MacroTools.prettify(f_expr)))
    end

    local f = @eval $(f_expr)

    if opts.debug
        println(io, "\n* Evaluating Julia expression:")
    end

    # Call `f`, loading MATLAB input arguments from `opts.infile`
    # and saving Julia outputs to `opts.outfile`
    local output = MATDaemon.jlcall(f, opts)

    if opts.debug
        println(io, "\n* Julia output summary:")
        println(io, "*   output :: ", summary(output))
    end

    nothing
end

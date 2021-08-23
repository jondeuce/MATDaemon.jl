# Dynamically include setup code, import modules, and finally evaluate the function expression passed by the user.
# User settings are loaded from the input file `JuliaFromMATLAB.JL_INPUT` located in the jlcall.m workspace folder.
# The workspace folder is passed using the environment variable `JULIA_FROM_MATLAB_WORKSPACE`.

let
    # Load jlcall.m input parser results from workspace
    local workspace = get(ENV, "JULIA_FROM_MATLAB_WORKSPACE", abspath(".jlcall"))
    local opts = JuliaFromMATLAB.load_options(workspace)

    # Initialize load path etc.
    JuliaFromMATLAB.init_environment(opts)

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

    # Load modules from strings; will fail if not installed
    for mod in opts.modules
        @eval import $(Meta.parse(mod))
    end

    # Parse and evaluate `f` from string
    local f_expr = :(let; $(Meta.parse(opts.f)); end)

    if opts.debug
        println("* Generated Julia function expression: ")
        println(string(JuliaFromMATLAB.MacroTools.prettify(f_expr)), "\n")
    end

    local f = @eval $(f_expr)

    # Call `f` using MATLAB input arguments
    local output = JuliaFromMATLAB.jlcall(f, opts)

    # Save results to workspace
    JuliaFromMATLAB.save_output(output, opts)
end

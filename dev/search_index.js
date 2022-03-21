var documenterSearchIndex = {"docs":
[{"location":"#MATDaemon.jl","page":"Home","title":"MATDaemon.jl","text":"","category":"section"},{"location":"#Index","page":"Home","title":"Index","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"Modules = [MATDaemon]","category":"page"},{"location":"","page":"Home","title":"Home","text":"Modules = [MATDaemon]","category":"page"},{"location":"#MATDaemon.MATDaemon","page":"Home","title":"MATDaemon.MATDaemon","text":"MATDaemon.jl\n\n\"Yes, of course duct tape works in a near-vacuum. Duct tape works anywhere. Duct tape is magic and should be worshiped.\" ― Andy Weir, The Martian\n\n(Image: dev) (Image: build status) (Image: codecov.io)\n\nCall Julia from MATLAB using a Julia daemon launched by DaemonMode.jl.\n\nQuickstart\n\nUse the MATLAB function jlcall.m to call Julia from MATLAB:\n\n>> jlcall('sort', {rand(2,5)}, struct('dims', int64(2)))\n\nans =\n\n    0.1270    0.2785    0.6324    0.8147    0.9575\n    0.0975    0.5469    0.9058    0.9134    0.9649\n\nThe positional arguments passed to jlcall.m are:\n\nThe Julia function to call, given as a MATLAB char array. This can be any Julia expression which evaluates to a function. For example, 'a=2; b=3; x -> a*x+b'. For convenience, the empty string '' is interpreted as '(args...; kwargs...) -> nothing', returning nothing for any inputs. Note: expressions are wrapped in a let block and evaluated in the global scope\nPositional arguments, given as a MATLAB cell array. For example, args = {arg1, arg2, ...}\nKeyword arguments, given as a MATLAB struct. For example, kwargs = struct('key1', value1, 'key2', value2, ...)\n\nThe first time jlcall.m is invoked:\n\nMATDaemon.jl will be installed into a local Julia project, if one does not already exist. By default, a folder .jlcall is created in the same folder as jlcall.m\nA Julia server will be started in the background using DaemonMode.jl\n\nAll subsequent calls to Julia are run on the Julia server. The server will be automatically killed when MATLAB exits.\n\nRestarting the Julia server\n\nIn the event that the Julia server reaches an undesired state, the server can be restarted by passing the 'restart' flag with value true:\n\n>> jlcall('', 'restart', true) % restarts the Julia server and returns nothing\n\nSimilarly, one can shutdown the Julia server without restarting it:\n\n>> jlcall('', 'shutdown', true) % shuts down the Julia server and returns nothing\n\nSetting up the Julia environment\n\nBefore calling Julia functions, it may be necessary or convenient to first set up the Julia environment. For example, one may wish to activate a local project environment, run setup scripts, import modules for later use, or set the number of threads for running multithreaded code.\n\nThis setup can be conveniently executed at the start of your MATLAB script with a single call to jlcall.m as follows:\n\n>> jlcall('', ...\n    'project', '/path/to/MyProject', ... % activate a local Julia Project\n    'setup', '/path/to/setup.jl', ... % run a setup script to load some custom Julia code\n    'modules', {'MyProject', 'LinearAlgebra', 'Statistics'}, ... % load a custom module and some modules from Base Julia\n    'threads', 'auto', ... % use the default number of Julia threads\n    'restart', true ... % start a fresh Julia server environment\n    )\n\nSee the corresponding sections below for more details about these flags.\n\nJulia multithreading\n\nThe number of threads used by the Julia server can be set using the 'threads' flag:\n\n>> jlcall('() -> Threads.nthreads()', 'threads', 8, 'restart', true)\n\nans =\n\n  int64\n\n   8\n\nThe default value for 'threads' is 'auto', deferring to Julia to choose the number of threads.\n\nNote: Julia cannot change the number of threads at runtime. In order for the 'threads' flag to take effect, the server must be restarted.\n\nLoading modules\n\nJulia modules can be loaded and used:\n\n>> jlcall('LinearAlgebra.norm', {[3.0; 4.0]}, 'modules', {'LinearAlgebra'})\n\nans =\n\n     5\n\nNote: modules are loaded using import, not using. Module symbols must therefore be fully qualified, e.g. LinearAlgebra.norm in the above example as opposed to norm.\n\nPersistent environments\n\nBy default, previously loaded Julia code is available on subsequent calls to jlcall.m. For example, following the above call to LinearAlgebra.norm, the LinearAlgebra.det function can be called without loading LinearAlgebra again:\n\n>> jlcall('LinearAlgebra.det', {[1.0 2.0; 3.0 4.0]})\n\nans =\n\n    -2\n\nUnique environments\n\nSet the 'shared' flag to false in order to evaluate each Julia call in a separate namespace on the Julia server:\n\n% Restart the server, setting 'shared' to false\n>> jlcall('LinearAlgebra.norm', {[3.0; 4.0]}, 'modules', {'LinearAlgebra'}, 'restart', true, 'shared', false)\n\nans =\n\n     5\n\n% This call now errors, despite the above command loading the LinearAlgebra module, as LinearAlgebra.norm is evaluated in a new namespace\n>> jlcall('LinearAlgebra.norm', {[3.0; 4.0]}, 'shared', false)\nERROR: LoadError: UndefVarError: LinearAlgebra not defined\nStacktrace:\n ...\n\nUnique Julia instances\n\nInstead of running Julia code on a persistent Julia server, unique Julia instances can be launched for each call to jlcall.m by passing the 'server' flag with value false.\n\nNote: this may cause significant overhead when repeatedly calling jlcall.m due to Julia package precompilation and loading:\n\n>> tic; jlcall('x -> sum(abs2, x)', {1:5}, 'server', false); toc\nElapsed time is 4.181178 seconds. % call unique Julia instance\n\n>> tic; jlcall('x -> sum(abs2, x)', {1:5}, 'restart', true); toc\nElapsed time is 5.046929 seconds. % re-initialize Julia server\n\n>> tic; jlcall('x -> sum(abs2, x)', {1:5}); toc\nElapsed time is 0.267088 seconds. % call server; significantly faster\n\nLoading code from a local project\n\nCode from a local Julia project can be loaded and called:\n\n>> jlcall('MyProject.my_function', args, kwargs, ...\n    'project', '/path/to/MyProject', ...\n    'modules', {'MyProject'})\n\nNote: the string passed via the 'project' flag is simply forwarded to Pkg.activate; it is the user's responsibility to ensure that the project's dependencies have been installed.\n\nLoading setup code\n\nJulia functions may require or return types which cannot be directly passed from or loaded into MATLAB. For example, suppose one would like to query Base.VERSION. Naively calling jlcall('() -> Base.VERSION') would fail, as typeof(Base.VERSION) is not a String but a VersionNumber.\n\nOne possible remedy is to define a wrapper function in a Julia script:\n\n# setup.jl\njulia_version() = string(Base.VERSION)\n\nThen, use the 'setup' flag to pass the above script to jlcall.m:\n\n>> jlcall('julia_version', 'setup', '/path/to/setup.jl')\n\nans =\n\n    '1.6.1'\n\nIn this case, jlcall('() -> string(Base.VERSION)') would work just as well. In general, however, interfacing with complex Julia libraries using MATLAB types may be nontrivial, and the 'setup' flag allows for the execution of arbitrary setup code.\n\nNote: the setup script is loaded into the global scope using include; when using persistent environments, symbols defined in the setup script will be available on subsequent calls to jlcall.m.\n\nHandling Julia outputs\n\nOutput(s) from Julia are returned using the MATLAB cell array varargout, MATLAB's variable-length list of output arguments. A helper function MATDaemon.matlabify is used to convert Julia values into MATLAB-compatible values. Specifically, the following rules are used to populate varargout with the Julia output y:\n\nIf y::Nothing, then varargout = {} and no outputs are returned to MATLAB\nIf y::Tuple, then length(y) outputs are returned, with varargout{i} given by matlabify(y[i])\nOtherwise, one output is returned with varargout{1} given by matlabify(y)\n\nThe following matlabify methods are defined by default:\n\nmatlabify(x) = x # default fallback\nmatlabify(::Union{Nothing, Missing}) = zeros(0,0) # equivalent to MATLAB's []\nmatlabify(x::Symbol) = string(x)\nmatlabify(xs::Tuple) = Any[matlabify(x) for x in xs] # matlabify values\nmatlabify(xs::Union{<:AbstractDict, <:NamedTuple, <:Base.Iterators.Pairs}) = Dict{String, Any}(string(k) => matlabify(v) for (k, v) in pairs(xs)) # convert keys to strings and matlabify values\n\nNote: MATLAB cell and struct types correspond to Array{Any} and Dict{String, Any} in Julia.\n\nConversion via matlabify can easily be extended to additional types. Returning to the example from the above section, we can define a matlabify method for Base.VersionNumber:\n\n# setup.jl\nMATDaemon.matlabify(v::Base.VersionNumber) = string(v)\n\nNow, the return type will be automatically converted:\n\n>> jlcall('() -> Base.VERSION', 'setup', '/path/to/setup.jl')\n\nans =\n\n    '1.6.1'\n\nPerformance\n\nMATLAB inputs and Julia ouputs are passed back and forth between MATLAB and the DaemonMode.jl server by writing to temporary .mat files. The location of these files can be configured with the 'infile' and 'outfile' flags, respectively. Pointing these files to a ram-backed file system is recommended when possible (for example, the /tmp folder on Linux is usually ram-backed), as read/write speed will likely improve. This is now the default; 'infile' and 'outfile' are created via the MATLAB tempname function (thanks to @mauro3 for this tip).\n\nNevertheless, this naturally leads to some overhead when calling Julia, particularly when the MATLAB inputs and/or Julia outputs have large memory footprints. It is therefore not recommended to use jlcall.m in performance critical loops.\n\nMATLAB and Julia version compatibility\n\nThis package has been tested on a variety of MATLAB versions. However, for some versions of Julia and MATLAB, supported versions of external libraries may clash. For example, running jlcall.m using Julia v1.6.1 and MATLAB R2015b gives the following error:\n\n>> jlcall\n\nERROR: Unable to load dependent library ~/.local/julia-1.6.1/bin/../lib/julia/libjulia-internal.so.1\n\nMessage: /usr/local/MATLAB/R2015b/sys/os/glnxa64/libstdc++.so.6: version `GLIBCXX_3.4.20' not found (required by ~/.local/julia-1.6.1/bin/../lib/julia/libjulia-internal.so.1)\n\nThis error results due to a clash of supported libstdc++ versions, and does not occur when using e.g. Julia v1.5.4 with MATLAB R2015b, or Julia v1.6.1 with MATLAB R2020b.\n\nIf you encounter this issue, see the Julia and MATLAB documentation for information on mutually supported external libraries.\n\nAbout this package\n\nThis repository contains utilities for parsing and running Julia code, passing MATLAB arguments to Julia, and retrieving Julia outputs from MATLAB.\n\nThe workhorse behind MATDaemon.jl and jlcall.m is DaemonMode.jl which is used to start a persistent Julia server in the background.\n\n\n\n\n\n","category":"module"},{"location":"#MATDaemon.JLCallOptions","page":"Home","title":"MATDaemon.JLCallOptions","text":"JLCallOptions(; kwargs...)\n\nJulia struct for storing jlcall.m input parser results.\n\nStruct fields/keyword arguments for constructor:\n\nf::String\nUser function to be parsed and evaluated\ninfile::String\nMATLAB .mat file containing positional and keyword arguments for calling f\noutfile::String\nMATLAB .mat file for writing outputs of f into\nruntime::String\nJulia runtime binary location\nproject::String\nJulia project to activate before calling f\nthreads::Int64\nNumber of Julia threads\nsetup::String\nJulia setup script to include before defining and calling the user function\nnofun::Bool\nTreat f as a generic Julia expression, not a function: evaluate f and return nothing\nmodules::Vector{Any}\nJulia modules to import before defining and calling the user function\ncwd::String\nCurrent working directory. Change path to this directory before loading code\nworkspace::String\nMATDaemon workspace. Local Julia project and temporary files for communication with MATLAB are stored here\nserver::Bool\nStart Julia instance on a local server using DaemonMode.jl\nport::Int64\nPort to start Julia server on\nshared::Bool\nJulia code is loaded into a persistent server environment if true. Otherwise, load code in unique namespace\nrestart::Bool\nRestart the Julia server before loading code\nshutdown::Bool\nShut down the julia server and return\ngc::Bool\nGarbage collect temporary files after each call\ndebug::Bool\nPrint debugging information\n\n\n\n\n\n","category":"type"},{"location":"#MATDaemon.init_environment-Tuple{MATDaemon.JLCallOptions}","page":"Home","title":"MATDaemon.init_environment","text":"init_environment(opts::MATDaemon.JLCallOptions)\n\n\nInitialize jlcall environment.\n\n\n\n\n\n","category":"method"},{"location":"#MATDaemon.jlcall-Union{Tuple{F}, Tuple{F, MATDaemon.JLCallOptions}} where F","page":"Home","title":"MATDaemon.jlcall","text":"jlcall(f, opts::MATDaemon.JLCallOptions)\n\n\nRun Julia function f using jlcall.m input parser results opts.\n\n\n\n\n\n","category":"method"},{"location":"#MATDaemon.jlcall_script-Tuple{}","page":"Home","title":"MATDaemon.jlcall_script","text":"jlcall_script() -> String\n\n\nLocation of script for loading code, importing modules, and evaluating the function expression passed from jlcall.m.\n\n\n\n\n\n","category":"method"},{"location":"#MATDaemon.kill-Tuple{Int64}","page":"Home","title":"MATDaemon.kill","text":"kill(port::Int64; verbose)\n\n\nKill Julia server. If server is already killed, do nothing.\n\n\n\n\n\n","category":"method"},{"location":"#MATDaemon.load_options-Tuple{String}","page":"Home","title":"MATDaemon.load_options","text":"load_options(workspace::String) -> MATDaemon.JLCallOptions\n\n\nLoad jlcall.m input parser results from workspace.\n\n\n\n\n\n","category":"method"},{"location":"#MATDaemon.matlabify-Tuple{Any}","page":"Home","title":"MATDaemon.matlabify","text":"matlabify(x)\n\nConvert Julia value x to equivalent MATLAB representation.\n\n\n\n\n\n","category":"method"},{"location":"#MATDaemon.save_output-Tuple{Any, MATDaemon.JLCallOptions}","page":"Home","title":"MATDaemon.save_output","text":"save_output(output, opts::MATDaemon.JLCallOptions)\n\n\nSave jlcall output results into workspace.\n\n\n\n\n\n","category":"method"},{"location":"#MATDaemon.start-Tuple{Int64}","page":"Home","title":"MATDaemon.start","text":"start(port::Int64; shared, verbose)\n\n\nStart Julia server.\n\n\n\n\n\n","category":"method"}]
}

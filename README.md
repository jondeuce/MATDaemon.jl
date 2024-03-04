# MATDaemon.jl

*"Yes, of course duct tape works in a near-vacuum. Duct tape works anywhere. Duct tape is magic and should be worshiped." ― Andy Weir, The Martian*

[![dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://jondeuce.github.io/MATDaemon.jl/dev)
[![build status](https://github.com/jondeuce/MATDaemon.jl/workflows/CI/badge.svg)](https://github.com/jondeuce/MATDaemon.jl/actions?query=workflow%3ACI)
[![codecov.io](https://codecov.io/github/jondeuce/MATDaemon.jl/branch/master/graph/badge.svg)](http://codecov.io/github/jondeuce/MATDaemon.jl/branch/master)

Call Julia from MATLAB using a Julia daemon launched by [`DaemonMode.jl`](https://github.com/dmolina/DaemonMode.jl).

## Installation

Download the MATLAB function [`jlcall.m`](https://github.com/jondeuce/MATDaemon.jl/blob/v0.1.4/api/jlcall.m) from the `api` subfolder of the `MATDaemon.jl` github repository and run

```matlab
>> jlcall
```

in the MATLAB console.
The first time [`jlcall.m`](https://github.com/jondeuce/MATDaemon.jl/blob/v0.1.4/api/jlcall.m) is invoked in a MATLAB session:
1. A local Julia project `.jlcall/Project.toml` will be created, if it does not already exist, to which `MATDaemon.jl` and dependencies are added. The folder `.jlcall` is stored in the same directory as the downloaded copy of [`jlcall.m`](https://github.com/jondeuce/MATDaemon.jl/blob/v0.1.4/api/jlcall.m).
2. A Julia server will be started in the background using [`DaemonMode.jl`](https://github.com/dmolina/DaemonMode.jl) which loads `MATDaemon.jl`.

All subsequent calls to Julia via [`jlcall.m`](https://github.com/jondeuce/MATDaemon.jl/blob/v0.1.4/api/jlcall.m) are run on the Julia server.
The server will be automatically killed when MATLAB exits.

## Quickstart

Use the MATLAB function [`jlcall.m`](https://github.com/jondeuce/MATDaemon.jl/blob/v0.1.4/api/jlcall.m) to call Julia from MATLAB:

```matlab
>> jlcall('sort', {rand(2,5)}, struct('dims', int64(2)))

ans =

    0.1270    0.2785    0.6324    0.8147    0.9575
    0.0975    0.5469    0.9058    0.9134    0.9649
```

The positional arguments passed to [`jlcall.m`](https://github.com/jondeuce/MATDaemon.jl/blob/v0.1.4/api/jlcall.m) are:
1. The Julia function to call, given as a MATLAB `char` array. This can be any Julia expression which evaluates to a function. For example, `'a=2; b=3; x -> a*x+b'`. For convenience, the empty string `''` is interpreted as `'(args...; kwargs...) -> nothing'`, returning `nothing` for any inputs. **Note:** expressions are wrapped in a `let` block and evaluated in the global scope
2. Positional arguments, given as a MATLAB `cell` array. For example, `args = {arg1, arg2, ...}`
3. Keyword arguments, given as a MATLAB `struct`. For example, `kwargs = struct('key1', value1, 'key2', value2, ...)`

### Restarting the Julia server

In the event that the Julia server reaches an undesired state, the server can be restarted by passing the `'restart'` flag with value `true`:

```matlab
>> jlcall('', 'restart', true) % restarts the Julia server and returns nothing
```

Similarly, one can shutdown the Julia server without restarting it:

```matlab
>> jlcall('', 'shutdown', true) % shuts down the Julia server and returns nothing
```

### Setting up the Julia environment

Before calling Julia functions, it may be necessary or convenient to first set up the Julia environment. For example, one may wish to
activate a local [project environment](https://github.com/jondeuce/MATDaemon.jl#loading-code-from-a-local-project),
run [setup scripts](https://github.com/jondeuce/MATDaemon.jl#loading-setup-code),
[import modules](https://github.com/jondeuce/MATDaemon.jl#loading-setup-code) for later use,
or set the [number of threads](https://github.com/jondeuce/MATDaemon.jl#julia-multithreading) for running multithreaded code.

This setup can be conveniently executed at the start of your MATLAB script with a single call to [`jlcall.m`](https://github.com/jondeuce/MATDaemon.jl/blob/v0.1.4/api/jlcall.m) as follows:

```matlab
>> jlcall('', ...
    'project', '/path/to/MyProject', ... % activate a local Julia Project
    'setup', '/path/to/setup.jl', ... % run a setup script to load some custom Julia code
    'modules', {'MyProject', 'LinearAlgebra', 'Statistics'}, ... % load a custom module and some modules from Base Julia
    'threads', 'auto', ... % use the default number of Julia threads
    'restart', true ... % start a fresh Julia server environment
    )
```

See the corresponding sections below for more details about these flags.

### Julia multithreading

The number of threads used by the Julia server can be set using the `'threads'` flag:

```matlab
>> jlcall('() -> Threads.nthreads()', 'threads', 8, 'restart', true)

ans =

  int64

   8
```

The default value for `'threads'` is `'auto'`, deferring to Julia to choose the number of threads.

**Note:** Julia cannot change the number of threads at runtime.
In order for the `'threads'` flag to take effect, the server must be restarted.

### Loading modules

Julia modules can be loaded and used:

```matlab
>> jlcall('LinearAlgebra.norm', {[3.0; 4.0]}, 'modules', {'LinearAlgebra'})

ans =

     5
```

**Note:** modules are loaded using `import`, not `using`. Module symbols must therefore be fully qualified, e.g. `LinearAlgebra.norm` in the above example as opposed to `norm`.

### Persistent environments

By default, previously loaded Julia code is available on subsequent calls to [`jlcall.m`](https://github.com/jondeuce/MATDaemon.jl/blob/v0.1.4/api/jlcall.m).
For example, following the [above call](https://github.com/jondeuce/MATDaemon.jl#loading-modules) to `LinearAlgebra.norm`, the `LinearAlgebra.det` function can be called without loading `LinearAlgebra` again:

```matlab
>> jlcall('LinearAlgebra.det', {[1.0 2.0; 3.0 4.0]})

ans =

    -2
```

### Unique environments

Set the `'shared'` flag to `false` in order to evaluate each Julia call in a separate namespace on the Julia server:

```matlab
% Restart the server, setting 'shared' to false
>> jlcall('LinearAlgebra.norm', {[3.0; 4.0]}, 'modules', {'LinearAlgebra'}, 'restart', true, 'shared', false)

ans =

     5

% This call now errors, despite the above command loading the LinearAlgebra module, as LinearAlgebra.norm is evaluated in a new namespace
>> jlcall('LinearAlgebra.norm', {[3.0; 4.0]}, 'shared', false)
ERROR: LoadError: UndefVarError: LinearAlgebra not defined
Stacktrace:
 ...
```

### Unique Julia instances

Instead of running Julia code on a persistent Julia server, unique Julia instances can be launched for each call to [`jlcall.m`](https://github.com/jondeuce/MATDaemon.jl/blob/v0.1.4/api/jlcall.m) by passing the `'server'` flag with value `false`.

**Note:** this may cause significant overhead when repeatedly calling [`jlcall.m`](https://github.com/jondeuce/MATDaemon.jl/blob/v0.1.4/api/jlcall.m) due to Julia package precompilation and loading:

```matlab
>> tic; jlcall('x -> sum(abs2, x)', {1:5}, 'server', false); toc
Elapsed time is 4.181178 seconds. % call unique Julia instance

>> tic; jlcall('x -> sum(abs2, x)', {1:5}, 'restart', true); toc
Elapsed time is 5.046929 seconds. % re-initialize Julia server

>> tic; jlcall('x -> sum(abs2, x)', {1:5}); toc
Elapsed time is 0.267088 seconds. % call server; significantly faster
```

### Loading code from a local project

Code from a [local Julia project](https://pkgdocs.julialang.org/v1/environments/) can be loaded and called:

```matlab
>> jlcall('MyProject.my_function', args, kwargs, ...
    'project', '/path/to/MyProject', ...
    'modules', {'MyProject'})
```

**Note:** the string passed via the `'project'` flag is simply forwarded to `Pkg.activate`; it is the user's responsibility to ensure that the project's dependencies have been installed.

### Loading setup code

Julia functions may require or return types which cannot be directly passed from or loaded into MATLAB.
For example, suppose one would like to query `Base.VERSION`.
Naively calling `jlcall('() -> Base.VERSION')` would fail, as `typeof(Base.VERSION)` is not a `String` but a `VersionNumber`.

One possible remedy is to define a wrapper function in a Julia script:

```julia
# setup.jl
julia_version() = string(Base.VERSION)
```

Then, use the `'setup'` flag to pass the above script to [`jlcall.m`](https://github.com/jondeuce/MATDaemon.jl/blob/v0.1.4/api/jlcall.m):

```matlab
>> jlcall('julia_version', 'setup', '/path/to/setup.jl')

ans =

    '1.6.1'
```

In this case, `jlcall('() -> string(Base.VERSION)')` would work just as well.
In general, however, interfacing with complex Julia libraries using MATLAB types may be nontrivial, and the `'setup'` flag allows for the execution of arbitrary setup code.

**Note:** the setup script is loaded into the global scope using `include`; when using [persistent environments](https://github.com/jondeuce/MATDaemon.jl#persistent-environments), symbols defined in the setup script will be available on subsequent calls to [`jlcall.m`](https://github.com/jondeuce/MATDaemon.jl/blob/v0.1.4/api/jlcall.m).

### Handling Julia outputs

Output(s) from Julia are returned using the MATLAB `cell` array [`varargout`](https://www.mathworks.com/help/matlab/ref/varargout.html), MATLAB's variable-length list of output arguments.
A helper function `MATDaemon.matlabify` is used to convert Julia values into MATLAB-compatible values.
Specifically, the following rules are used to populate `varargout` with the Julia output `y`:

1. If `y::Nothing`, then `varargout = {}` and no outputs are returned to MATLAB
2. If `y::Tuple`, then `length(y)` outputs are returned, with `varargout{i}` given by `matlabify(y[i])`
3. Otherwise, one output is returned with `varargout{1}` given by `matlabify(y)`

The following `matlabify` methods are defined by default:

```julia
matlabify(x) = x # default fallback
matlabify(::Union{Nothing, Missing}) = zeros(0,0) # equivalent to MATLAB's []
matlabify(x::Symbol) = string(x)
matlabify(xs::Tuple) = Any[matlabify(x) for x in xs] # matlabify values
matlabify(xs::Union{<:AbstractDict, <:NamedTuple, <:Base.Iterators.Pairs}) = Dict{String, Any}(string(k) => matlabify(v) for (k, v) in pairs(xs)) # convert keys to strings and matlabify values
```

**Note:** MATLAB `cell` and `struct` types correspond to `Array{Any}` and `Dict{String, Any}` in Julia.

Conversion via `matlabify` can easily be extended to additional types.
Returning to the example from the [above section](https://github.com/jondeuce/MATDaemon.jl#loading-setup-code), we can define a `matlabify` method for `Base.VersionNumber`:

```julia
# setup.jl
MATDaemon.matlabify(v::Base.VersionNumber) = string(v)
```

Now, the return type will be automatically converted:

```matlab
>> jlcall('() -> Base.VERSION', 'setup', '/path/to/setup.jl')

ans =

    '1.6.1'
```

### Troubleshooting

In case the Julia server gets into a bad state, the following troubleshooting tips may be helpful:

* Try restarting the server: `jlcall('', 'restart', true)`
* Enable debug mode for verbose logging: `jlcall('', 'debug', true)`
* Call Julia directly instead of calling the server: `jlcall('', 'server', false)`
    * This will be slower, since each call to [`jlcall.m`](https://github.com/jondeuce/MATDaemon.jl/blob/v0.1.4/api/jlcall.m) will start a new Julia instance, but it may [fix server issues on Windows](https://github.com/jondeuce/MATDaemon.jl/issues/9#issuecomment-1761710048)
* Update the `MATDaemon.jl` Julia project environment (note: this will restart the server): `jlcall('', 'update', true)`
* Reinstall the `MATDaemon.jl` workspace folder (note: this will restart the server): `jlcall('', 'reinstall', true)`
    * By default, the workspace folder is named `.jlcall` and is stored in the same directory as [`jlcall.m`](https://github.com/jondeuce/MATDaemon.jl/blob/v0.1.4/api/jlcall.m)
    * The `'reinstall'` flag deletes the workspace folder, forcing `MATDaemon.jl` to be reinstalled; you can also delete it manually

### Performance

MATLAB inputs and Julia ouputs are passed back and forth between MATLAB and the `DaemonMode.jl` server by writing to temporary `.mat` files.
The location of these files can be configured with the `'infile'` and `'outfile'` flags, respectively.
Pointing these files to a ram-backed file system is recommended when possible (for example, the `/tmp` folder on Linux is usually ram-backed), as read/write speed will likely improve.
This is now the default; `'infile'` and `'outfile'` are created via the MATLAB `tempname` function (thanks to @mauro3 for this tip).

Nevertheless, this naturally leads to some overhead when calling Julia, particularly when the MATLAB inputs and/or Julia outputs have large memory footprints.
It is therefore not recommended to use [`jlcall.m`](https://github.com/jondeuce/MATDaemon.jl/blob/v0.1.4/api/jlcall.m) in performance critical loops.

## MATLAB and Julia version compatibility

This package has been tested on a variety of MATLAB versions.
However, for some versions of Julia and MATLAB, supported versions of external libraries may clash.
For example, running [`jlcall.m`](https://github.com/jondeuce/MATDaemon.jl/blob/v0.1.4/api/jlcall.m) using Julia v1.6.1 and MATLAB R2015b gives the following error:

```matlab
>> jlcall

ERROR: Unable to load dependent library ~/.local/julia-1.6.1/bin/../lib/julia/libjulia-internal.so.1

Message: /usr/local/MATLAB/R2015b/sys/os/glnxa64/libstdc++.so.6: version `GLIBCXX_3.4.20' not found (required by ~/.local/julia-1.6.1/bin/../lib/julia/libjulia-internal.so.1)
```

This error results due to a clash of supported `libstdc++` versions, and does not occur when using e.g. Julia v1.5.4 with MATLAB R2015b, or Julia v1.6.1 with MATLAB R2020b.

If you encounter this issue, see the [`Julia`](https://github.com/JuliaLang/julia/blob/master/doc/build/build.md#required-build-tools-and-external-libraries) and [`MATLAB`](https://www.mathworks.com/support/requirements/supported-compilers.html) documentation for information on mutually supported external libraries.

## About this package

This repository contains utilities for parsing and running Julia code, passing MATLAB arguments to Julia, and retrieving Julia outputs from MATLAB.

The workhorse behind `MATDaemon.jl` and [`jlcall.m`](https://github.com/jondeuce/MATDaemon.jl/blob/v0.1.4/api/jlcall.m) is [`DaemonMode.jl`](https://github.com/dmolina/DaemonMode.jl) which is used to start a persistent Julia server in the background.

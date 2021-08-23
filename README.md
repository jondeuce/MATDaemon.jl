# JuliaFromMATLAB.jl

<!-- [![stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://jondeuce.github.io/JuliaFromMATLAB.jl/stable) -->
<!-- [![dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://jondeuce.github.io/JuliaFromMATLAB.jl/dev) -->
[![build status](https://github.com/jondeuce/JuliaFromMATLAB.jl/workflows/CI/badge.svg)](https://github.com/jondeuce/JuliaFromMATLAB.jl/actions?query=workflow%3ACI)
[![codecov.io](https://codecov.io/github/jondeuce/JuliaFromMATLAB.jl/branch/master/graph/badge.svg)](http://codecov.io/github/jondeuce/JuliaFromMATLAB.jl/branch/master)

Call Julia from MATLAB.

## Quickstart

Use the MATLAB function [`jlcall.m`](https://github.com/jondeuce/JuliaFromMATLAB.jl/blob/master/api/jlcall.m) to call Julia from MATLAB:

```matlab
>> jlcall('sort', {rand(2,5)}, struct('dims', int64(2)))

ans =

    0.1270    0.2785    0.6324    0.8147    0.9575
    0.0975    0.5469    0.9058    0.9134    0.9649
```

The positional arguments passed to [`jlcall.m`](https://github.com/jondeuce/JuliaFromMATLAB.jl/blob/master/api/jlcall.m) are:
1. The Julia function to call, given as a MATLAB `char` array. This can be any Julia expression which evaluates to a function. For example, `'a=2; b=3; x -> a*x+b'`. **Note:** this expression is wrapped in a `let` block and evaluated in the global scope
2. Positional arguments, given as a MATLAB `cell` array. For example, `args = {arg1, arg2, ...}`
3. Keyword arguments, given as a MATLAB `struct`. For example, `kwargs = struct('key1', value1, 'key2', value2, ...)`

The first time [`jlcall.m`](https://github.com/jondeuce/JuliaFromMATLAB.jl/blob/master/api/jlcall.m) is invoked:
1. `JuliaFromMATLAB.jl` will be installed into a local Julia project, if one does not already exist. By default, a folder `.jlcall` is created in the same folder as [`jlcall.m`](https://github.com/jondeuce/JuliaFromMATLAB.jl/blob/master/api/jlcall.m)
2. A Julia server will be started in the background using [`DaemonMode.jl`](https://github.com/dmolina/DaemonMode.jl)

All subsequent calls to Julia are run on the Julia server.
The server will be automatically killed when MATLAB exits.

### Restarting the Julia server

In the event that the Julia server reaches an undesired state, the server can be restarted by passing the `'restart'` flag with value `true`:

```matlab
>> jlcall('x -> sum(abs2, x)', {1:5}, 'restart', true)

ans =

    55
```

### Julia multithreading

The Julia server can be started with multiple threads by passing the `'threads'` flag:

```matlab
>> jlcall('() -> Base.Threads.nthreads()', 'threads', 8, 'restart', true)

ans =

  int64

   8
```

The default value for `'threads'` is given by the output of the MATLAB function `maxNumCompThreads`.

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

By default, previously loaded Julia code is available on subsequent calls to [`jlcall.m`](https://github.com/jondeuce/JuliaFromMATLAB.jl/blob/master/api/jlcall.m).
For example, following the [above call](https://github.com/jondeuce/JuliaFromMATLAB.jl#loading-modules) to `LinearAlgebra.norm`, the `LinearAlgebra.det` function can be called without loading `LinearAlgebra` again:

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

Instead of running Julia code on a persistent Julia server, unique Julia instances can be launched for each call to [`jlcall.m`](https://github.com/jondeuce/JuliaFromMATLAB.jl/blob/master/api/jlcall.m) by passing the `'server'` flag with value `false`.

**Note:** this may cause significant overhead when repeatedly calling [`jlcall.m`](https://github.com/jondeuce/JuliaFromMATLAB.jl/blob/master/api/jlcall.m) due to Julia package precompilation and loading:

```matlab
>> tic; jlcall('x -> sum(abs2, x)', {1:5}, 'server', false); toc
Elapsed time is 4.181178 seconds. % call unique Julia instance

>> tic; jlcall('x -> sum(abs2, x)', {1:5}, 'restart', true); toc
Elapsed time is 5.046929 seconds. % re-initialize Julia server

>> tic; jlcall('x -> sum(abs2, x)', {1:5}); toc
Elapsed time is 0.267088 seconds. % call server; significantly faster
```

### Loading code from a local project

Code from a local Julia project can be loaded and called:

```matlab
>> jlcall('MyProject.my_function', args, kwargs, ...
    'project', '/path/to/MyProject', ...
    'modules', {'MyProject'})
```

**Note:** the value of the `'project'` flag is simply added to the Julia `LOAD_PATH`; it is the user's responsibility to ensure that the project's dependencies have been installed.

### Loading setup code

Julia functions may require or return types which cannot be directly passed from or loaded into MATLAB.
For example, suppose one would like to query `Base.VERSION`.
Naively calling `jlcall('() -> Base.VERSION')` would fail, as `typeof(Base.VERSION)` is not a `String` but a `VersionNumber`.

One possible remedy is to define a wrapper function in a Julia script:

```julia
# setup.jl
julia_version() = string(Base.VERSION)
```

Then, use the `'setup'` flag to pass the above script to [`jlcall.m`](https://github.com/jondeuce/JuliaFromMATLAB.jl/blob/master/api/jlcall.m):

```matlab
>> jlcall('julia_version', 'setup', '/path/to/setup.jl')

ans =

    '1.6.1'
```

In this case, `jlcall('() -> string(Base.VERSION)')` would work just as well.
In general, however, interfacing with complex Julia libraries using MATLAB types may be nontrivial, and the `'setup'` flag allows for the execution of arbitrary setup code.

**Note:** the setup script is loaded into the global scope using `include`; when using [persistent environments](https://github.com/jondeuce/JuliaFromMATLAB.jl#persistent-environments), symbols defined in the setup script will be available on subsequent calls to [`jlcall.m`](https://github.com/jondeuce/JuliaFromMATLAB.jl/blob/master/api/jlcall.m).

### Handling Julia outputs

Output(s) from Julia are returned using the MATLAB `cell` array [`varargout`](https://www.mathworks.com/help/matlab/ref/varargout.html), MATLAB's variable-length list of output arguments.
A helper function `JuliaFromMATLAB.matlabify` is used to convert Julia values into MATLAB-compatible values.
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
Returning to the example from the [above section](https://github.com/jondeuce/JuliaFromMATLAB.jl#loading-setup-code), we can define a `matlabify` method for `Base.VersionNumber`:

```julia
# setup.jl
JuliaFromMATLAB.matlabify(v::Base.VersionNumber) = string(v)
```

Now, the return type will be automatically converted:

```matlab
>> jlcall('() -> Base.VERSION', 'setup', '/path/to/setup.jl')

ans =

    '1.6.1'
```

### Performance

MATLAB inputs and Julia ouputs are passed back and forth between MATLAB and the `DaemonMode.jl` server by writing to temporary `.mat` files.
This naturally leads to some overhead when calling Julia, particularly when the MATLAB inputs and/or Julia outputs have large memory footprints.
It is therefore not recommended to use [`jlcall.m`](https://github.com/jondeuce/JuliaFromMATLAB.jl/blob/master/api/jlcall.m) in performance critical loops.

## MATLAB and Julia version compatibility

This package has been tested on a variety of MATLAB versions.
However, for some versions of Julia and MATLAB, supported versions of external libraries may clash.
For example, running [`jlcall.m`](https://github.com/jondeuce/JuliaFromMATLAB.jl/blob/master/api/jlcall.m) using Julia v1.6.1 and MATLAB R2015b gives the following error:

```matlab
>> jlcall

ERROR: Unable to load dependent library ~/.local/julia-1.6.1/bin/../lib/julia/libjulia-internal.so.1

Message: /usr/local/MATLAB/R2015b/sys/os/glnxa64/libstdc++.so.6: version `GLIBCXX_3.4.20' not found (required by ~/.local/julia-1.6.1/bin/../lib/julia/libjulia-internal.so.1)
```

This error results due to a clash of supported `libstdc++` versions, and does not occur when using e.g. Julia v1.5.4 with MATLAB R2015b, or Julia v1.6.1 with MATLAB R2020b.

If you encounter this issue, see the [`Julia`](https://github.com/JuliaLang/julia/blob/master/doc/build/build.md#required-build-tools-and-external-libraries) and [`MATLAB`](https://www.mathworks.com/support/requirements/supported-compilers.html) documentation for information on mutually supported external libraries.

## About this package

This repository contains utilities for parsing and running Julia code, passing MATLAB arguments to Julia, and retrieving Julia outputs from MATLAB.

The workhorse behind `JuliaFromMATLAB.jl` and [`jlcall.m`](https://github.com/jondeuce/JuliaFromMATLAB.jl/blob/master/api/jlcall.m) is [`DaemonMode.jl`](https://github.com/dmolina/DaemonMode.jl) which is used to start a persistent Julia server in the background.

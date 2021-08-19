# JuliaFromMATLAB.jl

<!-- [![stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://jondeuce.github.io/JuliaFromMATLAB.jl/stable) -->
<!-- [![dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://jondeuce.github.io/JuliaFromMATLAB.jl/dev) -->
[![build status](https://github.com/jondeuce/JuliaFromMATLAB.jl/workflows/CI/badge.svg)](https://github.com/jondeuce/JuliaFromMATLAB.jl/actions?query=workflow%3ACI)
[![codecov.io](https://codecov.io/github/jondeuce/JuliaFromMATLAB.jl/branch/master/graph/badge.svg)](http://codecov.io/github/jondeuce/JuliaFromMATLAB.jl/branch/master)

Call Julia from MATLAB.

## Quickstart

Use the MATLAB function [jlcall.m](https://github.com/jondeuce/JuliaFromMATLAB.jl/blob/master/api/jlcall.m) to call Julia from MATLAB:

```matlab
>> jlcall('sort', {rand(2,5)}, struct('dims', int64(2)))

ans =

    0.1270    0.2785    0.6324    0.8147    0.9575
    0.0975    0.5469    0.9058    0.9134    0.9649
```

The positional arguments passed to `jlcall.m` are:
1. The Julia function to call, given as a MATLAB `char` array. This can be any Julia expression which evaluates to a function. For example, `'let a=2, b=3; x -> a*x+b; end'`. **Note:** this expression is evaluated in the global scope
2. Positional input arguments, given as a MATLAB `cell` array. For example, `args = {arg1, arg2, ...}`
3. Keyword input arguments, given as a MATLAB `struct`. For example, `kwargs = struct('key1', value1, 'key2', value2, ...)`

The first time `jlcall.m` is invoked, a Julia server is started as a background process.
All calls to Julia are run on this server.
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

By default, previously loaded Julia code is available on subsequent calls to [jlcall.m](https://github.com/jondeuce/JuliaFromMATLAB.jl/blob/master/api/jlcall.m).
For example, following the above call to `LinearAlgebra.norm`, the `LinearAlgebra.det` function can be called without loading `LinearAlgebra` again:

```matlab
>> jlcall('LinearAlgebra.det', {[1.0 2.0; 3.0 4.0]})

ans =

    -2
```

### Unique environments

Set the `'shared'` flag to `false` in order to evaluate each Julia call in a separate namespace:

```matlab
% Restart the server, setting 'shared' to false
>> jlcall('LinearAlgebra.norm', {[3.0; 4.0]}, 'modules', {'LinearAlgebra'}, 'restart', true, 'shared', false)

ans =

     5

% This call would now error, despite the above command loading the LinearAlgebra module, as LinearAlgebra.norm is evaluated in a new namespace
>> jlcall('LinearAlgebra.norm', {[3.0; 4.0]}, 'shared', false)
```

### Loading code from a local project

Code from a local Julia project can be loaded and called:

```matlab
>> jlcall('MyProject.my_function', args, kwargs, ...
    'project', '/path/to/MyProject', ...
    'modules', {'MyProject'})
```

### Loading setup code

Julia functions may require or return types which cannot be directly passed from or loaded into MATLAB.
For example, suppose one would like to query `Base.VERSION`.
Naively calling `jlcall('() -> Base.VERSION')` would fail, as `typeof(Base.VERSION)` is not a `String` but a `VersionNumber`.

One possible remedy is to define a wrapper function:

```julia
# setup.jl
julia_version() = string(Base.VERSION)
```

Then, use the `'setup'` flag to pass the above script to [jlcall.m](https://github.com/jondeuce/JuliaFromMATLAB.jl/blob/master/api/jlcall.m):


```matlab
>> jlcall('julia_version', 'setup', '/path/to/setup.jl')

ans =

    '1.6.1'
```

In this case, `jlcall('() -> string(Base.VERSION)')` would work just as well.
In general, however, interfacing with complex Julia libraries using MATLAB types may be nontrivial, and the `'setup'` flag allows for the execution of arbitrary setup code.

## Internals

This repository contains utilities for parsing and running Julia code, MATLAB input arguments, and other settings received via [jlcall.m](https://github.com/jondeuce/JuliaFromMATLAB.jl/blob/master/api/jlcall.m).

The workhorse behind `JuliaFromMATLAB.jl` and `jlcall.m` is [DaemonMode.jl](https://github.com/dmolina/DaemonMode.jl) which is used to start a persistent Julia server in the background.
MATLAB inputs and Julia ouputs are passed back and forth between MATLAB and the `DaemonMode.jl` server by writing to temporary `.mat` files.

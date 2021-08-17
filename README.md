# JuliaFromMATLAB.jl

<!-- [![stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://jondeuce.github.io/JuliaFromMATLAB.jl/stable) -->
[![dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://jondeuce.github.io/JuliaFromMATLAB.jl/dev)
[![build status](https://github.com/jondeuce/JuliaFromMATLAB.jl/workflows/CI/badge.svg)](https://github.com/jondeuce/JuliaFromMATLAB.jl/actions?query=workflow%3ACI)
[![codecov.io](https://codecov.io/github/jondeuce/JuliaFromMATLAB.jl/branch/master/graph/badge.svg)](http://codecov.io/github/jondeuce/JuliaFromMATLAB.jl/branch/master)

Call Julia from Matlab.

## Quickstart

Use the MATLAB function [jlcall.m](https://github.com/jondeuce/JuliaFromMATLAB.jl/blob/master/api/jlcall.m) to call Julia from MATLAB:

```matlab
>> jlcall('x -> sum(abs2, x)', {1:5})

ans =

    55
```

Julia modules can be loaded and used:


```matlab
>> jlcall('LinearAlgebra.norm', {[3.0; 4.0]}, 'modules', {'LinearAlgebra'})

ans =

     5
```

**Note:** all symbols must be fully qualified, i.e. `LinearAlgebra.norm` in the above example as opposed to `norm`.

By default, previously loaded Julia modules are available on subsequent calls to [jlcall.m](https://github.com/jondeuce/JuliaFromMATLAB.jl/blob/master/api/jlcall.m):

```matlab
>> jlcall('LinearAlgebra.det', {[1.0 2.0; 3.0 4.0]})

ans =

    -2
```

Set the `'shared'` flag to `false` in order to evaluate each call in a separate namespace:

```matlab
% Restart the server, setting 'shared' to false
>> jlcall('LinearAlgebra.norm', {[3.0; 4.0]}, 'modules', {'LinearAlgebra'}, 'restart', true, 'shared', false)

ans =

     5

% This call would now error, as the LinearAlgebra module is not available in the new namespace
>> jlcall('LinearAlgebra.norm', {[3.0; 4.0]}, 'shared', false)
```

## JuliaFromMATLAB.jl

This repository contains utilities for parsing and running Julia code, MATLAB input arguments, and other settings received via [jlcall.m](https://github.com/jondeuce/JuliaFromMATLAB.jl/blob/master/api/jlcall.m).

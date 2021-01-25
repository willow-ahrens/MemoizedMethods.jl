# MemoizedMethods.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://peterahrens.github.io/MemoizedMethods.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://peterahrens.github.io/MemoizedMethods.jl/dev)
[![Build Status](https://github.com/peterahrens/MemoizedMethods.jl/workflows/CI/badge.svg)](https://github.com/peterahrens/MemoizedMethods.jl/actions)
[![Coverage](https://codecov.io/gh/peterahrens/MemoizedMethods.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/peterahrens/MemoizedMethods.jl)

Methodwise memoization for Julia, supporting all the corner cases. 

## Usage

```julia
using MemoizedMethods
@memoize function x(a)
	println("Running")
	2a
end
```

```
julia> x(1)
Running
2

julia> memories(x)
1-element Array{Any,1}:
 IdDict{Any,Any}((1,) => 2)

julia> x(1)
2

julia> map(empty!, memories(x))
1-element Array{IdDict{Tuple{Any},Any},1}:
 IdDict()

julia> x(1)
Running
2

julia> x(1)
2
```

By default, MemoizedMethods.jl uses an [`IdDict`](https://docs.julialang.org/en/v1/base/collections/#Base.IdDict) as a cache, but it's also possible to specify the type of the cache. If you want to cache vectors based on the values they contain, you probably want this:

```julia
using Memoize
@memoize Dict function x(a)
	println("Running")
	a
end
```

You can also specify the full function call for constructing the dictionary. For example, to use LRUCache.jl:

```julia
using Memoize
using LRUCache
@memoize LRU{Tuple{Any,Any},Any}(maxsize=2) function x(a, b)
    println("Running")
    a + b
end
```

```julia
julia> x(1,2)
Running
3

julia> x(1,2)
3

julia> x(2,2)
Running
4

julia> x(2,3)
Running
5

julia> x(1,2)
Running
3

julia> x(2,3)
5
```

## Notes

Note that the `@memoize` macro treats the type argument differently depending on its syntactical form: in the expression
```julia
@memoize CacheType function x(a, b)
    # ...
end
```
the expression `CacheType` must be either a non-function-call that evaluates to a type, or a function call that evaluates to an _instance_ of the desired cache type.  Either way, the methods `Base.get!` and `Base.empty!` must be defined for the supplied cache type.

This package was forked from [Memoize.jl](https://github.com/JuliaCollections/Memoize.jl) to support more corner cases and different syntax.
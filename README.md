# MemoizedMethods.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://peterahrens.github.io/MemoizedMethods.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://peterahrens.github.io/MemoizedMethods.jl/dev)
[![Build Status](https://github.com/peterahrens/MemoizedMethods.jl/workflows/CI/badge.svg)](https://github.com/peterahrens/MemoizedMethods.jl/actions)
[![Coverage](https://codecov.io/gh/peterahrens/MemoizedMethods.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/peterahrens/MemoizedMethods.jl)

Methodwise memoization for Julia. Use any function definition syntax at any scope! Specialize custom dictionary types with straightforward syntax! Don't compute the same thing twice!

## Usage

```julia
using MemoizedMethods
@memoize function f(x, y) where {X}
	println("run")
	x + y
end
```

```julia-repl
julia> f(1, 1)
run
2

julia> f(1, 2)
run
3

julia> f(1, 1)
2
```

By default, MemoizedMethods.jl uses an [`IdDict`](https://docs.julialang.org/en/v1/base/collections/#Base.IdDict) as a cache, but you can specify an expression that evaluates to a cache of your very own, so long as it supports the methods `Base.get!` and `Base.empty!`. If you want to cache vectors based on the values they contain, you probably want this:

```julia
using Memoize
@memoize Dict() function x(a)
	println("run")
	a
end
```

The variables `__Key__` and `__Value__` are available to the constructor expression, containing syntactically determined type bounds on the keys and values used by MemoizedMethods.jl. Here's an example using [LRUCache.jl](https://github.com/JuliaCollections/LRUCache.jl):

```julia
using Memoize
using LRUCache
@memoize LRU{__Key__,__Value__}(maxsize=2) function x(a, b)
    println("run")
    a + b
end
```

```julia-repl
julia> x(1,2)
run
3

julia> x(1,2)
3

julia> x(2,2)
run
4

julia> x(2,3)
run
5

julia> x(1,2)
run
3

julia> x(2,3)
5
```

MemoizedMethods works on *almost* every function declaration in global and local scope, including lambdas and callable objects. Each method and scope is memoized with a separate cache. When an argument is unnamed, MemoizedMethods only uses the type of the argument as a key to the cache. Callable types and callable objects are keyed as an extra first argument.

```julia
struct F{A}
	a::A
end
@memoize function (f::F{A})(b, ::C) where {A, C}
	println("run")
	(f.a + b, C)
end
```

```julia-repl
julia> F(1)(1, "hello")
run
(2, String)

julia> F(1)(1, "goodbye")
(2, String)

julia> F(1)(2, "goodbye")
run
(3, String)

julia> F(1)(2, false)
run
(3, Bool)

julia> F(2)(2, false)
run
(4, Bool)
```

This package was forked from [Memoize.jl](https://github.com/JuliaCollections/Memoize.jl) to support extra corner cases and features. Thanks to all of the Memoize.jl contributors.
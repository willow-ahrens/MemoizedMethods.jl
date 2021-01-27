# MemoizedMethods.jl

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://peterahrens.github.io/MemoizedMethods.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://peterahrens.github.io/MemoizedMethods.jl/dev)
[![Build Status](https://github.com/peterahrens/MemoizedMethods.jl/workflows/CI/badge.svg)](https://github.com/peterahrens/MemoizedMethods.jl/actions)
[![Coverage](https://codecov.io/gh/peterahrens/MemoizedMethods.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/peterahrens/MemoizedMethods.jl)

Methodwise memoization for Julia. Use any function definition syntax at any scope! Specialize custom dictionary types with straightforward syntax! Don't compute the same thing twice!

## Usage

```julia
using MemoizedMethods
@memoize function f(x, y)
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

You can look up caches with the function `memories`, and clear caches with the function `forget!`, both of which take the same arguments as the
function `Base.which`. You can also directly specify a `Base.Method` or `Base.MethodList` (returned from e.g. `Base.methods`).

```julia-repl
julia> memories(methods(x))
#TODO

julia> memories(x, Tuple{Int, Int})
#TODO

julia> x(2,3)
5

julia> forget!(x, Tuple{Int, Int})

julia> x(2,3)
run
5
```

## Details

MemoizedMethods works on *almost* every function declaration in global and local scope, including lambdas and callable objects. Each method and scope is memoized with a separate cache. When an argument is unnamed, MemoizedMethods uses only the type of the argument as a key to the cache. Callable types and callable objects are keyed as an extra first argument.

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

Each scope of an inner function gets its own cache. MemoizedMethods avoids tracking inner caches so that that they can be garbage collected. Thus, you can't reference inner caches with `Method` objects. To clear the cache of a closure, you must pass an instance of the closure itself to `forget!`.

```julia
function h(x)
	@memoize function f(y)
		println("run")
		x + y
	end
end
f1 = h(1)
f2 = h(2)
```

```julia-repl
julia> f1(3)
run
4

julia> f1(3)
4

julia> f2(3)
run
5

julia> f2(3)
5

julia> forget!(f1)

julia> f1(3)
run
4

julia> f2(3)
5
```

MemoizedMethods expands to a function that closes over a variable holding the cache. The cache is also referenced in a global structure for later lookups. If a method is overwritten at global scope, MemoizedMethods automatically calls `empty!` on the old cache. Roughly, our starter example

```julia
@memoize function f(x, y)
	println("run")
	x + y
end
```
expands to something like
```julia
using MemoizedMethods
local cache = IdDict()
function f(x, y)
	get!(cache, (x, y)) do
		println("run")
		x + y
	end
end
```

## Thanks

This package was forked from [Memoize.jl](https://github.com/JuliaCollections/Memoize.jl) to support extra corner cases and features. Thanks to all of the Memoize.jl contributors.
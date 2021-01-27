using BenchmarkTools

using Memoize
using Memoization
using MemoizedMethods

Memoize.@memoize fib_Memoize(n::Int) = n <= 1 ? 1 : fib_Memoize(n - 1) + fib_Memoize(n - 2)
Memoization.@memoize fib_Memoization(n::Int) = n <= 1 ? 1 : fib_Memoization(n - 1) + fib_Memoization(n - 2)
MemoizedMethods.@memoize fib_MemoizedMethods(n::Int) = n <= 1 ? 1 : fib_MemoizedMethods(n - 1) + fib_MemoizedMethods(n - 2)

N = 10000

println("fib_Memoize($N):")
@btime fib_Memoize($N) setup = empty!(Memoize.memoize_cache(fib_Memoize))

println("fib_Memoization($N):")
@btime fib_Memoization($N) setup = Memoization.empty_cache!(fib_Memoization)

println("fib_MemoizedMethods($N):")
@btime fib_MemoizedMethods($N) setup = map(forget!, methods(fib_MemoizedMethods))
using BenchmarkTools

using Memoize
using Memoization
using MemoizedMethods

Memoize.@memoize fib_Memoize(n::Int)::Int = n <= 1 ? 1 : fib_Memoize(n - 1) + fib_Memoize(n - 2)
Memoization.@memoize fib_Memoization(n::Int)::Int = n <= 1 ? 1 : fib_Memoization(n - 1) + fib_Memoization(n - 2)
MemoizedMethods.@memoize fib_MemoizedMethods(n::Int)::Int = n <= 1 ? 1 : fib_MemoizedMethods(n - 1) + fib_MemoizedMethods(n - 2)

const N = 10000

println("Default IdDict (initialize):")

println("fib_Memoize($N):")
@time fib_Memoize(N)

println("fib_Memoization($N):")
@time fib_Memoization(N)

println("fib_MemoizedMethods($N):")
@time fib_MemoizedMethods(N)

println()
println("Default IdDict (refill):")

println("fib_Memoize($N):")
@btime fib_Memoize($N) setup = empty!(Memoize.memoize_cache(fib_Memoize))

println("fib_Memoization($N):")
@btime fib_Memoization($N) setup = Memoization.empty_cache!(fib_Memoization)

println("fib_MemoizedMethods($N):")
@btime fib_MemoizedMethods($N) setup = map(forget!, methods(fib_MemoizedMethods))

# Note that for Memoize and Memoization, we cannot overwrite the old cache without supplying a new function name.
Memoize.@memoize Dict{Tuple{Int64}}{Int} fib_Memoize_2(n::Int)::Int = n <= 1 ? 1 : fib_Memoize_2(n - 1) + fib_Memoize_2(n - 2)
Memoization.@memoize Dict{Tuple{Tuple{Int64},NamedTuple{(),Tuple{}}}}{Int} fib_Memoization_2(n::Int)::Int = n <= 1 ? 1 : fib_Memoization_2(n - 1) + fib_Memoization_2(n - 2)
MemoizedMethods.@memoize Dict{__Key__}{__Value__}() fib_MemoizedMethods(n::Int)::Int = n <= 1 ? 1 : fib_MemoizedMethods(n - 1) + fib_MemoizedMethods(n - 2)

println()
println("Typed Dict (initialize):")

println("fib_Memoize($N):")
@time fib_Memoize_2(N)

println("fib_Memoization($N):")
@time fib_Memoization_2(N)

println("fib_MemoizedMethods($N):")
@time fib_MemoizedMethods(N)

println()
println("Typed Dict (refill):")

println("fib_Memoize($N):")
@btime fib_Memoize_2($N) setup = empty!(Memoize.memoize_cache(fib_Memoize_2))

println("fib_Memoization($N):")
@btime fib_Memoization_2($N) setup = Memoization.empty_cache!(fib_Memoization_2)

println("fib_MemoizedMethods($N):")
@btime fib_MemoizedMethods($N) setup = map(forget!, methods(fib_MemoizedMethods))
module MemoizedMethods
using MacroTools: isexpr, combinearg, combinedef, namify, splitarg, splitdef, @capture
export @memoize, forget!

# which($sig) becomes available in Julia 1.6, so here's a workaround
function _which(tt)
    meth = ccall(:jl_gf_invoke_lookup, Any, (Any, UInt), tt, typemax(UInt))
    if meth !== nothing
        if meth isa Method
            return meth::Method
        else
            meth = meth.func
            return meth::Method
        end
    end
end

"""
    @memoize [cache] declaration
    
    Transform any method declaration `declaration` (except for inner constructors) so that calls to the original method are cached by their arguments. When an argument is unnamed, its type is treated as an argument instead.
    
    `cache` should be an expression which evaluates to a dictionary-like type that supports `get!` and `empty!`, and may depend on the local variables `__Key__` and `__Value__`, which evaluate to syntactically-determined bounds on the required key and value types the cache must support.

    If the given cache contains values, it is assumed that they will agree with the values the method returns. Specializing a method will not empty the cache, but overwriting a method will. The caches corresponding to methods can be determined with `memory` or `memories.`
"""
macro memoize(args...)
    if length(args) == 1
        cache_constructor = :(IdDict{__Key__}{__Value__}())
        ex = args[1]
    elseif length(args) == 2
        (cache_constructor, ex) = args
    else
        error("Memoize accepts at most two arguments")
    end

    def = try
        splitdef(ex)
    catch
        error("@memoize must be applied to a method definition")
    end

    function split(arg, iskwarg=false)
        arg_name, arg_type, slurp, default = splitarg(arg)
        trait = arg_name === nothing
        trait && (arg_name = gensym())
        vararg = namify(arg_type) === :Vararg
        return (
            arg_name = arg_name,
            arg_type = arg_type,
            arg_value = arg_name,
            slurp = slurp,
            vararg = vararg,
            default = default,
            trait = trait,
            iskwarg = iskwarg)
    end

    combine(arg) = combinearg(arg.arg_name, arg.arg_type, arg.slurp, arg.default)

    pass(arg) =
        (arg.slurp || arg.vararg) ? Expr(:..., arg.arg_name) :
            arg.iskwarg ? Expr(:kw, arg.arg_name, arg.arg_name) : arg.arg_name

    dispatch(arg) = arg.slurp ? :(Vararg{$(arg.arg_type)}) : arg.arg_type

    args = split.(def[:args])
    kwargs = split.(def[:kwargs], true)
    def[:args] = combine.(args)
    def[:kwargs] = combine.(kwargs)
    @gensym inferrable
    inferrable_def = deepcopy(def)
    inferrable_def[:name] = inferrable
    inferrable_args = copy(args)
    inferrable_kwargs = copy(kwargs)
    pop!(inferrable_def, :params, nothing)
    @gensym result

    # If this is a method of a callable type or object, the definition returns nothing.
    # Thus, we must construct the type of the method on our own.
    # We also need to pass the object to the inferrable function
    if haskey(def, :name)
        if haskey(def, :params) # Callable type
            typ = :($(def[:name]){$(pop!(def, :params)...)})
            inferrable_args = [split(:(::Type{$typ})), inferrable_args...]
            def[:name] = combine(inferrable_args[1])
            head = :(Type{$typ})
        elseif @capture(def[:name], obj_::obj_type_ | ::obj_type_) # Callable object
            inferrable_args = [split(def[:name]), inferrable_args...]
            def[:name] = combine(inferrable_args[1])
            head = obj_type
        else # Normal call
            head = :(typeof($(def[:name])))
            name = def[:name]
        end
        sig = :(Tuple{$head, $(dispatch.(args)...)} where {$(def[:whereparams]...)})
    else # Anonymous function
        head = :(typeof($result))
    end
    tail = :(Tuple{$(dispatch.(args)...)} where {$(def[:whereparams]...)})

    inferrable_def[:args] = combine.(inferrable_args)

    # Set up arguments for memo key
    key_names = map([inferrable_args; inferrable_kwargs]) do arg
        arg.trait ? arg.arg_type : arg.arg_name
    end
    key_types = map([inferrable_args; inferrable_kwargs]) do arg
        arg.trait ? DataType :
        arg.vararg ? :(Tuple{$(arg.arg_type)}) :
            arg.arg_type
    end

    cache = gensym(:__cache__)

    pass_args = pass.(inferrable_args)
    pass_kwargs = pass.(inferrable_kwargs)
    def[:body] = quote
        get!($cache[2], ($(key_names...),)) do
            $(def[:body])
        end
    end

    # A return type declaration of Any is a No-op because everything is <: Any
    return_type = get(def, :rtype, Any)

    #=
    To improve inference in kwarg cases, might want to look into these functions
    @which f(1; k=2)
    return_type = InteractiveUtils.gen_call_with_extracted_types(Main, :(Core.Compiler.return_type), :($inferrable()))
        #= /Users/Peter/Projects/julia/usr/share/julia/stdlib/v1.5/InteractiveUtils/src/macros.jl:86 =#
        local arg1 = $(Expr(:escape, :f))
        #= /Users/Peter/Projects/julia/usr/share/julia/stdlib/v1.5/InteractiveUtils/src/macros.jl:87 =#
        local (args, kwargs) = (InteractiveUtils.separate_kwargs)($(Expr(:escape, :($(Expr(:parameters, :($(Expr(:kw, :k, 2)))))))), $(Expr(:escape, 1)))
        #= /Users/Peter/Projects/julia/usr/share/julia/stdlib/v1.5/InteractiveUtils/src/macros.jl:88 =#
        Core.Complier.return_type(Core.kwfunc(arg1), Tuple{typeof(kwargs), Core.Typeof(arg1), map(Core.Typeof, args)...}; )

    Core.kwfunc(arg1)   
    :($(Expr(:parameters, :($(Expr(:kw, :k, 2)))))))
    =#

    if length(kwargs) == 0
        def[:body] = quote
            $(def[:body])::Core.Compiler.widenconst(Core.Compiler.return_type($inferrable, typeof(($(pass_args...),))))
        end
    end


    scope = gensym()

    quote
        # The `local` qualifier will make this performant even in the global scope.
        $(esc(quote
            local $cache = begin
                local __Key__ = (Tuple{$(key_types...)} where {$(def[:whereparams]...)})
                local __Value__ = ($return_type where {$(def[:whereparams]...)})
                ($tail, $cache_constructor)
            end
        end))

        $(esc(scope)) = nothing

        $(if @isdefined sig
            quote
                if isdefined($__module__, $(QuoteNode(scope)))
                    $(if @isdefined name
                        esc(:(function $name end))
                    end)

                    # If overwriting a method, empty the old cache.
                    # Notice that methods are hashed by their stored signature
                    local meth = $_which($(esc(sig)))
                    if meth != nothing && meth.sig == $(esc(sig)) && isdefined(meth.module, :__memories__)
                        empty!(pop!(meth.module.__memories__, meth.sig, (nothing, []))[2])
                    end
                end
            end
        end)

        $(esc(combinedef(inferrable_def)))
        local $(esc(result)) = Base.@__doc__($(esc(combinedef(def))))

        $(if @isdefined sig
            quote
                if isdefined($__module__, $(QuoteNode(scope)))
                    if !isdefined($__module__, :__memories__)
                        $(esc(:__memories__)) = IdDict()
                    end
                    # Store the cache so that it can be emptied later
                    local meth = $_which($(esc(sig)))
                    $(esc(:__memories__))[meth.sig] = $(esc(cache))
                end
            end
        end)

        $(esc(result))
    end
end

"""
    forget!(f, types)
    
    If the method `which(f, types)`, is memoized, `empty!` its cache in the
    scope of `f`.
"""
function forget!(f, types)
    for name in propertynames(f) #if f is a closure, we walk its fields
        if first(string(name), length("##__cache__")) == "##__cache__"
            cache = getproperty(f, name)
            if cache isa Core.Box
                cache = cache.contents
            end
            (cache[1] == types) && empty!(cache[2])
        end
    end
    forget!(which(f, types)) #otherwise, a method would suffice
end

"""
    forget!(m::Method)
    
    If m, defined at global scope, is a memoized function, `empty!` its
    cache.
"""
function forget!(m::Method)
    if isdefined(m.module, :__memories__)
        empty!(get(m.module.__memories__, m.sig, (nothing, []))[2])
    end
end

end

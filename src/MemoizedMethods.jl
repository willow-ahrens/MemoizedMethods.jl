module MemoizedMethods
using MacroTools: isexpr, combinearg, combinedef, namify, splitarg, splitdef, @capture
export @memoize, memories, forget!

const salt = :__UYTBOOUDVEWICBEWNMDO__ #Symbol(:__, join(rand('A':'Z', 20)), :__)

# which($sig) becomes available in Julia 1.6, so here's a workaround
function _which(tt, world=typemax(UInt))
    meth = ccall(:jl_gf_invoke_lookup, Any, (Any, UInt), tt, world)
    if meth !== nothing
        if meth isa Method
            return meth::Method
        else
            meth = meth.func
            return meth::Method
        end
    end
end

# get_world_counter was never exported, so here's a workaround
_get_world_counter() = ccall(:jl_get_world_counter, UInt, ())

"""
    @memoize [cache] declaration
    
    Transform any method declaration `declaration` (except for inner constructors) so that calls to the original method are cached by their arguments. When an argument is unnamed, its type is treated as an argument instead.
    
    `cache` should be an expression which evaluates to a dictionary-like type that supports `get!` and `empty!`, and may depend on the local variables `__Key__` and `__Value__`, which evaluate to syntactically-determined bounds on the required key and value types the cache must support.

    If the given cache contains values, it is assumed that they will agree with the values the method returns. Specializing a method will not empty the cache, but overwriting a method will. The caches corresponding to methods can be determined with `memory` or `memories.`
"""
macro memoize(args...)
    if length(args) == 1
        cache_constructor = :(IdDict())
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

    pass(arg) = (arg.slurp || arg.vararg) ? Expr(:..., arg.arg_name) :
        arg.iskwarg ? Expr(:kw, arg.arg_name, arg.arg_name) : arg.arg_name

    dispatch(arg) = arg.slurp ? :(Vararg{$(arg.arg_type)}) : arg.arg_type

    key(arg) = arg.trait ? arg.arg_type : arg.arg_name

    key_type(arg) = arg.trait ? DataType :
        arg.vararg ? :(Tuple{$(arg.arg_type)}) : arg.arg_type

    args = split.(def[:args])
    kwargs = split.(def[:kwargs], true)
    def[:args] = combine.(args)
    def[:kwargs] = combine.(kwargs)
    @gensym inferrable
    inferrable_def = deepcopy(def)
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
            #Named inner function definitions are sometimes evaluated
            #asynchronously, and only use Symbols as the function name
            #in both the local and global cases, its safe to name the
            #inference function after the function name, since they
            #dispatch identically. Naming them after the same function
            #name ensures that the symbol is defined when it needs to be.
            if def[:name] isa Symbol 
                inferrable = Symbol(def[:name], :_inferrable, salt)
            end
        end
        sig = :(Tuple{$head, $(dispatch.(args)...)} where {$(def[:whereparams]...)})
    else # Anonymous function
        head = :(typeof($result))
    end
    tail = :(Tuple{$(dispatch.(args)...)} where {$(def[:whereparams]...)})

    inferrable_def[:name] = inferrable
    inferrable_def[:args] = combine.(inferrable_args)

    cache = gensym(Symbol(:cache, salt))
    bank = Symbol(:bank, salt)

    @gensym inner
    def[:body] = quote
        begin
            $inner = () -> $inferrable($(pass.(inferrable_args)...); $(pass.(inferrable_kwargs)...))
            $(get!)($inner, $cache[2], ($(map(key, [inferrable_args; inferrable_kwargs])...),))
        end::$(Core.Compiler.widenconst)($(Core.Compiler.return_type)($inner, $(Tuple{})))
    end

    scope = gensym()

    quote
        # The `local` qualifier will make this performant even in the global scope.
        $(esc(quote
            local $cache = begin
                local __Key__ = (Tuple{$(map(key_type, [inferrable_args; inferrable_kwargs])...)} where {$(def[:whereparams]...)})
                local __Value__ = ($(get(def, :rtype, Any)) where {$(def[:whereparams]...)})
                ($tail, $cache_constructor)
            end
        end))

        $(esc(scope)) = nothing

        $(if @isdefined sig
            quote
                if isdefined($__module__, $(QuoteNode(scope)))
                    local world = _get_world_counter()
                end
            end
        end)

        $(esc(combinedef(inferrable_def)))
        local $(esc(result)) = Base.@__doc__($(esc(combinedef(def))))

        $(if @isdefined sig
            quote
                if isdefined($__module__, $(QuoteNode(scope)))
                    # If overwriting a method, empty the old cache.
                    # Notice that methods are hashed by their stored signature
                    local meth = $_which($(esc(sig)), world)
                    if meth != nothing && meth.sig == $(esc(sig)) && isdefined(meth.module, $(Expr(:quote, bank)))
                        empty!(pop!(meth.module.$bank, meth.sig, (nothing, []))[2])
                    end

                    if !isdefined($__module__, $(Expr(:quote, bank)))
                        $(esc(bank)) = IdDict()
                    end
                    # Store the cache so that it can be emptied later
                    local meth = $_which($(esc(sig)))
                    $(esc(bank))[meth.sig] = $(esc(cache))
                end
            end
        end)

        $(esc(result))
    end
end

"""
    memories(f, types::Type)
    
    If the method `which(f, types)`, is memoized, return the cache in the
    scope of `f`. Otherwise, return `nothing` or an overwritten cache.
"""
function memories(f, types)
    m = which(f, types)
    types = Tuple{m.sig.parameters[2:end]...}
    for name in propertynames(f) #if f is a closure, we walk its fields
        if first(string(name), length(string("##cache", salt))) == string("##cache", salt)
            cache = getproperty(f, name)
            if cache isa Core.Box
                cache = cache.contents
            end
            if (cache[1] == types) 
                return cache[2]
            end
        end
    end
    return memories(m) #otherwise, a method would suffice
end

"""
    memories(m::Method)
    
    If m is a memoized method defined at global scope, return its cache.
    Otherwise, return `nothing` or an overwritten cache.
"""
function memories(m::Method)
    if isdefined(m.module, Symbol(:bank, salt))
        return get(getproperty(m.module, Symbol(:bank, salt)), m.sig, (nothing, nothing))[2]
    end
    return nothing
end

"""
    forget!(f, types::Type)
        
    If the method `which(f, types)`, is memoized, `empty!` the cache in the
    scope of `f`.
"""
function forget!(f, types::Type)
    c = memories(f, types)
    if c !== nothing
        return empty!(c)
    else
        return nothing
    end
end

"""
    forget!(m::Method)
        
    If the method `m`, is memoized, `empty!` its cache.
"""
function forget!(m::Method)
    c = memories(m)
    if c !== nothing
        return empty!(c)
    else
        return nothing
    end
end

end

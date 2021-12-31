struct TypedKey{T}
    key::T
end

getkey(x::TypedKey) = x.key

Base.hash(x::TypedKey{T}) where {T} = hash((T, x.key))
Base.hash(x::TypedKey{T}, h::UInt) where {T} = hash((T, x.key), h)
Base.==(x::TypedKey{T}, y::TypedKey{S}) where {T, S} = (T, x.key) == (S, y.key)

"""
    TypedDict(data)

`TypedDict(data)` wraps its keys in a `TypedKey` wrapper before passing them to the `AbstractDict` which backs the collection named `data`.

TypedDict modifies dictionaries which normally compare with `==` to also check that the concrete argument types are `==`.
"""
struct TypedDict{K,V,D<:AbstractDict{TypedKey{K}, V}} <: AbstractDict{K,V}
    data::D
end

TypedDict(data::D) where {K, V, D <: AbstractDict{TypedKey{K}, V}} = TypedDict{K, V, D}(data)

function Base.length(d::TypedDict)
    length(d.data)
end

function Base.isempty(d::TypedDict)
    isempty(d.data)
end

function Base.haskey(d::TypedDict, key)
    return haskey(d.data, TypedKey(key))
end

function Base.get(d::TypedDict, key, default)
    return get(d.data, TypedKey(key), default)
end

function Base.get(f::Union{Function, Type}, d::TypedDict, key)
    return get(f, d.data, TypedKey(key))
end

function Base.getindex(d::TypedDict, key)
    return d.data[TypedKey(key)]
end

function Base.keys(d::TypedDict)
    map(getkey, keys(d.data))
end

function Base.values(d::TypedDict)
    values(d.data)
end

Base.pairs(d::TypedDict) = d

function Base.iterate(d::TypedDict)
    ((key, value), state) = iterate(d.data)
    return (getkey(key) => value, state)
end

Base.iterate(d::TypedDict, state) = iterate(d.data, state)

function Base.get!(d::TypedDict, key, default)
    get!(d.data, TypedKey(key), default)
end

function Base.get!(f::Union{Function, Type}, d::TypedDict, key)
    get!(f, d.data, TypedKey(key))
end

function Base.setindex!(d::TypedDict, value, key)
    d.data[TypedKey(key)] = value
end

function Base.delete!(d::TypedDict, key)
    delete!(d.data, TypedKey(key))
end

function Base.pop!(d::TypedDict)
    pop!(d.data)
end

function Base.pop!(d::TypedDict, key)
    pop!(d.data, TypedKey(key))
end

function Base.pop!(d::TypedDict, key, default)
    pop!(d.data, TypedKey(key), default)
end

function Base.empty!(d::TypedDict) where {K, V}
    empty!(d)
end

end
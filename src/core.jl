# Core types and definitions

immutable AxisArray{T,N,D<:AbstractArray,names,Ax,AxElts} <: AbstractArray{T,N}
    data::D
    axes::Ax
end
# Allow AxisArrays that are missing dimensions and/or names?
AxisArray{T,N}(A::AbstractArray{T,N}, axes::(AbstractVector...)=()) =
    AxisArray(A, axes, N==0 ? () : N==1 ? (:row,) : N==2 ? (:row,:col) : (:row,:col,:page))
stagedfunction AxisArray{T,N}(A::AbstractArray{T,N}, axes::(AbstractVector...), names::(Symbol...))
    Ax = axes == Type{()} ? () : axes # Tuple's Type/Value duality is painful
    AxElts = map(eltype,Ax)
    :(AxisArray{T,N,$A,names,$Ax,$AxElts}(A, axes))
end

# Type-stable axis-specific indexing and identification with a parametric type:
immutable Axis{name,T}
    I::T
end
# Constructed exclusively through Axis{:symbol}(...)
call{name,T}(::Type{Axis{name}}, I::T=()) = Axis{name,T}(I)
Base.isempty(ax::Axis) = isempty(ax.I)
# TODO: I'd really like to only have one of axisnames/axisname.
axisname(ax::Axis) = axisname(typeof(ax))
axisname{name,T}(::Type{Axis{name,T}}) = name
axisname{name}(::Type{Axis{name}}) = name # Invariance. Is this a real concern?

# Base definitions that aren't provided by AbstractArray
Base.size(A::AxisArray) = size(A.data)
Base.linearindexing(A::AxisArray) = Base.linearindexing(A.data)

# Custom methods specific to AxisArrays
axisnames(A::AxisArray) = axisnames(typeof(A))
axisnames{T,N,D,names,Ax,AxElts}(::Type{AxisArray{T,N,D,names,Ax,AxElts}}) = names
axisnames{T,N,D,names,Ax}(::Type{AxisArray{T,N,D,names,Ax}}) = names
axisnames{T,N,D,names}(::Type{AxisArray{T,N,D,names}}) = names
axes(A::AxisArray) = A.axes
axes(A::AxisArray,i::Int) = A.axes[i]

### Indexing returns either a scalar or a smartly-subindexed AxisArray ###

# Limit indexing to types supported by SubArrays, at least initially
typealias Idx Union(Colon,Int,Array{Int,1},Range{Int})

# Simple scalar indexing where we return scalars
Base.getindex(A::AxisArray) = A.data[]
Base.getindex{T,N,D,names,Ax,AxElt}(A::AxisArray{T,N,D,names,Ax,AxElt}) = A.data[]
let args = Expr[], idxs = Symbol[]
    for i = 1:4
        isym = symbol("i$i")
        push!(args, :($isym::Int))
        push!(idxs, isym)
        @eval Base.getindex{T}(A::AxisArray{T,$i}, $(args...)) = A.data[$(idxs...)]
    end
end
Base.getindex{T,N}(A::AxisArray{T,N}, idxs::Int...) = A.data[idxs...]

# TODO: don't do this. This is needed for nonscalar identification of `:`
Base.ndims(::Type{Colon}) = 1
Base.ndims(::Colon) = 1

# More complicated cases where we must create a subindexed AxisArray
# TODO: do we want to be dogmatic about using views? For the data? For the axes?
# TODO: perhaps it would be better to return an entirely lazy SubAxisArray view
# TODO: avoid splatting for low dimensions by splitting into a function
# TODO: what does linear indexing with ranges mean with regards to axes?
stagedfunction Base.getindex{T,N,D,names,Ax,AxElt}(A::AxisArray{T,N,D,names,Ax,AxElt}, idxs::Idx...)
    # There might be a case here for preserving trailing scalar dimensions
    # within the axes... but for now let's drop them.
    nonscalardims = map(x->ndims(x) > 0, idxs) # this is pretty hacky
    newdims = findlast(nonscalardims)
    # TODO: can we pass names in a type-stable manner? https://github.com/JuliaLang/julia/issues/10191
    newnames = names[1:min(newdims, length(names))]
    newaxes = Ax[1:min(newdims, length(Ax))]
    newaxelts = AxElt[1:min(newdims, length(AxElt))]
    quote
        data = sub(A.data, idxs...)
        ndims(data) == $newdims || error("miscomputed dimensionality: computed ", $newdims, ", got ", ndims(data))
        axes = ntuple(min(length(A.axes), $newdims)) do i
            # This needs to preserve the type of the axes, so scalar indices
            # must become ranges. This is really hacky and will fail if
            # indexing the axis vector by a UnitRange returns a different type.
            # TODO: do this during staging, and do it better.
            ndims(idxs[i]) == 0 ? A.axes[i][idxs[i]:idxs[i]] : A.axes[i][idxs[i]]
        end::$(newaxes)
        AxisArray{$T,$newdims,typeof(data),$newnames,$newaxes,$newaxelts}(data, axes)
    end
end

### Fancier indexing capabilities provided only by AxisArrays ###

# First is the ability to index by named axis.
# When indexing by named axis the shapes of omitted dimensions are preserved
# TODO: should we handle multidimensional Axis indexes? It could be interpreted
#       as adding dimensions in the middle of an AxisArray.
# TODO: should we allow repeated axes? As a union of indices of the duplicates?
stagedfunction Base.getindex{T,N,D,names,Ax,AxElt}(A::AxisArray{T,N,D,names,Ax,AxElt}, I::Axis...)
    Inames = Symbol[axisname(i) for i in I]
    Anames = Symbol[names...]
    ind = indexin(Inames, Anames)
    for i = 1:length(ind)
        ind[i] == 0 && return :(error("axis name ", $(Inames[i]), " is not in ", $names))
    end

    idxs = Expr[:(Colon()) for d = 1:N]
    for i=1:length(ind)
        idxs[ind[i]] == :(Colon()) || return :(error("multiple indices provided on axis ", $(names[ind[i]])))
        idxs[ind[i]] = :(I[$i].I)
    end

    return :(A[$(idxs...)])
end

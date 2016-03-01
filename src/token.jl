using Compat
using AbstractTrees

typealias TokenValue @compat(Union{Symbol, Char, Number, Void})

import AbstractTrees: children, AbstractShadowTree, make_zip, first_tree, second_tree
import Base: convert

abstract AbstractToken

immutable Token <: AbstractToken
  val::TokenValue
end
val(t::Token) = t.val
val(t::Union{Expr,Symbol,ASCIIString,UTF8String,LineNumberNode}) = t


immutable SourceRange
    offset::UInt32
    length::UInt16
    file::UInt8
end
SourceRange() = SourceRange(-1 % UInt32,-1 % UInt16,-1 % UInt8)

immutable SourceLocToken <: AbstractToken
  val::TokenValue
  loc::SourceRange
end
SourceLocToken(val, offset, length, file) =
    SourceLocToken(val, SourceRange(offset, length, file))
val(t::SourceLocToken) = t.val

const ¬ = val
√(tok::SourceLocToken) = tok.loc
√(r::SourceRange) = r

# Expr and source tree Construction
immutable SourceNode
    loc::Any # SourceRange
    children::Vector
end
convert(::Type{SourceNode},loc::SourceRange) = SourceNode(loc,SourceNode[])
SourceNode(x::SourceNode) = x
children(node::SourceNode) = node.children
Base.show(io::IO, node::SourceNode) = print(io, node.loc)

immutable SourceExpr <: AbstractShadowTree
    expr::Any
    loc::SourceNode
end
make_zip(x::SourceExpr) = zip(children(x.expr),children(x.loc))
first_tree(x::SourceExpr) = x.expr
second_tree(x::SourceExpr) = x.loc
val(expr::SourceExpr) = expr.expr
√(expr::SourceExpr) = expr.loc

normalize(loc::SourceNode) = normalize(loc.loc)
normalize(x) = x
const NodeOrRange = Union{SourceNode,SourceRange}
function merge(loc1::NodeOrRange, loc2::NodeOrRange)
    loc1, loc2 = normalize(loc1), normalize(loc2)
    loc1 == SourceRange() && return loc2
    loc2 == SourceRange() && return loc1
    @assert loc1.file == loc2.file
    start = min(loc1.offset, loc2.offset)
    stop = max(loc1.offset + loc1.length, loc2.offset + loc2.length)
    res = SourceRange(start, stop-start, loc1.file)
    res
end

const ⤄ = merge
function ⤄(ex::SourceExpr, x::SourceRange)
    SourceExpr(ex.expr,SourceNode(ex.loc.loc ⤄ x, ex.loc.children))
end
⤄(ex::Union{ASCIIString, UTF8String, Char}, x::NodeOrRange) = SourceExpr(ex,SourceNode(x))
⤄(ex::SourceExpr, x::SourceLocToken) = ⤄(ex,√x)
⤄(ex::Union{Symbol,Expr,Bool}, x::Union{SourceLocToken,SourceRange}) = SourceExpr(ex,√x)
⤄(ex::Expr, x::Token) = ex
⤄(x,y::Void) = x

function sortedcomplement(of::SourceRange, set)
    complement = SourceRange[]
    lastend = of.offset
    laststart = lastend
    for x in set
        x = normalize(x)
        @assert x.offset >= laststart
        if x.offset >= lastend
            push!(complement,SourceRange(lastend,x.offset-lastend,0))
        end
        laststart = max(laststart, x.offset)
        lastend = max(lastend, x.offset + x.length)
    end
    if lastend < of.offset + of.length
        push!(complement,SourceRange(lastend,of.offset+of.length-lastend-1,0))
    end
    complement
end

⨳(sym::Symbol) = Expr(sym)
⨳(sym::Symbol, args::LineNumberNode...) = Expr(sym::Symbol, args...)
function ⨳(sym::Symbol, args::Union{SourceLocToken,LineNumberNode,SourceExpr}...)
    args = filter(x->!isa(x,LineNumberNode),args) # Don't need line number nodes
    loc = normalize(reduce(⤄,map(√,args)))
    SourceExpr(Expr(sym,map(¬,args)...),SourceNode(loc,
        [map(x->SourceNode(√x),args)...]))
end
⨳(sym::Symbol,args::Union{Token,ASCIIString,UTF8String,Symbol,LineNumberNode,Expr}...) = Expr(sym,map(¬,args)...)
⨳(sym::SourceLocToken,args...) = (SourceExpr(Expr(¬sym), SourceRange()) ⪥ args) ⤄ √sym
⨳(sym::Token,args...) = ⨳(¬sym,args...)

function expr_append!(ex::SourceExpr, args::Union{Array,Tuple})
    !isempty(args) || return ex
    append!(ex.expr.args,[¬x for x in args])
    append!(ex.loc.children,[SourceNode(√x) for x in args])
    ex = SourceExpr(ex.expr,
        SourceNode(normalize(reduce(⤄,ex.loc.children)),ex.loc.children))
    ex
end
function expr_append!(ex::SourceExpr, new::SourceExpr)
    expr_append!(ex, collect(map(x->SourceExpr(x[1],SourceNode(x[2])),zip(new.expr.args,children(new.loc)))))
end
expr_append!(ex::Expr, args::Array) = (append!(ex.args, args); ex)
expr_append!(ex::Expr, new::Expr) = expr_append!(ex, new.args)

const ⪥ = expr_append!
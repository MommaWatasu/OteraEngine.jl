struct JLCodeBlock
    code::String
end

struct SuperBlock
    count::Int
end

struct VariableBlock
    exp::String
end

struct TmpStatement
    st::String
end

struct TmpBlock
    name::String
    contents::Vector{Union{String, VariableBlock, TmpStatement}}
end

function Base.push!(a::TmpBlock, v::Union{String, TmpStatement})
    push!(a.contents, v)
end

function (TB::TmpBlock)(filters::Dict{String, Function}, autoescape::Bool)
    code = ""
    for content in TB.contents
        t = typeof(content)
        if t == TmpStatement
            code *= "$(content.st);"
        elseif t == VariableBlock
            if occursin("|>", content.exp)
                exp = map(strip, split(content.exp, "|>"))
                f = filters[exp[2]]
                if autoescape && f != htmlesc
                    code *= "txt *= htmlesc($(string(Symbol(f)))(string($(content.exp))));"
                else
                    code *= "txt *= $(string(Symbol(f)))(string($(content.exp)));"
                end
            else
                if autoescape
                    code *= "txt *= htmlesc(string($(content.exp)));"
                else
                    code *= "txt *= string($(content.exp));"
                end
            end
        elseif t == String
            code *= "txt *= \"$(replace(content, "\""=>"\\\""))\";"
        end
    end
    return code
end

struct TmpCodeBlock
    contents::Vector{Union{String, VariableBlock, TmpStatement, TmpBlock, SuperBlock}}
end

function (TCB::TmpCodeBlock)(filters::Dict{String, Function}, autoescape::Bool)
    code = ""
    for content in TCB.contents
        t = typeof(content)
        if t == TmpStatement
            code *= "$(content.st);"
        elseif t == TmpBlock
            code *= content(filters, autoescape)
        elseif t == VariableBlock
            if occursin("|>", content.exp)
                exp = map(strip, split(content.exp, "|>"))
                f = filters[exp[2]]
                if autoescape && f != htmlesc
                    code *= "txt *= htmlesc($(string(Symbol(f)))(string($(content.exp))));"
                else
                    code *= "txt *= $(string(Symbol(f)))(string($(content.exp)));"
                end
            else
                if autoescape
                    code *= "txt *= htmlesc(string($(content.exp)));"
                else
                    code *= "txt *= string($(content.exp));"
                end
            end
        elseif t == String
            code *= "txt *= \"$(replace(content, "\""=>"\\\""))\";"
        end
    end
    expr = Meta.parse(code)
    if expr.head == :toplevel
        return Expr(:block, expr.args...)
    else
        return expr
    end
end

CodeBlockVector = Vector{Union{String, JLCodeBlock, TmpCodeBlock, TmpBlock, VariableBlock, SuperBlock}}
SubCodeBlockVector = Vector{Union{String, JLCodeBlock, TmpStatement, TmpBlock, VariableBlock, SuperBlock}}

function get_string(tb::TmpBlock)
    txt = ""
    for content in tb.contents
        if typeof(content) == String
            txt *= content
        end
    end
    return txt
end

function process_super(child::TmpBlock, parent::TmpBlock)
    for i in 1 : length(child.contents)
        if typeof(child.contents[i]) == SuperBlock
            child.contents[i].count -= 1
            if child.contents[i].count == 0
                child.contents[i] = get_string(parent)
            end
        end
    end
    return child
end

function inherite_blocks(src::Vector{TmpBlock}, dst::Vector{TmpBlock})
    for i in 1 : length(src)
        idx = findfirst(x->x.name==src[i].name, dst)
        if idx === nothing
            push!(dst, src[i])
        else
            dst[idx] = process_super(src[i], dst[idx])
        end
    end
    return dst
end

function apply_inheritance(elements, blocks::Vector{TmpBlock})
    for i in eachindex(elements)
        if typeof(elements[i]) == TmpCodeBlock
            idxs = findall(x->typeof(x)==TmpBlock, elements[i].contents)
            length(idxs) == 0 && continue
            for j in idxs
                idx = findfirst(x->x.name==elements[i].contents[j].name, blocks)
                if idx === nothing
                    elements[i].contents[j] = ""
                else
                    elements[i].contents[j] = blocks[idx]
                end
            end
        elseif typeof(elements[i]) == TmpBlock
            idx = findfirst(x->x.name==elements[i], blocks)
            if idx === nothing
                elements[i] = ""
            else
                elements[i] = blocks[idx]
            end
        end
    end
    return elements
end
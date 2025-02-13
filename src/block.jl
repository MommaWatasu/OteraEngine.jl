mutable struct SuperBlock
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
    contents::Vector{Union{AbstractString, TmpStatement, TmpBlock, VariableBlock, SuperBlock}}
end
TmpBlockTypes = Vector{Union{AbstractString, TmpStatement, TmpBlock, VariableBlock, SuperBlock}}

function Base.push!(a::TmpBlock, v::Union{AbstractString, VariableBlock, TmpStatement, SuperBlock})
    push!(a.contents, v)
end

function (TB::TmpBlock)(autoescape::Bool)
    code = ""
    for content in TB.contents
        t = typeof(content)
        if isa(content, TmpStatement)
            code *= "$(content.st);"
        elseif isa(content, TmpBlock)
            code *= content(autoescape)
        elseif isa(content, VariableBlock)
            if occursin("|>", content.exp)
                exp = map(strip, split(content.exp, "|>"))
                f = filters_alias[exp[2]]
                if autoescape && f != htmlesc
                    code *= "txt *= htmlesc(string($(string(f))($(exp[1]))));"
                else
                    code *= "txt *= string($(string(f))($(content.exp[1])));"
                end
            else
                if autoescape
                    code *= "txt *= htmlesc(string($(content.exp)));"
                else
                    code *= "txt *= string($(content.exp));"
                end
            end
        elseif typeof(content) <: AbstractString
            code *= "txt *= \"$(replace(replace(content, "\""=>"\\\""), "\r"=>"\\r"))\";"
        end
    end
    return code
end

struct TmpCodeBlock
    contents::Vector{Union{AbstractString, VariableBlock, TmpStatement, TmpBlock}}
end
TmpCodeBlockTypes = Vector{Union{AbstractString, VariableBlock, TmpStatement, TmpBlock}}

function (TCB::TmpCodeBlock)(autoescape::Bool)
    code = ""
    for content in TCB.contents
        if isa(content, TmpStatement)
            code *= "$(content.st);"
        elseif isa(content, TmpBlock)
            code *= content(autoescape)
        elseif isa(content, VariableBlock)
            if occursin("|>", content.exp)
                exp = map(strip, split(content.exp, "|>"))
                f = filters_alias[exp[2]]
                if autoescape && f != htmlesc
                    code *= "txt *= htmlesc(string($(string(f))($(content.exp))));"
                else
                    code *= "txt *= string($(string(f))($(content.exp)));"
                end
            else
                if autoescape
                    code *= "txt *= htmlesc(string($(content.exp)));"
                else
                    code *= "txt *= string($(content.exp));"
                end
            end
        elseif typeof(content) <: AbstractString
            code *= "txt *= \"$(replace(replace(content, "\""=>"\\\""), "\r"=>"\\r"))\";"
        end
    end
    expr = Meta.parse(code)
    if expr === nothing
        return ""
    elseif expr.head == :toplevel
        return Expr(:block, expr.args...)
    else
        return expr
    end
end

CodeBlockVector = Vector{Union{AbstractString, TmpCodeBlock, TmpBlock, VariableBlock, SuperBlock}}
SubCodeBlockVector = Vector{Union{AbstractString, TmpStatement, TmpBlock, VariableBlock, SuperBlock}}

function get_string(tb::TmpBlock)
    txt = ""
    for content in tb.contents
        if typeof(content) <: AbstractString
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

function apply_inheritance(elements::CodeBlockVector, blocks::Vector{TmpBlock})
    for element in elements
        if isa(element, TmpCodeBlock)
            idxs = findall(x->typeof(x)==TmpBlock, element.contents)
            length(idxs) == 0 && continue
            for j in idxs
                idx = findfirst(x->x.name==element.contents[j].name, blocks)
                if idx === nothing
                    element.contents[j] = ""
                else
                    element.contents[j] = blocks[idx]
                end
            end
            if !isempty(findall(x -> isa(x, TmpBlock), element.contents))
                apply_inheritance(element.contents, blocks)
            end
        end
    end
    return elements
end

for elements_types in [TmpCodeBlockTypes, TmpBlockTypes]
    eval(:(function apply_inheritance(elements::$(elements_types), blocks::Vector{TmpBlock})
        for element in elements
            if isa(element, TmpBlock)
                idxs = findall(x->typeof(x)==TmpBlock, element.contents)
                length(idxs) == 0 && continue
                for j in idxs
                    idx = findfirst(x->x.name==element.contents[j].name, blocks)
                    if idx === nothing
                        element.contents[j] = ""
                    else
                        element.contents[j] = blocks[idx]
                    end
                end
                if !isempty(findall(x -> isa(x, TmpBlock), element.contents))
                    apply_inheritance(element.contents, blocks)
                end
            end
        end
        return elements
    end))
end
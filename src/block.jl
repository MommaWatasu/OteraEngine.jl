struct RawText
    txt::String
end

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
    contents::Vector{Union{String, RawText, TmpStatement}}
end

CodeBlockVector = Vector{Union{String, RawText, TmpStatement, TmpBlock, VariableBlock, SuperBlock}}

function (TB::TmpBlock)(init::Dict{String, T}, filters::Dict{String, Function}, autoescape::Bool) where {T}
    code = ""
    for content in TB.contents
        t = typeof(content)
        if t == TmpStatement
            code *= "$(content.st);"
        elseif t == VariableBlock
            if occursin("|>", content.exp)
                exp = map(strip, split(content.exp, "|>"))
                if exp[1] in keys(init)
                    f = filters[exp[2]]
                    if autoescape && f != htmlesc
                        code *= "txt *= htmlesc($(string(Symbol(f)))(string($(content.exp))));"
                    else
                        code *= "txt *= $(string(Symbol(f)))(string($(content.exp)));"
                    end
                end
            else
                if content.exp in keys(init)
                    if autoescape
                        code *= "txt *= htmlesc(string($(content.exp)));"
                    else
                        code *= "txt *= string($(content.exp));"
                    end
                end
            end
        elseif t == RawText
            code *= "txt *= \"$(replace(content.txt, "\""=>"\\\""))\";"
        else
            code *= "txt *= \"$(replace(content, "\""=>"\\\""))\";"
        end
    end
    return code
end

function get_string(tb::TmpBlock)
    txt = ""
    for content in tb.contents
        if typeof(content) == String
            txt *= content
        elseif typeof(content) == RawText
            txt *= content.txt
        end
    end
    return txt
end

function process_super(parent::TmpBlock, child::TmpBlock, expression_block::Tuple{String, String})
    for i in 1 : length(child.contents)
        if typeof(child.contents[i]) == String
            re = Regex("$(expression_block[1])\\s*?(?<body>(super.)*)super\\(\\)\\s*$(expression_block[2])")
            for m in eachmatch(re, child.contents[i])
                if m[:body] == ""
                    child.contents[i] = replace(child.contents[i], m.match=>get_string(parent))
                else
                    child.contents[i] = replace(child.contents[i], m.match=>"{{$(m[:body][7:end])super()}}")
                end
            end
        end
    end
    return child
end

function inherite_blocks(src::Vector{TmpBlock}, dst::Vector{TmpBlock}, expression_block::Tuple{String, String})
    for i in 1 : length(src)
        idx = findfirst(x->x.name==src[i].name, dst)
        idx === nothing && continue
        dst[idx] = process_super(dst[idx], src[i], expression_block)
    end
    return dst
end


function Base.push!(a::TmpBlock, v::Union{String, RawText, TmpStatement})
    push!(a.contents, v)
end

struct TmpCodeBlock
    #Union{TmpBlock, RawText, String, TmpStatement}
    contents::CodeBlockVector
end

function (TCB::TmpCodeBlock)(init::Dict{String, T}, filters::Dict{String, Function}, autoescape::Bool) where {T}
    code = ""
    for content in TCB.contents
        t = typeof(content)
        if t == TmpStatement
            code *= "$(content.st);"
        elseif t == TmpBlock
            code *= content(init, filters, autoescape)
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
        elseif t == RawText
            code *= "txt *= \"$(replace(content.txt, "\""=>"\\\""))\";"
        else
            code *= "txt *= \"$(replace(content, "\""=>"\\\""))\";"
        end
    end
    return code
end

function apply_variables(content, filters::Dict{String, Function}, config::ParserConfig)
    re = Regex("$(config.expression_block[1])\\s*(?<variable>[\\s\\S]*?)\\s*?$(config.expression_block[2])")
    for m in eachmatch(re, content)
        if occursin("|>", m[:variable])
            exp = split(m[:variable], "|>")
            f = filters[exp[2]]
            if config.autoescape && f != htmlesc
                content = content[1:m.offset-1] * "\$(htmlesc($f(string($(exp[1])))))" *  content[m.offset+length(m.match):end]
            else
                content = content[1:m.offset-1] * "\$($f(string($(exp[1]))))" *  content[m.offset+length(m.match):end]
            end
        else
            if config.autoescape
                content = content[1:m.offset-1] * "\$(htmlesc(string($(m[:variable]))))" *  content[m.offset+length(m.match):end]
            else
                content = content[1:m.offset-1] * "\$" * m[:variable] *  content[m.offset+length(m.match):end]
            end
        end
    end
    return content
end

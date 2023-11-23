struct RawText
    txt::String
end

struct TmpStatement
    st::String
end

struct TmpBlock
    name::String
    contents::Vector{Union{String, RawText, TmpStatement}}
end

CodeBlockVector = Vector{Union{String, RawText, TmpStatement, TmpBlock}}

function (TB::TmpBlock)(filters::Dict{String, Function}, config::ParserConfig)
    code = ""
    for content in TB.contents
        if typeof(content) == TmpStatement
            code *= "$(content.st);"
        elseif typeof(content) == RawText
            code *= ("txt *= \"$(replace(content.txt, "\""=>"\\\""))\";")
        else
            code *= ("txt *= \"$(replace(apply_variables(content, filters, config), "\""=>"\\\""))\";")
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
    contents::CodeBlockVector
end

function (TCB::TmpCodeBlock)(blocks::Vector{TmpBlock}, filters::Dict{String, Function}, config::ParserConfig)
    code = "txt=\"\";"
    for content in TCB.contents
        if typeof(content) == TmpStatement
            code *= "$(content.st);"
        elseif typeof(content) == TmpBlock
            idx = findfirst(x->x.name==content.name, blocks)
            idx === nothing && throw(TemplateError("invalid block: failed to appy block named `$(content.name)`"))
            code *= blocks[idx](filters, config)
        elseif typeof(content) == RawText
            code *= ("txt *= \"$(replace(content.txt, "\""=>"\\\""))\";")
        else
            code *= ("txt *= \"$(replace(apply_variables(content, filters, config), "\""=>"\\\""))\";")
        end
    end
    if length(TCB.contents) != 1 || typeof(TCB.contents[1]) == TmpBlock
        code *= "push!(txts, txt);"
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

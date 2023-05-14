struct ParserConfig
    jl_code_block::String
    tmp_code_block::Tuple{String, String}
    variable_block::Tuple{String, String}
    function ParserConfig(config::Dict{String, String})
        return new(
            config["jl_block"],
            (config["tmp_block_start"], config["tmp_block_stop"]),
            (config["variable_block_start"], config["variable_block_stop"])
        )
    end
end

struct ParserError <: Exception
    msg::String
end

Base.showerror(io::IO, e::ParserError) = print(io, "ParserError: "*e.msg)

struct TmpStatement
    st::String
end

struct TmpCodeBlock
    contents::Array{Union{String, TmpStatement}, 1}
end

function (TCB::TmpCodeBlock)()
    code = "txt=\"\";"
    for content in TCB.contents
        if typeof(content) == TmpStatement
            code *= (content.st*";")
        else
            code *= ("txt *= \"$(apply_variables(content))\";")
        end
    end
    if length(TCB.contents) != 1
        code *= "push!(txts, txt);"
    end
    return code
end

#new parser
function parse_template(txt::String, config::ParserConfig)
    jl_block_len = length(config.jl_code_block)
    tmp_block_len = length.(config.tmp_code_block)
    
    jl_pos, tmp_pos = zeros(Int, 2)
    depth = 0
    block_counts = ones(Int, 2)
    idx = 1
    
    jl_codes = Array{String}(undef, 0)
    top_codes = Array{String}(undef, 0)
    tmp_codes = Array{TmpCodeBlock}(undef, 0)
    block = Array{Union{String, TmpStatement}}(undef, 0)
    out_txt = ""
    for i in 1 : length(txt)
        #jl code block
        if txt[i:min(end, i+jl_block_len-1)] == config.jl_code_block
            if tmp_pos != 0
                throw(ParserError("invaild jl code block! code block can't be in another code block."))
            elseif jl_pos == 0
                jl_pos = i
                out_txt *= txt[idx:i-1]
            elseif jl_pos != 0
                code = txt[jl_pos+jl_block_len+1:i-1]
                top_regex = r"(using|import)\s.*[\n, ;]"
                for t in eachmatch(top_regex, code)
                    push!(top_codes, t.match)
                    code = replace(code, t.match=>"")
                end
                push!(jl_codes, code)
                out_txt *= txt[idx:jl_pos-1]
                out_txt*="<jlcode$(block_counts[1])>"
                block_counts[1] += 1
                idx = i + jl_block_len
                jl_pos = 0
            end
        #tmp code block start
        elseif txt[i:min(end, i+tmp_block_len[1]-1)] == config.tmp_code_block[1]
            if jl_pos != 0
                throw(ParserError("invaild code block! code block can't be in another code block."))
            end
            if depth == 0
                out_txt *= txt[idx:i-1]
            else
                push!(block, txt[idx:i-1])
            end
            tmp_pos = i
        #tmp code block stop
        elseif txt[i:min(end, i+tmp_block_len[2]-1)] == config.tmp_code_block[2]
            code = strip(txt[tmp_pos+tmp_block_len[1]+1:i-1])
            #process tmp code
            operator = split(code)[1]
            if operator == "set"
                if length(block) == 0
                    push!(tmp_codes, TmpCodeBlock([TmpStatement(code[4:end])]))
                else
                    push!(block, TmpStatement(code[4:end]))
                end
            elseif operator == "end"
                if depth == 0
                    throw(ParserError("`end` block was found despite the depth of the code is 0."))
                end
                depth -= 1
                push!(block, TmpStatement("end"))
                if depth == 0
                    push!(tmp_codes, TmpCodeBlock(block))
                    block = Array{Union{String, TmpStatement}}(undef, 0)
                    out_txt *= "<tmpcode$(block_counts[2])>"
                    block_counts[2] += 1
                    tmp_pos = 0
                end
            else
                depth += 1
                if operator == "with"
                    push!(block, TmpStatement("let "*code[5:end]))
                else
                    push!(block, TmpStatement(code))
                end
            end
            idx = i + tmp_block_len[2]
        end
    end
    out_txt *= txt[idx:end]
    return out_txt, jl_codes, top_codes, tmp_codes
end

# text parser
function parse_text(txt::String, config::ParserConfig)
    txt, jl_codes, top_codes = parse_jl_code(txt, config.jl_code_block)
    txt, tmp_codes = parse_tmp_code(txt, config.tmp_code_block)
    return txt, top_codes, jl_codes, tmp_codes
end

function parse_jl_code(txt::String, jl_code_block::Tuple{String, String})
    sl, el = length(jl_code_block[1]), length(jl_code_block[2])
    regex = Regex(jl_code_block[1]*"[\\s\\S]*?"*jl_code_block[2])
    result = eachmatch(regex, txt)
    jl_codes = Array{String}(undef, length(collect(result)))
    top_codes = Array{String}(undef, 0)
    for (i, m) in enumerate(result)
        code = m.match[sl+1:length(m.match)-el]
        top_regex = r"(using|import)\s.*[\n, ;]"
        for t in eachmatch(top_regex, code)
            push!(top_codes, t.match)
            code = replace(code, t.match=>"")
        end
        jl_codes[i] = code
        txt = replace(txt, m.match => "<jlcode$i>")
    end
    return txt, jl_codes, top_codes
end

function apply_variables(content)
    for m in eachmatch(r"{{\s*(?<variable>[\s\S]*?)\s*?}}", content)
        content = replace(content, m.match=>"\$"*m[:variable])
    end
    return content
end

function parse_tmp_code(txt::String, tmp_code_block::Tuple{String, String})
    sl, el = length(tmp_code_block[1]), length(tmp_code_block[2])
    regex = Regex(tmp_code_block[1]*"\\s*(?<tmp_code>[\\s\\S]*?)\\s*?"*tmp_code_block[2]*"\\s*")
    result = eachmatch(regex, txt)
    tmp_codes = Array{TmpCodeBlock}(undef, 0)
    block = Array{Union{String, TmpStatement}}(undef, 0)
    depth = 0
    idx = 1
    block_count = 1
    func_count = 1
    out_txt = ""
    for m in result
        if depth != 0
            push!(block, string(lstrip(txt[idx:m.offset-1])))
        else
            out_txt *= txt[idx:m.offset-1]
        end
        code_len = length(m.match)
        tmp_code = m[:tmp_code]
        operator = split(tmp_code)[1]
        if operator == "set"
            if length(block) == 0
                push!(tmp_codes, TmpCodeBlock([TmpStatement(replace(tmp_code, " "=>"")[4:end])]))
            else
                push!(block, TmpStatement(replace(tmp_code, " "=>"")[4:end]))
            end
        elseif operator == "end"
            if depth == 0
                throw(ParserError("`end` block was found despite the depth of the code is 0."))
            end
            depth -= 1
            push!(block, TmpStatement("end"))
            if depth == 0
                push!(tmp_codes, TmpCodeBlock(block))
                block = Array{Union{String, TmpStatement}}(undef, 0)
                out_txt *= "<tmpcode$block_count>"
                block_count += 1
            end
        else
            if depth == 0
                block_start = m.offset
            end
            depth += 1
            if operator == "with"
                with_st = replace(tmp_code, " "=>"")[5:end]
                push!(block, TmpStatement("let "*with_st))
                func_count += 1
            else
                push!(block, TmpStatement(tmp_code))
            end
        end
        idx = m.offset+code_len
    end
    depth != 0 && throw(ParserError("invaild template! control statement must be closed with `end`"))
    out_txt *= txt[idx:end]
    return out_txt, tmp_codes
end

# configuration(TOML format) parser
function parse_config(filename::String)
    if filename[end-3:end] != "toml"
        throw(ArgumentError("Suffix of config file must be `toml`! Now, it is `$(filename[end-3:end])`."))
    end
    config = ""
    open(filename, "r") do f
        config = read(f, String)
    end
    return TOML.parse(config)
end
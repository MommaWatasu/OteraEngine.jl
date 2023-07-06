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

function apply_variables(content)
    for m in eachmatch(r"{{\s*(?<variable>[\s\S]*?)\s*?}}", content)
        content = replace(content, m.match=>"\$"*m[:variable])
    end
    return content
end

## template parser
function parse_template(txt::String, config::ParserConfig)
    jl_block_len = length(config.jl_code_block)
    tmp_block_len = length.(config.tmp_code_block)
    
    jl_pos, tmp_pos = zeros(Int, 2)
    depth = 0
    block_counts = ones(Int, 2)
    idx = 1
    eob = false
    
    jl_codes = Array{String}(undef, 0)
    top_codes = Array{String}(undef, 0)
    tmp_codes = Array{TmpCodeBlock}(undef, 0)
    block = Array{Union{String, TmpStatement}}(undef, 0)
    out_txt = ""
    for i in 1 : length(txt)
        if eob
            if txt[i+tmp_block_len[2]] in ['\t', '\n', ' ']
                idx += 1
            else
                idx += 1
                eob = false
            end
        end
        #jl code block
        if txt[i:min(end, i+jl_block_len-1)] == config.jl_code_block
            if tmp_pos != 0
                throw(ParserError("invaild jl code block! code block can't be in another code block."))
            elseif jl_pos == 0
                jl_pos = i
                out_txt *= txt[idx:i-1]
            elseif jl_pos != 0
                code = txt[jl_pos+jl_block_len:i-1]
                top_regex = r"(using|import)\s.*[\n, ;]"
                result = eachmatch(top_regex, code)
                tops = ""
                for t in result
                    tops *= t.match
                    code = replace(code, t.match=>"")
                end
                push!(top_codes, tops)
                push!(jl_codes, code)
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
                out_txt *= string(lstrip(txt[idx:i-1]))
            else
                push!(block, string(lstrip(txt[idx:i-1])))
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
                    eob = true
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
    return out_txt, top_codes, jl_codes, tmp_codes
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
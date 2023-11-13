struct ParserConfig
    control_block::Tuple{String, String}
    expression_block::Tuple{String, String}
    comment_block::Tuple{String, String}
    space_control::Bool
    lstrip_blocks::Bool
    trim_blocks::Bool
    dir::String
    function ParserConfig(config::Dict{String, Union{String, Bool}})
        if config["space_control"] && (config["lstrip_blocks"] || config["trim_blocks"])
            throw(ParserError("ParserConfig is broken: lstrip_blocks and trim_blocks should be disabled when space_control"))
        end
        return new(
            (config["control_block_start"], config["control_block_end"]),
            (config["expression_block_start"], config["expression_block_end"]),
            (config["comment_block_start"], config["comment_block_end"]),
            config["space_control"],
            config["lstrip_blocks"],
            config["trim_blocks"],
            config["dir"]
        )
    end
end

config2dict(config::ParserConfig) = Dict{String, Union{String, Bool}}(
    "control_block_start" => config.control_block[1],
    "control_block_end" => config.control_block[2],
    "expression_block_start" => config.expression_block[1],
    "expression_block_end" => config.expression_block[2],
    "comment_block_start" => config.comment_block[1],
    "comment_block_end" => config.comment_block[2],
    "space_control" => config.space_control,
    "lstrip_blocks" => config.lstrip_blocks,
    "trim_blocks" => config.trim_blocks,
    "dir" => config.dir
)

struct ParserError <: Exception
    msg::String
end

Base.showerror(io::IO, e::ParserError) = print(io, "ParserError: "*e.msg)

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

function Base.push!(a::TmpBlock, v::Union{String, RawText, TmpStatement})
    push!(a.contents, v)
end

struct TmpCodeBlock
    contents::Vector{Union{String, RawText, TmpStatement, TmpBlock}}
end

function (TCB::TmpCodeBlock)()
    code = "txt=\"\";"
    for content in TCB.contents
        if typeof(content) == TmpStatement
            code *= (content.st*";")
        elseif typeof(content) == RawText
            code *= ("txt *= $(content.txt)")
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

function regex_escape(txt)
    replace(txt, r"(?<escape>\(|\)|\[|\]|\{|\}|\.|\?|\+|\*|\||\\)" => s"\\\g<escape>")
end

function parse_meta(txt::String, config::ParserConfig)
    # dict to check tokens
    block_tokens = Dict(
        config.control_block[1] => config.control_block[2],
        config.comment_block[1] => config.comment_block[2]
    )
    # length of the code blocks start/end token
    control_block_len = length(config.control_block)
    # variables for lstrip and trim
    lstrip_block = nothing
    trim_block = nothing
    # processed text
    out_txt = ""
    # parent template
    super = nothing
    # idx to use add strings into out_txt
    idx = 1
    # variables for macro
    macros = Dict{String, String}()
    macro_def = ""

    re = Regex("(?<left_nl>\\n*)(?<left_space>\\s*?)(?<left_token>($(regex_escape(config.control_block[1]))|$(regex_escape(config.comment_block[1]))))(?<code>.*?)(?<right_token>($(regex_escape(config.control_block[2]))|$(regex_escape(config.comment_block[2]))))(?<right_nl>\\n?)")
    for m in eachmatch(re, txt)
        if block_tokens[m[:left_token]] != m[:right_token]
            throw(ParserError("token mismatch: beginning and end of the block doesn't match"))
        end
        if m[:left_token] == config.control_block[1]
            code = m[:code]
            # check space control configuration
            if !config.space_control
                if code[1] == "-"
                    lstrip_block = true
                    code = code[2:end]
                elseif code[1] == "+"
                    lstrip_block = false
                    code = code[2:end]
                else
                    lstrip_block = config.lstrip_blocks
                end
                if code[end] == "-"
                    trim_block = true
                    code = code[1:end-1]
                elseif code[end] == "+"
                    trim_block = false
                    code = code[1:end-1]
                else
                    trim_block = config.trim_blocks
                end
            end

            code = strip(code)
            tokens = split(code)
            operator = tokens[1]
            
            if !(operator in ["extends", "include", "import", "macro", "endmacro"])
                continue
            end

            # space control
            new_txt = ""
            if config.space_control
                new_txt = txt[idx:m.offset-1]
                idx = m.offset + length(m.match) - length(m[:right_nl])
            end
            if lstrip_block == true
                new_txt = txt[idx:m.offset-1]*m[:left_nl]
            elseif lstrip_block == false
                new_txt = txt[idx:m.offset-1]*m[:left_nl]*m[:left_space]
            end
            if trim_block == true
                idx = m.offset + length(m.match)
            elseif trim_block == false
                idx = m.offset + length(m.match) - length(m[:right_nl])
            end

            # check if the template has a parent
            if operator == "extends"
                # add text before the block
                out_txt *= new_txt
                
                if m.offset != 1
                    throw(ParserError("invalid extends block: `extends` block have to be top of the template"))
                end
                file_name = strip(code[8:end])
                if file_name[1] == file_name[end] == '\"'
                    super = Template(config.dir*"/"*file_name[2:end-1], config = config2dict(config))
                else
                    throw(ParserError("failed to read $file_name: file name have to be enclosed in double quotation marks"))
                end
            # include external template
            elseif operator == "include"
                # add text before the block
                out_txt *= new_txt
                file_name = strip(code[8:end])
                if file_name[1] == file_name[end] == '\"'
                    open(config.dir*"/"*file_name[2:end-1], "r") do f
                        parse_template(read(f, String), config)#add new elements into the current variables
                    end
                else
                    throw(ParserError("failed to include $file_name: file name have to be enclosed in double quotation marks"))
                end
            elseif operator == "from"
                import_st = match(r"from\s*(?<file_name>.*?)\s*import(?<body>.*)", code)
                if isnothing(import_st)
                    throw(ParserError("incorrect `import` block: your import block is broken. please look at the docs for detail."))
                end
                file_name = import_st[:file_name]
                external_macros = Dict()
                open(config.dir*"/"*file_name[2:end-1], "r") do f
                    external_macros = parse_meta(read(f, String), config)[3]
                    for em in external_macros
                        macros[alias*"."*p[1]] = em[2]
                    end
                end
                for macro_name in split(import_st[:body], ",")
                    def_element = split(macro_name)
                    if length(def_element) == 1
                        if haskey(external_macros, def_element[1])
                            macros[def_element[1]] = external_macros[def_element[1]]
                        else
                            @warn "failed to impoer external macro named $(def_element[1])"
                        end
                    elseif length(def_element) == 3
                        if haskey(external_macros, def_element[1])
                            macros[def_element[3]] = external_macros[def_element[1]]
                        else
                            @warn "failed to impoer external macro named $(def_element[1])"
                        end
                    else
                        throw(ParserError("incorrect `import` block: your import block is broken. please look at the docs for detail."))
                    end
                end
            elseif operator == "import"
                out_txt *= new_txt
                file_name = tokens[2]
                if tokens[3] != "as"
                    throw(ParserError("incorrect `import` block: your import block is broken. please look at the docs for detail."))
                end
                alias = tokens[4]
                if file_name[1] == file_name[end] == '\"'
                    open(config.dir*"/"*file_name[2:end-1], "r") do f
                        external_macros = parse_meta(read(f, String), config)[3]
                        for em in external_macros
                            macros[alias*"."*p[1]] = em[2]
                        end
                    end
                else
                    throw(ParserError("failed to import macro from $file_name: file name have to be enclosed in double quotation marks"))
                end
            elseif operator == "macro"
                # add text before the block
                out_txt *= new_txt
                macro_def = string(lstrip(code[6:end]))
            elseif operator == "endmacro"
                macros[get_macro_name(macro_def)] = build_macro(macro_def, new_txt)
            end

        # remove comment block
        else
            out_txt *= txt[idx:m.offset-1]
            idx = m.offset + length(m.match) - length(m[:right_nl])
        end
    end
    out_txt *= txt[idx:end]
    out_txt = apply_macros(out_txt, macros, config)
    return super, out_txt, macros
end

get_macro_name(macro_def) = match(r"(?<name>.*?)\(.*?\)", macro_def)[:name]

function build_macro(macro_def::String, txt::String)
    arg_names = [match(r"\S[^=]*", arg).match for arg in split(match(r"\((?<args>.*?)\)", macro_def)[:args], ",")]
    out_txt = ""
    idx = 1
    for m in eachmatch(r"\{\{\s*(?<variable>.*?)\s*\}\}", txt)
        if m[:variable] in arg_names
            out_txt *= (txt[idx:m.offset-1] * "\$" * m[:variable])
            idx = m.offset + length(m.match)
        end
    end
    out_txt *= txt[idx:end]
    return "_" * get_macro_name(macro_def) * "_" * match(r"\(.*\)", macro_def).match * "=\"\"\"" * out_txt * "\"\"\""
end

function apply_macros(txt::String, macros::Dict{String, String}, config::ParserConfig)
    for func_def in values(macros)
        eval(Meta.parse(func_def))
    end
    re = Regex("$(config.expression_block[1])\\s*(?<name>.*?)(?<body>\\(.*?\\))\\s*$(config.expression_block[2])")
    m = match(re, txt)
    while !isnothing(m)
        if haskey(macros, m[:name])
            println("@invokelatest _"*split(m[:name], ".")[end]*"_"*m[:body])
            try
                txt = txt[1:m.offset-1]*eval(Meta.parse("@invokelatest _"*split(m[:name], ".")[end]*"_"*m[:body]))*txt[m.offset+length(m.match):end]
            catch
                throw(ParserError("invalid macro: failed to call macro in $(m.match)"))
            end
        end
        m = match(re, txt)
    end
    return txt
end

## template parser
function parse_template(txt::String, config::ParserConfig)
    # process meta information
    super, txt, _ = parse_meta(txt, config)

    # dict to check tokens
    block_tokens = Dict(
        config.control_block[1] => config.control_block[2],
        config.expression_block[1] => config.expression_block[2],
        config.comment_block[1] => config.comment_block[2]
    )
    # length of the code blocks start/end token
    control_block_len = length(config.control_block)
    expression_block_len = length.(config.expression_block)
    comment_block_len = length.(config.comment_block)
    # variables for lstrip and trim
    lstrip_block = nothing
    trim_block = nothing
    # variables for blocks
    blocks = Vector{TmpBlock}()
    in_block = false
    # variable to check whether inside of raw block or not
    raw = false
    # variable to represent whether macro is valid or not
    macro_def = true
    # code block depth
    depth = 0
    # the number of blocks
    block_count = 1
    # index of the template
    idx = 1

    # prepare the arrays to store the code blocks
    jl_codes = Array{String}(undef, 0)
    top_codes = Array{String}(undef, 0)
    tmp_codes = Array{TmpCodeBlock}(undef, 0)
    code_block = Array{Union{String, RawText, TmpStatement, TmpBlock}}(undef, 0)
    out_txt = ""
    
    re = Regex("(?<left_nl>\\n*)\\s*?(?<left_token>($(regex_escape(config.control_block[1]))|$(regex_escape(config.expression_block[1]))|$(regex_escape(config.comment_block[1]))))(?<code>.*?)(?<right_token>($(regex_escape(config.control_block[2]))|$(regex_escape(config.expression_block[2]))|$(regex_escape(config.comment_block[2]))))(?<right_nl>\\n?)")
    for m in eachmatch(re, txt)
        if block_tokens[m[:left_token]] != m[:right_token]
            throw(ParserError("token mismatch: beginning and end of the block doesn't match"))
        end

        # control block
        if m[:left_token] == config.control_block[1]
            code = m[:code]
            # check space control configuration
            if !config.space_control
                if code[1] == "-"
                    lstrip_block = true
                    code = code[2:end]
                elseif code[1] == "+"
                    lstrip_block = false
                    code = code[2:end]
                else
                    lstrip_block = config.lstrip_blocks
                end
                if code[end] == "-"
                    trim_block = true
                    code = code[1:end-1]
                elseif code[end] == "+"
                    trim_block = false
                    code = code[1:end-1]
                else
                    trim_block = config.trim_blocks
                end
            end

            code = strip(code)
            tokens = split(code)
            operator = tokens[1]

            # process raw code block
            if raw
                if operator == "endraw"
                    raw = false
                    # space control
                    new_txt = ""
                    if config.space_control
                        new_txt = txt[idx:m.offset-1]
                        idx = m.offset + length(m.match) - length(m[:right_nl])
                    end
                    if lstrip_block == true
                        new_txt = txt[idx:m.offset-1]*m[:left_nl]
                    elseif lstrip_block == false
                        new_txt = txt[idx:m.offset-1]*m[:left_nl]*m[:left_space]
                    end
                    if trim_block == true
                        idx = m.offset + length(m.match)
                    elseif trim_block == false
                        idx = m.offset + length(m.match) - length(m[:right_nl])
                    end
                    # check depth
                    if in_block
                        push!(code_block[end], RawText(new_txt))
                    else
                        if depth == 0
                            out_txt *= new_txt
                        else
                            push!(code_block, RawText(new_txt))
                        end
                    end
                    continue
                else
                    continue
                end
            end

            # space control
            new_txt = ""
            if config.space_control
                new_txt = txt[idx:m.offset-1]
                idx = m.offset + length(m.match) - length(m[:right_nl])
            end
            if lstrip_block == true
                new_txt = txt[idx:m.offset-1]*m[:left_nl]
            elseif lstrip_block == false
                new_txt = txt[idx:m.offset-1]*m[:left_nl]*m[:left_space]
            end
            if trim_block == true
                idx = m.offset + length(m.match)
            elseif trim_block == false
                idx = m.offset + length(m.match) - length(m[:right_nl])
            end
            # check depth
            if in_block
                push!(code_block[end], new_txt)
            else
                if depth == 0
                    out_txt *= new_txt
                else
                    push!(code_block, new_txt)
                end
            end

            if operator == "endblock"
                if !in_block
                    throw(ParserError("invalid end of block: `endblock`` statement without `block` statement"))
                end
                in_block = false
                push!(blocks, code_block[end])
                if depth == 0
                    push!(tmp_codes, TmpCodeBlock(code_block))
                    code_block = Array{Union{String, RawText, TmpStatement}}(undef, 0)
                    out_txt *= "<tmpcode$block_count>"
                    block_count += 1
                end
                continue
                
            elseif operator == "block"
                if in_block
                    throw(ParserError("nested block: nested block is invalid"))
                end
                in_block = true
                push!(code_block, TmpBlock(tokens[2], Vector()))
                continue
                
            # set raw flag
            elseif operator == "raw"
                raw = true
                continue
                
            # assignment for julia
            elseif operator == "set"
                if in_block
                    push!(code_block[end], TmpStatement("global "*code))
                else
                    if depth == 0
                        push!(tmp_codes, TmpCodeBlock([TmpStatement(code[4:end])]))
                    else
                        push!(code_block, TmpStatement("global "*code))
                    end
                end

            # end for julia statement
            elseif operator == "end"
                if depth == 0
                    throw(ParserError("end is found at block depth 0"))
                end
                if in_block
                    push!(block[end], TmpStatement("end"))
                else
                    depth -= 1
                    push!(block, TmpStatement("end"))
                    if depth == 0
                        push!(tmp_codes, TmpCodeBlock(code_block))
                        code_block = Array{Union{String, RawText, TmpStatement}}(undef, 0)
                        out_txt *= "<tmpcode$block_count>"
                        block_count += 1
                    end
                end

            # julia statement
            else
                if !(operator in ["for", "while", "if", "let"])
                    throw(ParserError("This block is invalid: {$(m[:left_token])$(m[:code])$(m[:right_token])}"))
                end
                if in_block
                    push!(code_block[end], TmpStatement(code))
                else
                    depth += 1
                    push!(code_block, TmpStatement(code))
                end
            end
        
        # expression block
        elseif m[:left_token] == config.expression_block[1]
            macro_def = false
            if depth == 0
            else
            end
        else
            throw(ParserError("This block is invalid: {$(m[:left_token]*" "*m[:code]*" "*m[right_token])}"))
        end
    end
    out_txt *= txt[idx:end]
    return super, out_txt, tmp_codes, blocks
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
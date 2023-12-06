struct ParserError <: Exception
    msg::String
end

Base.showerror(io::IO, e::ParserError) = print(io, "ParserError: "*e.msg)

function regex_escape(txt)
    replace(txt, r"(?<escape>\(|\)|\[|\]|\{|\}|\.|\?|\+|\*|\||\\)" => s"\\\g<escape>")
end

function parse_meta(txt::String, filters::Dict{String, Symbol}, config::ParserConfig)
    # dict to check tokens
    block_tokens = Dict(
        config.control_block[1] => config.control_block[2],
        config.comment_block[1] => config.comment_block[2]
    )
    # variables for lstrip and trim
    lstrip_block = ' '
    trim_block = ' '
    prev_trim = false
    # processed text
    out_txt = ""
    # parent template
    super = nothing
    # idx to use add strings into out_txt
    idx = 1
    # variables for macro
    macros = Dict{String, String}()
    macro_def = ""

    re = Regex("(?<left_space1>\\s*?)(?<left_nl>\n?)(?<left_space2>\\s*?)(?<left_token>($(regex_escape(config.control_block[1]))|$(regex_escape(config.comment_block[1]))))(?<code>.*?)(?<right_token>($(regex_escape(config.control_block[2]))|$(regex_escape(config.comment_block[2]))))(?<right_nl>\\n?)(?<right_space>\\s*?)")
    for m in eachmatch(re, txt)
        if block_tokens[m[:left_token]] != m[:right_token]
            throw(ParserError("token mismatch: beginning and end of the block doesn't match"))
        end
        if m[:left_token] == config.control_block[1]
            # get space control config and process code
            code, lstrip_block, trim_block = get_block_config(string(m[:code]))
            code = strip(code)
            tokens = split(code)
            operator = tokens[1]
            
            if !(operator in ["extends", "include", "from", "import", "macro", "endmacro"])
                continue
            end

            if config.autospace
                if operator == "macro"
                    lstrip_block = ' '
                    trim_block = '-'
                elseif operator == "endmacro"
                    lstrip_block = '-'
                    trim_block = ' '
                end
            end

            # space control
            new_txt, idx, prev_trim = process_space(txt, m, idx, lstrip_block, trim_block, prev_trim, config)

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
                        out_txt *= read(f, String)
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
                    external_macros = parse_meta(read(f, String), filters, config)[3]
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
                            @warn "failed to import external macro named $(def_element[1])"
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
                        external_macros = parse_meta(read(f, String), filters, config)[3]
                        for em in external_macros
                            macros[alias*"."*em[1]] = em[2]
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
                macros[get_macro_name(macro_def)] = build_macro(macro_def, new_txt, filters, config)
            end

        # remove comment block
        else
            out_txt *= txt[idx:m.offset-1]
            idx = m.offset + length(m.match) - length(m[:right_nl])
        end
    end
    out_txt *= txt[idx:end]
    out_txt = string(strip(apply_macros(out_txt, macros, config)))
    return super, out_txt, macros
end

function get_block_config(code::String)
    lstrip_block = ' '
    trim_block = ' '
    if code[1] == '-'
        lstrip_block = '-'
        code = code[2:end]
    elseif code[1] == '+'
        lstrip_block = '+'
        code = code[2:end]
    end
    if code[end] == '-'
        trim_block = '-'
        code = code[1:end-1]
    elseif code[end] == '+'
        trim_block = '+'
        code = code[1:end-1]
    end
    return code, lstrip_block, trim_block
end

function process_space(txt::String, m::RegexMatch, idx::Int, lstrip_block::Char, trim_block::Char, prev_trim::Bool, config::ParserConfig)
    new_txt = ""
    if lstrip_block == '+'
        new_txt = txt[idx:m.offset-1]*m[:left_space1]*m[:left_nl]*m[:left_space2]
    elseif lstrip_block == '-'
        new_txt = txt[idx:m.offset-1]
        new_txt = string(rstrip(new_txt))
    elseif config.lstrip_blocks
        new_txt = txt[idx:m.offset-1]*m[:left_space1]*m[:left_nl]
    else
        new_txt = txt[idx:m.offset-1]*m[:left_space1]*m[:left_nl]*m[:left_space2]
    end
    if prev_trim
        new_txt = string(lstrip(new_txt))
    end
    if trim_block == '+'
        idx = m.offset + length(m.match) - length(m[:right_space]) - length(m[:right_nl])
    elseif trim_block == '-'
        idx = m.offset + length(m.match)
    elseif config.trim_blocks
        idx = m.offset + length(m.match) - length(m[:right_space])
    else
        idx = m.offset + length(m.match) - length(m[:right_space]) - length(m[:right_nl])
    end
    return new_txt, idx, (trim_block=='-') ? true : false
end

## template parser
function parse_template(txt::String, filters::Dict{String, Symbol}, config::ParserConfig)
    # process meta information
    super, txt, _ = parse_meta(txt, filters, config)

    # dict to check tokens
    block_tokens = Dict(
        config.control_block[1] => config.control_block[2],
        config.jl_block[1] => config.jl_block[2],
        config.expression_block[1] => config.expression_block[2]
    )
    # variables for lstrip and trim
    lstrip_block = ' ' 
    trim_block = ' '
    prev_trim = false
    # variables for blocks
    blocks = Vector{TmpBlock}()
    in_block = false
    # variable to check whether inside of raw block or not
    raw = false
    # code block depth
    depth = 0
    in_block_depth = 0
    # the number of blocks
    block_count = 1
    jl_block_count = 1
    # index of the template
    idx = 1

    # prepare the arrays to store the code blocks
    elements = CodeBlockVector(undef, 0)
    code_block = SubCodeBlockVector(undef, 0)

    re = Regex("(?<left_space1>\\s*?)(?<left_nl>\n?)(?<left_space2>\\s*?)(?<left_token>($(regex_escape(config.control_block[1]))|$(regex_escape(config.jl_block[1]))|$(regex_escape(config.expression_block[1]))))(?<code>[\\s\\S]*?)(?<right_token>($(regex_escape(config.control_block[2]))|$(regex_escape(config.jl_block[2]))|$(regex_escape(config.expression_block[2]))))(?<right_nl>\\n?)(?<right_space>\\s*?)")
    for m in eachmatch(re, txt)
        if block_tokens[m[:left_token]] != m[:right_token]
            throw(ParserError("token mismatch: beginning and end of the block doesn't match"))
        end

        # get space control config and process code
        code, lstrip_block, trim_block = get_block_config(string(m[:code]))
        code = strip(code)

        # control block
        if m[:left_token] == config.control_block[1]
            tokens = split(code)
            operator = tokens[1]

            # process raw code block
            if raw
                if operator == "endraw"
                    raw = false
                    # space control
                    new_txt, idx, prev_trim = process_space(txt, m, idx, lstrip_block, trim_block, prev_trim, config)
                    # check depth
                    if in_block
                        push!(code_block[end], new_txt)
                    else
                        if depth == 0
                            push!(elements, new_txt)
                        else
                            push!(code_block, new_txt)
                        end
                    end
                    continue
                else
                    continue
                end
            end

            # space control
            new_txt, idx, prev_trim = process_space(txt, m, idx, lstrip_block, trim_block, prev_trim, config)
            # check depth
            if in_block
                push!(code_block[end], new_txt)
            else
                if depth == 0
                    push!(elements, new_txt)
                else
                    push!(code_block, new_txt)
                end
            end

            if operator == "endblock"
                if !in_block
                    throw(ParserError("invalid end of block: `endblock`` statement without `block` statement"))
                end
                if in_block_depth != 0
                    throw(ParserError("invalid end of block: this block has the statement which is not closed"))
                end
                in_block = false
                push!(blocks, code_block[end])
                if depth == 0
                    push!(elements, TmpCodeBlock(code_block))
                    code_block = SubCodeBlockVector(undef, 0)
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
                    push!(code_block[end], TmpStatement(code))
                else
                    if depth == 0
                        push!(elements, TmpCodeBlock([TmpStatement(code[4:end])]))
                    else
                        push!(code_block, TmpStatement(code))
                    end
                end

            # end for julia statement
            elseif operator == "end"
                if depth == 0 && in_block_depth == 0
                    throw(ParserError("end is found at block depth 0"))
                end
                if in_block
                    in_block_depth -= 1
                    push!(code_block[end], TmpStatement("end"))
                else
                    depth -= 1
                    push!(code_block, TmpStatement("end"))
                    if depth == 0
                        push!(elements, TmpCodeBlock(code_block))
                        code_block = SubCodeBlockVector(undef, 0)
                        block_count += 1
                    end
                end

            # julia statement
            else
                if !(operator in ["for", "if", "elseif", "else", "let"])
                    throw(ParserError("This block is invalid: $(m[:left_token])$(m[:code])$(m[:right_token])"))
                end
                if in_block
                    if operator in ["for", "if", "let"]
                        in_block_depth += 1
                    end
                    push!(code_block[end], TmpStatement(code))
                else
                    if operator in ["for", "if", "let"]
                        depth += 1
                    end
                    push!(code_block, TmpStatement(code))
                end
            end

        # jl block
        elseif m[:left_token] == config.jl_block[1]
            code, lstrip_block, trim_block = get_block_config(string(m[:code]))
            new_txt, idx, prev_trim = process_space(txt, m, idx, lstrip_block, trim_block, prev_trim, config)
            # check depth
            if in_block
                push!(code_block[end], new_txt)
            else
                if depth == 0
                    push!(elements, new_txt)
                else
                    push!(code_block, new_txt)
                end
            end

            push!(elements, JLCodeBlock(string(strip(code))))
            jl_block_count += 1
        
        # expression block
        elseif m[:left_token] == config.expression_block[1]
            code = string(strip(m[:code]))
            new_txt, idx, prev_trim = process_space(txt, m, idx, '+', '+', prev_trim, config)

            exp = nothing
            func = match(r"(?<name>>*?)\(.*?\)", code)
            if func === nothing
                exp = VariableBlock(code)
            else
                exp = SuperBlock(length(split(code, ".")))
            end
            # check depth
            if in_block
                push!(code_block[end], new_txt)
                push!(code_block[end], exp)
            else
                if depth == 0
                    push!(elements, new_txt)
                    push!(elements, exp)
                else
                    push!(code_block, new_txt)
                    push!(code_block, exp)
                end
            end
        
        else
            throw(ParserError("This block is invalid: {$(m[:left_token]*" "*m[:code]*" "*m[:right_token])}"))
        end
    end
    push!(elements, txt[idx:end])
    return super, elements, blocks
end

struct ParserError <: Exception
    msg::String
end

Base.showerror(io::IO, e::ParserError) = print(io, "ParserError: "*e.msg)

Token = Union{AbstractString, Symbol}

function tokenizer(txt::String, config::ParserConfig)
    tokens = Vector{Token}()
    idx = 1
    i = 1
    for i in eachindex(txt)
        if txt[i:min(nextind(txt, i, length(config.control_block[1])-1), end)] == config.control_block[1]
            push!(tokens, txt[idx:prevind(txt, i)])
            push!(tokens, :control_start)
            i = nextind(txt, i, length(config.control_block[1]))
            char = txt[i]
            if char == '+'
                push!(tokens, :plus)
                i += 1
            elseif char == '-'
                push!(tokens, :minus)
                i += 1
            end
            idx = i
            block_start = true
        elseif txt[i:min(nextind(txt, i, length(config.control_block[2])-1), end)] == config.control_block[2]
            char = txt[max(1, prevind(txt, i))]
            if char == '+'
                push!(tokens, txt[idx:prevind(txt, i, 2)])
                push!(tokens, :plus)
            elseif char == '-'
                push!(tokens, txt[idx:prevind(txt, i, 2)])
                push!(tokens, :minus)
            else
                push!(tokens, txt[idx:prevind(txt, i)])
            end
            push!(tokens, :control_end)
            idx = nextind(txt, i, length(config.control_block[2]))
        elseif txt[i:min(nextind(txt, i, length(config.expression_block[1])-1), end)] == config.expression_block[1]
            push!(tokens, txt[idx:prevind(txt, i)])
            push!(tokens, :expression_start)
            idx = nextind(txt, i, length(config.expression_block[1]))
        elseif txt[i:min(nextind(txt, i, length(config.expression_block[2])-1), end)] == config.expression_block[2]
            push!(tokens, txt[idx:prevind(txt, i)])
            push!(tokens, :expression_end)
            idx = nextind(txt, i, length(config.expression_block[2]))
        elseif txt[i:min(nextind(txt, i, length(config.jl_block[1])-1), end)] == config.jl_block[1]
            push!(tokens, txt[idx:prevind(txt, i)])
            push!(tokens, :jl_start)
            idx = nextind(txt, i, length(config.jl_block[1]))
        elseif txt[i:min(nextind(txt, i, length(config.jl_block[2])-1), end)] == config.jl_block[2]
            push!(tokens, txt[idx:prevind(txt, i)])
            push!(tokens, :jl_end)
            idx = nextind(txt, i, length(config.jl_block[2]))
        elseif txt[i:min(nextind(txt, i, length(config.comment_block[1])-1), end)] == config.comment_block[1]
            push!(tokens, txt[idx:prevind(txt, i)])
            push!(tokens, :comment_start)
            idx = nextind(txt, i, length(config.comment_block[1]))
        elseif txt[i:min(nextind(txt, i, length(config.comment_block[2])-1), end)] == config.comment_block[2]
            push!(tokens, txt[idx:prevind(txt, i)])
            push!(tokens, :comment_end)
            idx = nextind(txt, i, length(config.comment_block[2]))
        end
    end
    push!(tokens, txt[idx:end])
    return tokens
end

function get_operator(code::String)
    i = 1
    while i <= length(code)
        if code[i] == ' '
            return code[1:i-1]
        end
        i += 1
    end
    return code
end

function push_code_block!(code_block, content, n)
    element = code_block
    for _ in 1:n
        element = element[end]
    end
    push!(element.contents, content)
end

# if nl is true
# newline is also counted
function chop_space(s::AbstractString, config::ParserConfig, nl::Bool, tail::Bool)
    i = 0
    rs, newline = (tail) ? (reverse(s), reverse(config.newline)) : (s, config.newline)
    println(escape_string(rs), escape_string(newline))
    println(nl, tail)
    
    if nl
        while i < length(s)
            if rs[i+1] == ' ' || rs[i+1:i+1] == newline
                i += 1
            elseif rs[i+1:min(nextind(rs, i+1), end)] == newline
                println("OK")
                i += 2
            else
                break
            end
        end
    else
        while i < length(s)
            if rs[i+1] == ' '
                i += 1
            else
                break
            end
        end
    end
    if tail
        println(chop(s, tail=i))
        return chop(s, tail=i)
    else
        return chop(s, head=i, tail=0)
    end
end

function tokens2string(tokens::Vector{Token}, config::ParserConfig)
    txt = ""
    for token in tokens
        if typeof(token) <: AbstractString
            txt *= token
        elseif token == :plus
            txt *= '+'
        elseif token == :minus
            txt *= '-'
        elseif token == :control_start
            txt *= config.control_block[1]
        elseif token == :control_end
            txt *= config.control_block[2]
        elseif token == :expression_start
            txt *= config.expression_block[1]
        elseif token == :expression_end
            txt *= config.expression_block[2]
        elseif token == :jl_start
            txt *= config.jl_block[1]
        elseif token == :jl_end
            txt *= config.jl_block[2]
        elseif token == :comment_start
            txt *= config.comment_block[1]
        elseif token == :comment_end
            txt *= config.comment_block[2]
        end
    end
    return txt
end

function parse_meta(tokens::Vector{Token}, filters::Dict{String, Symbol}, config::ParserConfig; parse_macro::Bool = false, include::Bool=false)
    super = nothing
    out_tokens = Token[""]
    macros = Dict{String, String}()
    macro_def = ""
    macro_content = Vector{Token}()
    comment = false
    raw = false
    raw_idx = [1, 1]
    next_trim = ' '
    i = 1
    while i <= length(tokens)
        # inside of raw block
        if raw
            if tokens[i] == :control_start
                raw_idx[2] = i-1
                i += 1
                lstrip_token = ' '
                # record lstrip token
                if tokens[i] == :plus
                    lstrip_token = '+'
                    i += 1
                elseif tokens[i] == :minus
                    lstrip_token = '-'
                    i += 1
                end
                !(typeof(tokens[i]) <: AbstractString) && throw(ParserError("invalid control block: parser couldn't recognize the inside of control block"))

                code = string(strip(tokens[i]))
                if code == "endraw"
                    raw = false
                    s = tokens2string(tokens[raw_idx[1]:raw_idx[2]], config)
                    if next_trim == ' '
                        if config.trim_blocks
                            if s[1:1] == config.newline
                                s = s[2:end]
                            elseif s[1:min(nextind(s, 1), end)] == config.newline
                                s = s[3:end]
                            end
                        end
                    elseif next_trim == '-'
                        s = chop_space(s, config, true, false)
                    end
                    next_trim = ' '
                    push!(out_tokens, s)
                    i += 1
                else
                    i += 1
                    continue
                end

                # process lstrip token
                if lstrip_token == '-'
                    out_tokens[end] = chop_space(out_tokens[end], config, true, true)
                elseif lstrip_token == ' '
                    if config.lstrip_blocks
                        out_tokens[end] = chop_space(out_tokens[end], config, false, true)
                    end
                end

                # record trim token
                if tokens[i] == :plus
                    next_trim = '+'
                    i += 1
                elseif tokens[i] == :minus
                    next_trim = '-'
                    i += 1
                else
                    next_trim = ' '
                end
                !(tokens[i] == :control_end) && throw(Parser("invalid control block: control block without end token"))
                i += 1
                continue
            else
                i += 1
                continue
            end
        end

        # check end of comment block
        if tokens[i] == :comment_end
            if comment
                comment = false
                i += 1
                continue
            else
                throw(ParserError("invalid end token: end of comment block without start of comment block"))
            end
        end
        # inside of comment block
        if comment
            i += 1
            continue
        end

        # parse inside of macro block
        # this part is largely same to that of out of macro block
        # HACK: I should solve this duplication
        if macro_def != ""
            if tokens[i] == :control_start
                i += 1
                if tokens[i] == :plus
                    i += 1
                elseif tokens[i] == :minus
                    if typeof(macro_content[end]) <: AbstractString
                        macro_content[end] = chop_space(macro_content[end], config, true, true)
                    end
                    i += 1
                else
                    if config.lstrip_blocks && typeof(macro_content[end]) <: AbstractString
                        macro_content[end] = chop_space(macro_content[end], config, false, true)
                    end
                end
                # check format
                !(typeof(tokens[i]) <: AbstractString) && throw(ParserError("invalid control block: parser couldn't recognize the inside of control block"))
                
                code = string(strip(tokens[i]))
                operator = get_operator(code)
                if operator == "raw"
                    raw = true
                elseif operator == "macro"
                    throw(ParserError("nesting macro block is not allowed"))
                elseif operator == "endmacro"
                    if config.autospace && typeof(macro_content[end]) <: AbstractString
                        macro_content[1] = chop_space(macro_content[1], config, true, false)
                        macro_content[end] = chop_space(macro_content[end], config, true, true)
                    end
                    macros[get_macro_name(macro_def)] = build_macro(macro_def, macro_content, filters, config)
                    macro_def = ""
                    macro_content = Vector{Token}()
                elseif operator == "include"
                    file_name = strip(code[8:end])
                    if file_name[1] == file_name[end] == '\"'
                        open(config.dir*"/"*file_name[2:end-1], "r") do f
                            external_tokens, external_macros = parse_meta(tokenizer(read(f, String), config), filters, config, include=true)
                            !isempty(external_macros) && throw(ParserError("nesting macros is not allowed"))
                            append!(macro_content, external_tokens)
                        end
                    else
                        throw(ParserError("failed to include from $file_name: file name have to be enclosed in double quotation marks"))
                    end
                elseif operator == "extends"
                    throw(ParserError("invalid block: `extends` must be at the top of templates"))
                else
                    append!(macro_content, [:control_start, tokens[i], :control_end])
                end
    
                i += 1
                # process trim token
                if tokens[i] == :plus
                    next_trim = '+'
                    i += 1
                elseif tokens[i] == :minus
                    next_trim = '-'
                    i += 1
                else
                    next_trim = ' '
                end
                # check format
                !(tokens[i] == :control_end) && throw(Parser("invalid control block: control block without end token"))
    
                # record the index of start of the raw block
                if raw
                    raw_idx[1] = i + 1
                end
    
            # comment start
            elseif tokens[i] == :comment_start
                comment = true
    
            # push other tokens
            else
                if typeof(tokens[i]) <: AbstractString
                    s = tokens[i]
                    if isempty(s)
                        i += 1
                        continue
                    end
                    if next_trim == ' '
                        if config.trim_blocks
                            if s[1:1] == config.newline
                                s = s[2:end]
                            elseif s[1:min(nextind(s, 1), end)] == config.newline
                                s = s[3:end]
                            end
                        end
                    elseif next_trim == '-'
                        s = chop_space(s, config, true, false)
                    end
                    next_trim = ' '
                    push!(macro_content, s)
                else
                    push!(macro_content, tokens[i])
                end
            end
            i += 1
            continue
        end

        # main control flow
        if tokens[i] == :control_start
            i += 1
            # process lstrip token
            if tokens[i] == :plus
                i += 1
            elseif tokens[i] == :minus
                if typeof(out_tokens[end]) <: AbstractString
                    out_tokens[end] = chop_space(out_tokens[end], config, true, true)
                end
                i += 1
            else
                if config.lstrip_blocks && typeof(out_tokens[end]) <: AbstractString
                    out_tokens[end] = chop_space(out_tokens[end], config, false, true)
                end
            end
            # check format
            !(typeof(tokens[i]) <: AbstractString) && throw(ParserError("invalid control block: parser couldn't recognize the inside of control block"))
            
            code = string(strip(tokens[i]))
            operator = get_operator(code)
            if operator == "raw"
                raw = true
            elseif operator == "macro"
                macro_def = lstrip(code[6:end])
            elseif operator == "import"
                include && throw(ParserError("invalid block: `import` must be at the top of templates"))
                code_tokens = split(code[7:end])
                file_name = code_tokens[1]
                if code_tokens[2] != "as"
                    throw(ParserError("incorrect `import` block: your import block is broken. please look at the docs for detail."))
                end
                alias = code_tokens[3]
                if file_name[1] == file_name[end] == '\"'
                    open(config.dir*"/"*file_name[2:end-1], "r") do f
                        external_macros = parse_meta(tokenizer(read(f, String), config), filters, config, parse_macro=true)
                        for em in external_macros
                            macros[alias*"."*em[1]] = em[2]
                        end
                    end
                else
                    throw(ParserError("failed to import macro from $file_name: file name have to be enclosed in double quotation marks"))
                end
            elseif operator == "from"
                include && throw(ParserError("invalid block: `from` must be at the top of templates"))
                import_st = match(r"from\s*(?<file_name>.*?)\s*import(?<body>.*)", code)
                if isnothing(import_st)
                    throw(ParserError("incorrect `import` block: your import block is broken. please look at the docs for detail."))
                end
                file_name = import_st[:file_name]
                external_macros = Dict()
                open(config.dir*"/"*file_name[2:end-1], "r") do f
                    external_macros = parse_meta(tokenizer(read(f, String), config), filters, config, parse_macro=true)
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
            elseif operator == "include"
                file_name = strip(code[8:end])
                if file_name[1] == file_name[end] == '\"'
                    open(config.dir*"/"*file_name[2:end-1], "r") do f
                        external_tokens, external_macros = parse_meta(tokenizer(read(f, String), config), filters, config, include=true)
                        for em in external_macros
                            macros[alias*"."*em[1]] = em[2]
                        end
                        append!(out_tokens, external_tokens)
                    end
                else
                    throw(ParserError("failed to include from $file_name: file name have to be enclosed in double quotation marks"))
                end
            elseif operator == "extends"
                include && throw(ParserError("invalid block: `extends` must be at the top of templates"))
                file_name = strip(code[8:end])
                if file_name[1] == file_name[end] == '\"'
                    super = Template(config.dir*"/"*file_name[2:end-1], config = config2dict(config))
                else
                    throw(ParserError("failed to read $file_name: file name have to be enclosed in double quotation marks"))
                end
            else
                append!(out_tokens, [:control_start, tokens[i], :control_end])
            end

            i += 1
            # process trim token
            if tokens[i] == :plus
                next_trim = '+'
                i += 1
            elseif tokens[i] == :minus
                next_trim = '-'
                i += 1
            else
                next_trim = ' '
            end
            # check format
            !(tokens[i] == :control_end) && throw(ParserError("invalid control block: control block without end token"))

            # record the index of start of the raw block
            if raw
                raw_idx[1] = i + 1
            end

        # comment start
        elseif tokens[i] == :comment_start
            comment = true

            i += 1
            # process lstrip token
            if tokens[i] == :plus
                i += 1
            elseif tokens[i] == :minus
                if typeof(out_tokens[end]) <: AbstractString
                    out_tokens[end] = chop_space(out_tokens[end], config, true, true)
                end
                i += 1
            else
                if config.lstrip_blocks && typeof(out_tokens[end]) <: AbstractString
                    out_tokens[end] = chop_space(out_tokens[end], config, false, true)
                end
            end
            continue

        # push other(assumed to be string) tokens
        else
            if typeof(tokens[i]) <: AbstractString
                s = tokens[i]
                if isempty(s)
                    i += 1
                    continue
                end
                if next_trim == ' '
                    if config.trim_blocks && tokens[max(i-1, 1)] in [:control_end, :comment_end]
                        if s[1:1] == config.newline
                            s = s[2:end]
                        elseif s[1:min(nextind(s, 1), end)] == config.newline
                            s = s[3:end]
                        end
                    end
                elseif next_trim == '-'
                    s = chop_space(s, config, true, false)
                end
                next_trim = ' '
                push!(out_tokens, s)
            else
                push!(out_tokens, tokens[i])
            end
        end
        i += 1
    end
    if parse_macro
        return macros
    elseif include
        return apply_macros(filter(x->x!="", out_tokens), macros, config), macros
    else
        return super, apply_macros(filter(x->x!="", out_tokens), macros, config)
    end
end

function parse_template(txt::String, filters::Dict{String, Symbol}, config::ParserConfig)
    # tokenize
    tokens = tokenizer(txt, config)
    # process meta information
    super, tokens = parse_meta(tokens, filters, config)

    # array to store blocks
    blocks = Vector{TmpBlock}()
    # if position is in block this variable has non-zero value
    # this variable is also used to validate the depth of start and end position
    in_block_depth = 0
    # code block depth
    depth = 0
    
    # prepare the array to store the code blocks
    elements = CodeBlockVector(undef, 0)
    code_block = SubCodeBlockVector(undef, 0)
    
    i = 1
    code = ""
    while i <= length(tokens)
        if tokens[i] == :control_start
            i += 1
            code = strip(tokens[i])
            contents = split(code)
            operator = contents[1]
            
            if operator == "endblock"
                if in_block_depth == 0
                    throw(ParserError("invalid end of block: `endblock` statement without `block` statement"))
                end
                in_block_depth -= 1
                if in_block_depth == 0
                    if depth == 0
                        push!(elements, TmpCodeBlock(code_block))
                        push!(blocks, code_block[end])
                        code_block = SubCodeBlockVector(undef, 0)
                    else
                        element = code_block
                        for _ in 1:n
                            element = element[end]
                        end
                        push!(blocks, element)
                    end
                end
                
            elseif operator == "block"
                if in_block_depth == 0
                    push!(code_block, TmpBlock(contents[2], Vector()))
                else
                    push_code_block!(code_block, TmpBlock(contents[2], Vector()), in_block_depth)
                end
                in_block_depth += 1
                
            elseif operator == "set"
                if in_block_depth != 0
                    push_code_block!(code_block, TmpStatement(code), in_block_depth)
                elseif depth == 0
                    push!(elements, TmpCodeBlock([TmpStatement(code[4:end])]))
                else
                    push!(code_block, TmpStatement(code))
                end

            elseif operator == "end"
                if depth == 0 && in_block_depth == 0
                    throw(ParserError("`end` is found at block depth 0"))
                elseif in_block_depth != 0
                    push_code_block!(code_block, TmpStatement("end"), in_block_depth)
                else
                    depth -= 1
                    push!(code_block, TmpStatement("end"))
                    if depth == 0
                        push!(elements, TmpCodeBlock(code_block))
                        code_block = SubCodeBlockVector(undef, 0)
                    end
                end

            else
                if !(operator in ["for", "if", "elseif", "else", "let"])
                    throw(ParserError("this block is invalid: $code"))
                end
                if in_block_depth != 0
                    push_code_block!(code_block, TmpStatement(code), in_block_depth)
                else
                    if operator in ["for", "if", "let"]
                        depth += 1
                    end
                    push!(code_block, TmpStatement(code))
                end
            end
            
            tokens[i+1] != :control_end && throw(ParserError("invalid control block: this block is not closed"))
            i += 1
            
        elseif tokens[i] == :expression_start
            i += 1
            code = strip(tokens[i])

            exp = (occursin(r"\(.*?\)", code)) ? SuperBlock(length(split(code, "."))) : VariableBlock(code)
            if in_block_depth != 0
                push_code_block!(code_block, exp, in_block_depth)
            elseif depth == 0
                push!(elements, exp)
            else
                push!(code_block, exp)
            end
            tokens[i+1] != :expression_end && throw(ParserError("invalid expression block: this block is not closed"))
            i += 1
            
        elseif tokens[i] == :jl_start
            i += 1
            code = tokens[i]
            if in_block_depth != 0
                push_code_block!(code_block, JLCodeBlock(code), in_block_depth)
            elseif depth == 0
                push!(elements, JLCodeBlock(code))
            else
                push!(code_block, JLCodeBlock(code))
            end
            tokens[i+1] != :jl_end && throw(ParserError("invalid jl block: this block is not closed"))
            i += 1
            
        elseif typeof(tokens[i]) <: AbstractString
            if in_block_depth != 0
                push_code_block!(code_block, tokens[i], in_block_depth)
            elseif depth == 0
                push!(elements, tokens[i])
            else
                push!(code_block, tokens[i])
            end
        else
            throw(ParserError("unexpexted token: $(tokens[i]) is unexpected. maybe the parser is broken."))
        end
        i += 1
    end
    return super, elements, blocks
end

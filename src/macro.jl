function get_macro_name(macro_def::AbstractString)
    for i in 1 : length(macro_def)
        if @inbounds macro_def[i] == '('
            return @inbounds macro_def[1:i-1]
        end
    end
end
function get_macro_args(macro_def::AbstractString)
    for i in 1 : length(macro_def)
        if @inbounds macro_def[i] == '('
            return macro_def[i:end]
        end
    end
end

function build_macro(macro_def::AbstractString, contents::Vector{Token}, config::ParserConfig)
    out_contents = Vector{Token}()
    i = 1
    while i <= length(contents)
        if contents[i] == :expression_start
            i += 1
            code = string(strip(contents[i]))
            if occursin("|>", code)
                exp = split(code, "|>")
                f = filters_alias[exp[2]]
                if config.autospace && f != htmlesc
                    push!(out_contents, "\$(htmlesc($f(string($(exp[1])))))")
                else
                    push!(out_contents, "\$($f(string($(exp[1]))))")
                end
            else
                if config.autospace
                    push!(out_contents, "\$(htmlesc(string($(code))))")
                else
                    push!(out_contents, "\$"*code)
                end
            end
            contents[i+1] != :expression_end && throw(ParserError("invalid expression block: this block is not closed"))
            i += 1
        else
            push!(out_contents, contents[i])
        end
        i += 1
    end
    return get_macro_args(macro_def) * " = " * replace(string(out_contents), "\\\$"=>"\$")
end

function apply_macros(tokens::Vector{Token}, macros::Dict{String, String}, config::ParserConfig)
    for m in macros
        name = m[1]
        path = split(name, ".")
        if length(path) != 1
            name = path[end]
        end
        eval(Meta.parse(name*m[2]))
    end
    
    regex = r"\s*(?<name>.*?)(?<args>\(.*?\))"
    i = 1
    while i <= length(tokens)
        if tokens[i] == :expression_start
            i += 1
            # check wether the block is a macro caller or not
            r = match(regex, tokens[i])
            r == nothing && continue
            !haskey(macros, r[:name]) && continue
            
            path = split(r[:name], ".")
            if length(path) != 1
                name = path[end]
            else
                name = r[:name]
            end
            
            macro_out = nothing
            try
                macro_out = eval(Meta.parse(name*r[:args]))
            catch e
                throw(ParserError("invalid macro; failed to call macro in $(tokens[i]) because of the following error\n$e"))
            end
            
            tokens[i+1] != :expression_end && throw(ParserError("invalid expression block: this block is not closed"))
            tokens = vcat(tokens[1:i-2], macro_out, tokens[i+2:end])
            i+=length(macro_out)
            continue
        end
        i += 1
    end
    return tokens
end
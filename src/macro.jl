get_macro_name(macro_def::String) = match(r"(?<name>.*?)\(.*?\)", macro_def)[:name]
get_macro_args(macro_def::String) = match(r".*?(?<args>\(.*?\))", macro_def)[:args]

function build_macro(macro_def::String, txt::String, filters::Dict{String, Symbol}, config::ParserConfig)
    out_txt = ""
    idx = 1
    for m in eachmatch(r"\{\{\s*(?<variable>.*?)\s*\}\}", txt)
        if occursin("|>", m[:variable])
            exp = split(m[:variable], "|>")
            f = filters[exp[2]]
            if config.autoescape && f != htmlesc
                out_txt *= txt[idx:m.offset-1] * "\$(htmlesc($f(string($(exp[1])))))"
            else
                out_txt *= txt[idx:m.offset-1] * "\$($f(string($(exp[1]))))"
            end
        else
            if config.autoescape
                out_txt *= txt[idx:m.offset-1] * "\$(htmlesc(string($(m[:variable]))))"
            else
                out_txt *= txt[idx:m.offset-1] * "\$" * m[:variable]
            end
        end
        idx = m.offset + length(m.match)
    end
    out_txt *= txt[idx:end]
    return get_macro_args(macro_def) * "-> \"\"\"" * out_txt * "\"\"\""
end

function apply_macros(txt::String, macros::Dict{String, String}, config::ParserConfig)
    for (name, def) in zip(keys(macros), values(macros))
        path = split(name, ".")
        if length(path) != 1
            name = path[end]
        end
        eval(Meta.parse(name*"="*def))
    end
    re = Regex("$(config.expression_block[1])\\s*(?<name>.*?)(?<body>\\(.*?\\))\\s*$(config.expression_block[2])")
    m = match(re, txt)
    while !isnothing(m)
        split(m[:name], ".")[end] == "super" && break
        if haskey(macros, m[:name])
            path = split(m[:name], ".")
            if length(path) != 1
                name = path[end]
            else
                name = m[:name]
            end
            try
                txt = txt[1:m.offset-1]*eval(Meta.parse(name*m[:body]))*txt[m.offset+length(m.match):end]
            catch e
                throw(ParserError("invalid macro: failed to call macro in $(m.match) because of the following error\n$e"))
            end
        end
        m = match(re, txt)
    end
    return txt
end
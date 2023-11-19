get_macro_name(macro_def) = match(r"(?<name>.*?)\(.*?\)", macro_def)[:name]

function build_macro(macro_def::String, txt::String, filters::Dict{String, Function}, config::ParserConfig)
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
            try
                txt = txt[1:m.offset-1]*eval(Meta.parse("Base.@invokelatest _"*split(m[:name], ".")[end]*"_"*m[:body]))*txt[m.offset+length(m.match):end]
            catch e
                throw(ParserError("invalid macro: failed to call macro in $(m.match) because of the following error\n$e"))
            end
        end
        m = match(re, txt)
    end
    return txt
end
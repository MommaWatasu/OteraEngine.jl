"""
    Template(html::String; path::Bool=true, config_path::String="",
        config::Dict{String, T} = Dict(
            "code_block_start"=>"```",
            "code_block_stop"=>"```"
        )
    )
This is the only structure and function of this package.
This structure has 2 parameter,
- `html` is the path to the HTML file or HTML of String type.
- `path` determines whether the parameter `html` represents the file path. The default value is `true`.
- `config_path` is path to config file. The suffix of config file must be `toml`.
- `config` is configuration of Template. It is type of `Dict`, and now there are two settings bellow.
    - `code_block_start` : The string at the start of code blocks.
    - `code_block_stop` : The string at the end of code blocks.

# Config File
A config file must be written in TOML format. like this:
```
code_block_start = "{{"
code_block_stop = "}}"
```
The item is the same as the argiment `config`.

# HTML
You can write the code of Template in JuliaLang, and just write the variables you want to output to a HTML at the end of the code.
The code needs to be enclosed by ```(This can be changed by `config` variable).

For exmaple, this HTML work:
```
<html>
    <head><title>OteraEngine Test</title></head>
    <body>
        Hello, ```usr```!
    </body>
</html>
```

# Rendering
After you create a Template, you just have to execute the codes! For this, you use the Function-like Object of Template structure.`tmp(; init::Dict{String, T}) where T <: Any` variables are initialized by `init`(`init` is the parameter for Function-like Object). `init` must be `Dict`type. If you don't pass the `init`, the initialization won't be done.
Please see the example below.

# Example
```@repl
tmp = Template("./test1.html") #The last HTML code
init = Dict("usr"=>"OteraEngine")
result = tmp(init)
println(result)
```
"""
struct Template
    txt::String
    top_codes::Array{String, 1}
    jl_codes::Array{String, 1}
    tmp_codes::Array{TmpCodeBlock, 1}
    config::ParserConfig
end

function Template(txt::String; path::Bool=true, config_path::String="",
        config::Dict{String, String} = Dict(
            "jl_block_start"=>"```",
            "jl_block_stop"=>"```",
            "tmp_block_start"=>"{%",
            "tmp_block_stop"=>"%}",
            "variable_block_start"=>"{{",
            "variable_block_stop"=>"}}"
        )
    )
    if path
        open(txt, "r") do f
            txt = read(f, String)
        end
    end
    if config_path!=""
        conf_file = parse_config(config_path)
        for v in keys(conf_file)
            config[v] = conf_file[v]
        end
    end
    config = ParserConfig(config)
    return Template(parse_text(txt, config)..., config)
end

struct TemplateError <: Exception
    msg::String
end

Base.showerror(io::IO, e::ParserError) = print(io, "TemplateError: "*e.msg)

function (Tmp::Template)(; tmp_init::Dict{String, S}=Dict{String, Any}(), jl_init::Dict{String, T}=Dict{String, Any}()) where {S, T}
    tmp_args = ""
    for v in keys(tmp_init)
        tmp_args*=(v*",")
    end
    
    jl_args = ""
    for v in keys(jl_init)
        jl_args*=(v*",")
    end
    
    out_txt = Tmp.txt
    tmp_def = "function tmp_func("*tmp_args*");txts=Array{String}(undef, 0);"
    for tmp_code in Tmp.tmp_codes
        tmp_def*=tmp_code()
    end
    tmp_def*="end"
    eval(Meta.parse(tmp_def))
    txts = Base.invokelatest(tmp_func, values(tmp_init)...)
    for (i, txt) in enumerate(txts)
        out_txt = replace(out_txt, "<tmpcode$i>"=>txt)
    end
    
    for top_code in Tmp.top_codes
        eval(Meta.parse(top_code))
    end
    
    for (i, jl_code) in enumerate(Tmp.jl_codes)
        eval(Meta.parse("function f("*jl_args*");"*jl_code*"end"))
        out_txt = replace(out_txt, "<jlcode$i>"=>string(Base.invokelatest(f, values(jl_init)...)))
    end
    return assign_variables(out_txt, tmp_init, Tmp.config.variable_block)
end

function assign_variables(txt::String, tmp_init::Dict{String, T}, variable_block::Tuple{String, String}) where T
    for m in eachmatch(r"{{\s*(?<variable>[\s\S]*?)\s*?}}", txt)
        if m[:variable] in keys(tmp_init)
            txt = replace(txt, m.match=>tmp_init[m[:variable]])
        end
    end
    return txt
end
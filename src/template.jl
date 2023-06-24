"""
    Template(txt::String; path::Bool=true, config_path::String="", config::Dict{String, String} = Dict())
This is the only structure and function of this package.
This structure has 4 parameter,
- `txt` is the path to the template file or template of String type.
- `path` determines whether the parameter `txt` represents the file path. The default value is `true`.
- `config_path` is path to config file. The suffix of config file must be `toml`.
- `config` is configuration of template. It is type of `Dict`, please see [configuraiton](#Configurations) for more detail.

# Rendering
After you create a Template, you just have to execute the codes! For this, you use the Function-like Object of Template structure.`tmp(; jl_init::Dict{String, String}, tmp_init::Dict{String, String})` variables are initialized by `jl_init`(for julia code) and `tmp_init`(for template code). These parameters must be `Dict` type. If you don't pass the `jl_init` or `tmp_init`, the initialization won't be done.

# Example
This is a simple usage:
```jldoctest
julia> using OteraEngine
julia> txt = "```using Dates; now()```. Hello {{ usr }}!"
julia> tmp = Template(txt, path = false)
julia> init = Dict("usr"=>"OteraEngine")
julia> tmp(tmp_init = init)
```
"""
struct Template
    txt::String
    top_codes::Array{String, 1}
    jl_codes::Array{String, 1}
    tmp_codes::Array{TmpCodeBlock, 1}
    config::ParserConfig
end

function Template(txt::String; path::Bool=true, config_path::String="", config::Dict{String, String} = Dict{String, String}())
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
    config_dict = Dict{String, String}(
        "jl_block"=>"```",
        "tmp_block_start"=>"{%",
        "tmp_block_stop"=>"%}",
        "variable_block_start"=>"{{",
        "variable_block_stop"=>"}}"
    )
    for key in keys(config)
        config_dict[key] = config[key]
    end
    config = ParserConfig(config_dict)
    return Template(parse_template(txt, config)..., config)
end

struct TemplateError <: Exception
    msg::String
end

Base.showerror(io::IO, e::TemplateError) = print(io, "TemplateError: "*e.msg)

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
    txts = ""
    try
        txts = Base.invokelatest(tmp_func, values(tmp_init)...)
    catch e
        throw(TemplateError("$e has occurred during processing tmp code blocks. if you can't find any problems in your template, please report issue on https://github.com/MommaWatasu/OteraEngine.jl/issues."))
    end
    for (i, txt) in enumerate(txts)
        out_txt = replace(out_txt, "<tmpcode$i>"=>txt)
    end
    
    Pkg.activate()
    for top_code in Tmp.top_codes
        eval(Meta.parse(top_code))
    end
    
    for (i, jl_code) in enumerate(Tmp.jl_codes)
        eval(Meta.parse("function f("*jl_args*");"*jl_code*";end"))
        try
            out_txt = replace(out_txt, "<jlcode$i>"=>string(Base.invokelatest(f, values(jl_init)...)))
        catch e
            throw(TemplateError("$e has occurred during processing jl code blocks. if you can't find any problems in your template, please report issue on https://github.com/MommaWatasu/OteraEngine.jl/issues."))
        end
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
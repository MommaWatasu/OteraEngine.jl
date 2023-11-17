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
```julia-repl
julia> using OteraEngine
julia> txt = "```using Dates; now()```. Hello {{ usr }}!"
julia> tmp = Template(txt, path = false)
julia> init = Dict("usr"=>"OteraEngine")
julia> tmp(tmp_init = init)
```
"""
struct Template
    super::Union{Nothing, Template}
    txt::String
    tmp_codes::Vector{TmpCodeBlock}
    top_codes::Vector{String}
    jl_codes::Vector{String}
    blocks::Vector{TmpBlock}
    filters::Dict{String, Function}
    config::ParserConfig
end

function Template(
        txt::String;
        path::Bool=true,
        filters::Dict{String, Function} = Dict{String, Function}(),
        config_path::String="",
        config::Dict{String, Union{String, Bool}} = Dict{String, Union{String, Bool}}()
    )
    dir = pwd()
    if path
        if dirname(txt) == ""
            dir = "."
        else
            dir = dirname(txt)
        end
    end
    if path
        open(txt, "r") do f
            txt = read(f, String)
        end
    end
    filters = build_filters(filters)
    config = build_config(config_path, config)
    return Template(parse_template(txt, config)..., filters, config)
end

function build_filters(filters::Dict{String, Function})
    filters_dict = Dict{String, Function}(
        "e" => htmlesc,
        "escape" => htmlesc,
        "upper" => uppercase,
        "lower" => lowercase,
    )
    for key in keys(filters)
        filters_dict[key] = filters[key]
    end
    return filters_dict
end

function build_config(config_path, config)
    if config_path!=""
        conf_file = parse_config(config_path)
        for v in keys(conf_file)
            config[v] = conf_file[v]
        end
    end
    config_dict = Dict{String, Union{String, Bool}}(
        "control_block_start"=>"{%",
        "control_block_end"=>"%}",
        "expression_block_start"=>"{{",
        "expression_block_end"=>"}}",
        "jl_block_start" => "{<",
        "jl_block_end" => ">}",
        "comment_block_start" => "{#",
        "comment_block_end" => "#}",
        "space_control" => true,
        "lstrip_blocks" => false,
        "trim_blocks" => false,
        "dir" => dir
    )
    for key in keys(config)
        config_dict[key] = config[key]
    end
    return ParserConfig(config_dict)
end

struct TemplateError <: Exception
    msg::String
end

Base.showerror(io::IO, e::TemplateError) = print(io, "TemplateError: "*e.msg)

function (Tmp::Template)(; tmp_init::Dict{String, T}=Dict{String, Any}(), jl_init::Dict{String, N}=Dict{String, Any}()) where {T, N}
    if Tmp.super !== nothing
        return Tmp.super(tmp_init, jl_init, Tmp.blocks)
    end

    # preparation for tmp block
    tmp_args = ""
    for v in keys(tmp_init)
        tmp_args*=(v*",")
    end
    
    # execute tmp block
    out_txt = Tmp.txt
    tmp_def = "function tmp_func("*tmp_args*");txts=Array{String}(undef, 0);"
    for tmp_code in Tmp.tmp_codes
        tmp_def*=tmp_code(Tmp.blocks, Tmp.config.expression_block, Tmp.filters)
    end
    tmp_def*="end"
    # escape sequence is processed here and they don't remain in function except `\n`.
    # If I have to aplly those escape sequence, I sohuld replace them like this:
    # \r -> \\r
    # And the same this occurs in jl code block
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

    # preparation for jl block
    jl_dargs = ""
    jl_args = ""
    for p in jl_init
        jl_dargs*=(p[1]*",")
        if typeof(p[2]) <: Number
            jl_args*=(p[2]*",")
        else
            jl_args*=("\""*p[2]*"\""*",")
        end
    end

    # execute tmp block
    current_env = Base.active_project()
    for (i, jl_code) in enumerate(Tmp.jl_codes)
        jl_code = replace("using Pkg; Pkg.activate(\"$current_env\"); "*Tmp.top_codes[i]*"function f("*jl_dargs*");"*jl_code*";end; println(f("*jl_args*"))", "\\"=>"\\\\")
        try
            out_txt = replace(out_txt, "<jlcode$i>"=>rstrip(read(`julia -e $jl_code`, String)))
        catch e
            throw(TemplateError("$e has occurred during processing jl code blocks. if you can't find any problems in your template, please report issue on https://github.com/MommaWatasu/OteraEngine.jl/issues."))
        end
    end
    
    return assign_variables(out_txt, tmp_init, Tmp.config.expression_block)
end

function (Tmp::Template)(tmp_init::Dict{String, T}, jl_init::Dict{String, N}, blocks::Vector{TmpBlock}) where {T, N}
    blocks = inherite_blocks(blocks, Tmp.blocks, Tmp.config.expression_block)
    if Tmp.super !== nothing
        Tmp.super(tmp_init, blocks)
    end

    # preparation for tmp block
    tmp_args = ""
    for v in keys(tmp_init)
        tmp_args*=(v*",")
    end

    # execute tmp block
    out_txt = Tmp.txt
    tmp_def = "function tmp_func("*tmp_args*");txts=Array{String}(undef, 0);"
    for tmp_code in Tmp.tmp_codes
        tmp_def*=tmp_code(blocks, Tmp.config.expression_block, Tmp.filters)
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

    # preparation for jl block
    jl_dargs = ""
    jl_args = ""
    for p in jl_init
        jl_dargs*=(p[1]*",")
        if typeof(p[2]) <: Number
            jl_args*=(p[2]*",")
        else
            jl_args*=("\""*p[2]*"\""*",")
        end
    end

    # execute jl block
    current_env = Base.active_project()
    for (i, jl_code) in enumerate(Tmp.jl_codes)
        jl_code = replace("using Pkg; Pkg.activate(\"$current_env\"); "*Tmp.top_codes[i]*"function f("*jl_dargs*");"*jl_code*";end; println(f("*jl_args*"))", "\\"=>"\\\\")
        try
            out_txt = replace(out_txt, "<jlcode$i>"=>rstrip(read(`julia -e $jl_code`, String)))
        catch e
            throw(TemplateError("$e has occurred during processing jl code blocks. if you can't find any problems in your template, please report issue on https://github.com/MommaWatasu/OteraEngine.jl/issues."))
        end
    end

    return assign_variables(out_txt, tmp_init, Tmp.config.expression_block)
end

function inherite_blocks(src::Vector{TmpBlock}, dst::Vector{TmpBlock}, expression_block::Tuple{String, String})
    for i in 1 : length(src)
        idx = findfirst(x->x.name==src[i].name, dst)
        idx === nothing && continue
        dst[idx] = process_super(dst[idx], src[i], expression_block)
    end
    return dst
end

function assign_variables(txt::String, tmp_init::Dict{String, T}, expression_block::Tuple{String, String}) where T
    re = Regex("$(config.expression_block[1])\\s*(?<variable>[\\s\\S]*?)\\s*?$(config.expression_block[2])")
    for m in eachmatch(re, txt)
        if m[:variable] in keys(tmp_init)
            txt = replace(txt, m.match=>tmp_init[m[:variable]])
        end
    end
    return txt
end
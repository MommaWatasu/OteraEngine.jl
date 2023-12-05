"""
    Template(txt::String; path::Bool=true, config_path::String="", config::Dict{String, String} = Dict())
This is the only structure and function of this package.
This structure has 4 parameter,
- `txt` is the path to the template file or template of String type.
- `path` determines whether the parameter `txt` represents the file path. The default value is `true`.
- `filters` is used to register non-builtin filters. Please see [filters](#Filters) for more details.
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
    elements::Vector{Union{String, JLCodeBlock, TmpCodeBlock, TmpBlock, VariableBlock, SuperBlock}}
    top_codes::Vector{String}
    blocks::Vector{TmpBlock}
    filters::Dict{String, Function}
    config::ParserConfig
end

function Template(
        txt::String;
        path::Bool=true,
        filters::Dict{String, <:Function} = Dict{String, Function}(),
        config_path::String="",
        config::Dict{String, K} = Dict{String, Union{String, Bool}}()
    ) where {K}
    # set default working directory
    dir = pwd()
    if path
        if dirname(txt) == ""
            dir = "."
        else
            dir = dirname(txt)
        end
    end

    # load text
    if path
        open(txt, "r") do f
            txt = read(f, String)
        end
    end

    # build config
    filters = build_filters(filters)
    config = build_config(dir, config_path, config)
    return Template(parse_template(txt, filters, config)..., filters, config)
end

function build_filters(filters::Dict{String, <:Function})
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

function build_config(dir::String, config_path::String, config::Dict{String, K}) where {K}
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
        "autospace" => false,
        "lstrip_blocks" => false,
        "trim_blocks" => false,
        "autoescape" => true,
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

function (Tmp::Template)(; init::Dict{String, T}=Dict{String, Any}()) where {T}
    if Tmp.super !== nothing
        return Tmp.super(init, Tmp.blocks)
    end

    eval(build_render(Tmp.elements, init, Tmp.filters, Tmp.config.autoescape))
    try
        return Base.invokelatest(template_render, values(init)...)
    catch e
        throw(TemplateError("failed to render: following error occurred during rendering:\n$e"))
    end
end

function (Tmp::Template)(init::Dict{String, T}, blocks::Vector{TmpBlock}) where {T}
    blocks = inherite_blocks(blocks, Tmp.blocks)
    if Tmp.super !== nothing
        return Tmp.super(init, blocks)
    end
    elements = apply_inheritance(Tmp.elements, blocks)

    eval(build_render(elements, init, Tmp.filters, Tmp.config.autoescape))
    try
        return Base.invokelatest(template_render, values(init)...)
    catch e
        thtow(TemplateError("failed to render: following error occurred during rendering:\n$e"))
    end
end

function build_render(elements, init::Dict{String, T}, filters::Dict{String, Function}, autoescape::Bool) where {T}
    body = quote
        txt = ""
    end
    for e in elements
        t = typeof(e)
        if t == String
            push!(body.args, :(txt *= $(replace(e, "\""=>"\\\""))))
        elseif t == JLCodeBlock
            push!(body.args, :(txt *= string(begin; $(Meta.parse(e.code));end)))
        elseif t == TmpCodeBlock
            push!(body.args, e(filters, autoescape))
        elseif t == TmpBlock
            push!(body.args, e(filters, autoescape))
        elseif t == VariableBlock
            if occursin("|>", e.exp)
                exp = map(strip, split(e.exp, "|>"))
                f = filters[exp[2]]
                if autoescape && f != htmlesc
                    push!(body.args, :(txt *= htmlesc($(Symbol(f))(string($(Symbol(exp[1])))))))
                else
                    push!(body.args, :(txt *= Symbol(f)(string($(Symbol(exp[1]))))))
                end
            else
                if autoescape
                    push!(body.args, :(txt *= htmlesc(string($(Symbol(e.exp))))))
                else
                    push!(body.args, :(txt *= string($(Symbol(e.exp)))))
                end
            end
        elseif t == SuperBlock
            throw(TemplateError("invalid super block is found"))
        end
    end
    return Expr(:function, Expr(:call, :template_render, map(Symbol, collect(keys(init)))...), body)
end
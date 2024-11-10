"""
    Template(
        txt::String;
        path::Bool=true,
        filters::Dict{String, Symbol},
        config_path::String="",
        config::Dict{String, String} = Dict()
    )
This is the only structure and function of this package.
This structure has 4 parameter,
- `txt` is the path to the template file or template of String type.
- `path` determines whether the parameter `txt` represents the file path. The default value is `true`.
- `filters` is used to register non-builtin filters. Please see [filters](#Filters) for more details.
- `config_path` is path to config file. The suffix of config file must be `toml`.
- `config` is configuration of template. It is type of `Dict`, please see [configuraiton](#Configurations) for more detail.

# Rendering
After you create a Template, you just have to execute the codes! For this, you use the Function-like Object of Template structure.`tmp(; init::Dict{String, T}) where {T}` variables are initialized by `init` Dict which contains the pair of name(String) and value. If you don't pass the `init`, the initialization won't be done.

# Example
This is a simple usage:
```julia-repl
julia> using OteraEngine
julia> txt = "Hello {{ usr }}!"
julia> tmp = Template(txt, path = false)
julia> init = Dict("usr"=>"OteraEngine")
julia> tmp(init = init)
```
"""
struct Template
    super::Union{Nothing, Template}
    elements::CodeBlockVector
    blocks::Vector{TmpBlock}
    filters::Dict{String, Symbol}
    config::ParserConfig
end

function Template(
        txt::String;
        path::Bool=true,
        filters::Dict{String, Symbol} = Dict{String, Symbol}(),
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
    tmp_filters = define_filters(filters)
    config = build_config(dir, config_path, config)
    return Template(parse_template(txt, tmp_filters, config)..., tmp_filters, config)
end

function define_filters(filters::Dict{String, Symbol})
    filters_dict = Dict{String, Symbol}(
        "e" => :htmlesc,
        "escape" => :htmlesc,
        "upper" => :uppercase,
        "lower" => :lowercase,
        "safe" => :safe,
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
        "newline" => (Sys.islinux()) ? "\n" : "\r\n",
        "autospace" => true,
        "lstrip_blocks" => true,
        "trim_blocks" => true,
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

    for filter in filters
        eval(filter)
    end
    template_render = build_render(Tmp.elements, init, Tmp.filters, Tmp.config.newline, Tmp.config.autoescape)
    try
        return string(lstrip(Base.invokelatest(template_render, values(init)...)))
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

    for filter in filters
        eval(filter)
    end
    template_render = build_render(elements, init, Tmp.filters, Tmp.config.newline, Tmp.config.autoescape)
    try
        return string(lstrip(Base.invokelatest(template_render, values(init)...)))
    catch e
        throw(TemplateError("failed to render: following error occurred during rendering:\n$e"))
    end
end

function build_render(elements::CodeBlockVector, init::Dict{String, T}, filters::Dict{String, Symbol}, newline::String, autoescape::Bool) where {T}
    body = quote
        txt = ""
    end
    for e in elements
        if typeof(e) <: AbstractString
            push!(body.args, :(txt *= $e))
        elseif isa(e, JLCodeBlock)
            code = Meta.parse(replace(rstrip(e.code), newline=>";"))
            if isa(code, Expr)
                if code.head == :toplevel
                    code = Expr(:block, code.args...)
                end
            end
            push!(body.args, :(txt *= string(eval($code))))
        elseif isa(e, TmpCodeBlock)
            push!(body.args, e(filters, newline, autoescape))
        elseif isa(e, TmpBlock)
            push!(body.args, e(filters, newline, autoescape))
        elseif isa(e, VariableBlock)
            if occursin("|>", e.exp)
                exp = map(strip, split(e.exp, "|>"))
                f = filters[exp[2]]
                if autoescape && f != htmlesc
                    push!(body.args, :(txt *= htmlesc($f(string($(Symbol(exp[1])))))))
                else
                    push!(body.args, :(txt *= $f(string($(Symbol(exp[1]))))))
                end
            else
                if autoescape
                    push!(body.args, :(txt *= htmlesc(string($(Symbol(e.exp))))))
                else
                    push!(body.args, :(txt *= string($(Symbol(e.exp)))))
                end
            end
        elseif isa(e, SuperBlock)
            throw(TemplateError("invalid super block is found"))
        end
    end
    push!(body.args, :(return txt))
    println(body)
    return eval(Expr(:->, 
        Expr(:tuple, map(Symbol, collect(keys(init)))...),
    body))
end
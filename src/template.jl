abstract type AbstractTemplate end

struct ExtendTemplate <: AbstractTemplate
    super::Union{Nothing, ExtendTemplate}
    elements::CodeBlockVector
    blocks::Vector{TmpBlock}
end

function ExtendTemplate(
    path::String,
    config::ParserConfig
)
    txt = ""
    open(path, "r") do f
        txt = read(f, String)
    end

    return ExtendTemplate(parse_template(txt, config)...)
end

"""
    Template(
        txt::String;
        path::Bool=true,
        config_path::String="",
        config::Dict{String, String} = Dict()
    )
This is the only structure and function of this package.
This structure has 4 parameter,
- `txt` is the path to the template file or template of String type.
- `path` determines whether the parameter `txt` represents the file path. The default value is `true`.
- `config_path` is path to config file. The suffix of config file must be `toml`.
- `config` is configuration of template. It is type of `Dict`, please see [configuraiton](#Configurations) for more detail.

# Rendering
After you create a Template, you just have to execute the codes! For this, you use the Function-like Object of Template structure.`tmp(; init::Dict{Symbol, T}) where {T}` variables are initialized by `init` Dict which contains the pair of name(String) and value. If you don't pass the `init`, the initialization won't be done.

# Example
This is a simple usage:
```julia-repl
julia> using OteraEngine
julia> txt = "Hello {{ usr }}!"
julia> tmp = Template(txt, path = false)
julia> init = Dict(:usr=>"OteraEngine")
julia> tmp(init = init)
```
"""
struct Template <: AbstractTemplate
    super::Union{Nothing, ExtendTemplate}
    elements::CodeBlockVector
    blocks::Vector{TmpBlock}
    config::ParserConfig
    render::Function
    args::Vector{Symbol}
end

function Template(
        txt::String;
        path::Bool=true,
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
    config = build_config(dir, config_path, config)
    parse_result = parse_template(txt, config)
    render, args = build_renderer(parse_result..., config.autoescape)
    return Template(parse_result..., config, render, args)
end

function (temp::Template)(; init::Dict{Symbol, T} = Dict{Symbol, Any}()) where {T}
    args = []
    for sym in temp.args
        if haskey(init, sym)
            push!(args, init[sym])
        else
            throw(TemplateError("insufficient variable: $(string(sym))"))
        end
    end
    return string(lstrip(temp.render(args...)))
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
        "comment_block_start" => "{#",
        "comment_block_end" => "#}",
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

#=
#     undefined_symbols(expr::Any)
# 
# Traverses the given expression `expr` to find symbols that are used before being defined.
# Returns a set of such undefined symbols.
# 
# The following constructs are handled:
#   - x = rhs (assignment)
#   - x += rhs, x -= rhs, x *= rhs, x /= rhs (compound assignment)
#   - if cond
#       ...
#     [elseif ...]
#     [else ...]
#     end
#   - for i in iter
#       ...
#     end
#   - let x = expr, y = expr, ...
#       ...
#     end
# For other expressions, it just recurses into child expressions. 
# Any actual scoping behavior (introducing new definitions for subsequent expressions) is handled in `_walk`.
=#
function undefined_symbols(expr::Any)
    used, _ = _walk(expr, Set{Symbol}())
    return used
end

#=
#     _walk(expr, defined::Set{Symbol})
# 
# A helper function that returns a tuple `(used::Set{Symbol}, new_defined::Set{Symbol})`.
# 
# - `used` is the set of undefined symbols encountered in `expr`.
# - `new_defined` is the updated set of defined symbols *after* fully processing `expr`.
# 
# `defined` is the set of symbols considered defined before processing this expression.
# 
# We handle only a limited set of constructs (assignment, if, for, let, and compound assignments).
# All other expressions are handled by simply recursing over their subexpressions without modifying `defined`.
=#
function _walk(expr::Any, defined::Set{Symbol})
    # 1) If `expr` is just a Symbol
    if isa(expr, Symbol)
        if expr in defined
            return (Set{Symbol}(), defined)  # No new undefined symbol, no change in defined set
        else
            return (Set([expr]), defined)    # `expr` is undefined, so add it to 'used'
        end

    # 2) If `expr` is an Expr
    elseif isa(expr, Expr)
        # Check the head of the expression
        h = expr.head

        # 2.1) Assignment-like expressions
        if h in (:(=), :+=, :-=, :*=, :/=)
            # For example, `lhs = rhs` or `lhs += rhs`
            lhs, rhs = expr.args

            # (a) Walk the RHS first
            used_rhs, defined_after_rhs = _walk(rhs, defined)

            # (b) Check the LHS
            if isa(lhs, Symbol)
                # LHS is newly defined from now on
                local_defined = union(defined_after_rhs, Set([lhs]))
                # We do not add the LHS to the 'used' set because it’s being defined here
                return (used_rhs, local_defined)
            else
                # LHS might be an Expr, e.g., (x, y) = something
                used_lhs, defined_after_lhs = _walk(lhs, defined_after_rhs)
                # Combine undefined symbols from LHS and RHS
                used_total = union(used_rhs, used_lhs)
                return (used_total, defined_after_lhs)
            end

        # 2.2) If block: multiple statements in a row
        elseif h === :block
            # For example: quote
            #     statement1
            #     statement2
            # end
            used_total = Set{Symbol}()
            local_defined = copy(defined)
            for st in expr.args
                used_st, local_defined = _walk(st, local_defined)
                used_total = union(used_total, used_st)
            end
            return (used_total, local_defined)

        # 2.3) if expression
        elseif h === :if
            # if cond
            #   then_block
            # [elseif ...]
            # [else ...]
            # end
            # The `if` does not introduce a new scope, so each branch inherits the same 'defined'
            used_total = Set{Symbol}()
            local_defined = copy(defined)
            for subexpr in expr.args
                used_sub, local_defined = _walk(subexpr, local_defined)
                used_total = union(used_total, used_sub)
            end
            return (used_total, local_defined)

        # 2.4) for loop
        elseif h === :for
            # for i in iter
            #   body...
            # end
            # Typically e.args[1] = Expr(:in, i, iter)
            # e.args[2..end] = the body
            used_total = Set{Symbol}()
            local_defined = copy(defined)

            if !isempty(expr.args) && isa(expr.args[1], Expr) && expr.args[1].head === :(=)
                i, iter_expr = expr.args[1].args
                # (a) Walk the iteration source
                used_iter, defined_iter = _walk(iter_expr, local_defined)
                used_total = union(used_total, used_iter)

                # (b) If `i` is a symbol, define it within this for-loop scope
                for_defined = copy(defined_iter)
                if isa(i, Symbol)
                    push!(for_defined, i)
                end

                # (c) Walk the body
                # e.args[2..end] is the block inside the for
                used_body = Set{Symbol}()
                for b in expr.args[2:end]
                    used_b, for_defined = _walk(b, for_defined)
                    used_body = union(used_body, used_b)
                end

                used_total = union(used_total, used_body)
                return (used_total, local_defined)  # `local_defined` might not add `i` outside
            else
                # If this for is in an unexpected form, just traverse everything
                for subexpr in expr.args
                    used_sub, local_defined = _walk(subexpr, local_defined)
                    used_total = union(used_total, used_sub)
                end
                return (used_total, local_defined)
            end

        # 2.5) let expression
        elseif h === :let
            # let x = expr, y = expr, ...
            #   body...
            # end
            # Inside this let block, x, y, etc. are newly defined
            used_total = Set{Symbol}()
            local_defined = copy(defined)

            if expr.args[1].head == :block
                # If there are multiple definition statements, each one is like a normal assignment
                for def_ex in expr.args[1].args
                    push!(local_defined, def_ex.args[1])
                end
            else
                # If there is only one definition statement, it must be like a normal assignment
                def_ex = expr.args[1]
                push!(local_defined, def_ex.args[1])
            end

            # Walk the let used_body
            used_body, _ = _walk(expr.args[2], local_defined)

            used_total = union(used_total, used_body)
            return (used_total, defined)

        # 2.6) Function call
        elseif h === :call
            used_total = Set{Symbol}()
            local_defined = copy(defined)
            # ignore the symbol representing the function
            for (i, subexpr) in enumerate(expr.args)
                if i > 1
                    used_sub, local_defined = _walk(subexpr, local_defined)
                    used_total = union(used_total, used_sub)
                end
            end
            return (used_total, local_defined)

        # 2.7) Other expression types (function calls, etc.)
        else
            # No new scope. Just traverse subexpressions.
            used_total = Set{Symbol}()
            local_defined = copy(defined)
            for subexpr in expr.args
                used_sub, local_defined = _walk(subexpr, local_defined)
                used_total = union(used_total, used_sub)
            end
            return (used_total, local_defined)
        end

    else
        # 3) If `expr` is a literal (integer, string, float, bool, etc.)
        return (Set{Symbol}(), defined)
    end
end


build_renderer(_::Nothing, elements::CodeBlockVector, _::Vector{TmpBlock}, autoescape::Bool) = build_renderer(elements, autoescape)
function build_renderer(super::ExtendTemplate, _::CodeBlockVector, blocks::Vector{TmpBlock}, autoescape::Bool)
    blocks = inherite_blocks(blocks, super.blocks)
    if super.super !== nothing
        return build_renderer(super.super, super.elements, blocks, autoescape)
    end
    elements = apply_inheritance(super.elements, blocks)
    build_renderer(elements, autoescape)
end

function build_renderer(elements::CodeBlockVector, autoescape::Bool)
    render = quote
        txt = ""
    end
    for e in elements
        if typeof(e) <: AbstractString
            push!(render.args, :(txt *= $e))
        elseif isa(e, TmpCodeBlock)
            push!(render.args, e(autoescape))
        elseif isa(e, TmpBlock)
            push!(render.args, e(autoescape))
        elseif isa(e, VariableBlock)
            if occursin("|>", e.exp)
                exp = map(strip, split(e.exp, "|>"))
                f = filters_alias[exp[2]]
                if autoescape && f != htmlesc
                    push!(render.args, :(txt *= htmlesc(string($f($(Symbol(exp[1])))))))
                else
                    push!(render.args, :(txt *= string($f($(Symbol(exp[1]))))))
                end
            else
                if autoescape
                    push!(render.args, :(txt *= htmlesc(string($(Symbol(e.exp))))))
                else
                    push!(render.args, :(txt *= string($(Symbol(e.exp)))))
                end
            end
        elseif isa(e, SuperBlock)
            throw(TemplateError("invalid super block is found"))
        end
    end
    push!(render.args, :(txt))
    vars = collect(undefined_symbols(render))
    return eval(Expr(:->, 
        Expr(:tuple, vars...),
    render)), vars
end
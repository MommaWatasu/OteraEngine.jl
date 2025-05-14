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
    
    rendered = Base.invokelatest(temp.render, args...)
    return string(lstrip(rendered))
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
        if expr in (:nothing, :true, :false, :Int, :String, :Any, :Symbol, :Expr, :Main)
             return (Set{Symbol}(), defined)
        end
        if expr in defined
            return (Set{Symbol}(), defined)
        else
            return (Set([expr]), defined)
        end

    # 2) If `expr` is an Expr
    elseif isa(expr, Expr)
        used_total = Set{Symbol}()
        h = expr.head

        # 2.1a) Simple Assignment expressions: var = value
        if h === :(=)
            lhs, rhs = expr.args
            used_rhs, defined_after_rhs = _walk(rhs, defined) # Process RHS first
            used_total = union(used_total, used_rhs)

            if isa(lhs, Symbol)
                # LHS symbol is now defined.
                local_defined = union(defined_after_rhs, Set([lhs]))
                return (used_total, local_defined)
            elseif isa(lhs, Expr) && lhs.head === :tuple # Destructuring assignment: (a,b) = ...
                local_defined = copy(defined_after_rhs)
                # LHS tuple elements are being defined.
                for var_in_tuple in lhs.args
                    if isa(var_in_tuple, Symbol)
                        push!(local_defined, var_in_tuple)
                    else
                        # If tuple elements are complex, they might use/define other vars,
                        # but for (a,b)=... this is not typical. For simplicity, assume symbols.
                        # used_elem, local_defined = _walk(var_in_tuple, local_defined)
                        # used_total = union(used_total, used_elem)
                    end
                end
                return (used_total, local_defined)
            else # Complex LHS like A[i] = x or obj.field = x
                 # These LHS expressions (A, i, obj) are "used".
                 # The assignment doesn't create new variables in the current scope like `var = ...` does.
                used_lhs_expr, _ = _walk(lhs, defined_after_rhs) # Walk LHS in scope after RHS
                used_total = union(used_total, used_lhs_expr)
                # `defined` set for outer scope doesn't change due to new vars from this type of LHS
                return (used_total, defined_after_rhs)
            end
        # 2.1b) Compound assignment (e.g., a += b)
        elseif h in (:+=, :-=, :*=, :/=)
            lhs, rhs = expr.args
            # LHS is read, then RHS is read, then LHS is written.
            # Both LHS (as an expression) and RHS use variables from the original `defined` scope.
            used_from_lhs, _ = _walk(lhs, defined)
            used_from_rhs, _ = _walk(rhs, defined)
            used_total = union(used_from_lhs, used_from_rhs)
            # Compound assignment modifies an existing variable; it does not change the set of defined variable names for the outer scope.
            return (used_total, defined)

        # 2.2) Block: multiple statements in a row
        elseif h === :block
            local_defined = copy(defined)
            for st in expr.args
                st === nothing && continue
                isa(st, LineNumberNode) && continue
                used_st, local_defined = _walk(st, local_defined) # Definitions propagate
                used_total = union(used_total, used_st)
            end
            return (used_total, local_defined)

        # 2.3) if expression
        elseif h === :if
            # used_total is already initialized
            cond_expr = expr.args[1]
            then_expr = expr.args[2]

            used_cond, defined_after_cond = _walk(cond_expr, defined)
            used_total = union(used_total, used_cond)
            
            # Walk then-branch with scope after condition.
            # Definitions within then_expr are local to it and don't affect scope after 'if'.
            used_then, _ = _walk(then_expr, defined_after_cond) 
            used_total = union(used_total, used_then)
            
            if length(expr.args) == 3 # Else-branch exists
                else_expr = expr.args[3]
                # Walk else-branch with scope after condition.
                used_else, _ = _walk(else_expr, defined_after_cond)
                used_total = union(used_total, used_else)
            end
            # The 'defined' set for expressions *after* the 'if' statement is the set that was
            # defined *after the condition was processed*.
            return (used_total, defined_after_cond)

        # 2.4) for loop
        elseif h === :for
            local_defined_outer = defined
            if !isempty(expr.args) && isa(expr.args[1], Expr) && expr.args[1].head === :(=)
                assignment_expr = expr.args[1] 
                loop_vars_expr = assignment_expr.args[1] 
                iter_expr = assignment_expr.args[2]

                used_iter, _ = _walk(iter_expr, local_defined_outer)
                used_total = union(used_total, used_iter)

                defined_for_body = copy(local_defined_outer)
                if isa(loop_vars_expr, Symbol)
                    push!(defined_for_body, loop_vars_expr)
                elseif isa(loop_vars_expr, Expr) && loop_vars_expr.head === :tuple 
                    for var_in_tuple in loop_vars_expr.args
                        if isa(var_in_tuple, Symbol)
                            push!(defined_for_body, var_in_tuple)
                        end
                    end
                end
                
                used_body, _ = _walk(expr.args[2], defined_for_body) 
                used_total = union(used_total, used_body)
                return (used_total, local_defined_outer)
            else
                for arg in expr.args # Fallback
                    (isa(arg, LineNumberNode) || arg === nothing) && continue
                    used_arg, _ = _walk(arg, defined)
                    used_total = union(used_total, used_arg)
                end
                return (used_total, defined)
            end

        # 2.5) let expression
        elseif h === :let
            # used_total is already initialized
            defined_for_all_rhs_analysis = defined 
            defined_for_body_walk = copy(defined)

            body_arg = expr.args[end]
            binding_args = expr.args[1:end-1]
            
            lhs_vars_in_let = Symbol[]

            for binding_expr_arg in binding_args
                current_binding_lhs_vars_for_this_arg = Symbol[]
                assignments_to_process_for_this_arg = []

                if isa(binding_expr_arg, Expr) && binding_expr_arg.head === :(=)
                    push!(assignments_to_process_for_this_arg, binding_expr_arg)
                elseif isa(binding_expr_arg, Symbol) # `let x; ...` (x is defined as nothing implicitly)
                    _walk(:(nothing), defined_for_all_rhs_analysis) # RHS is effectively `nothing`
                    push!(current_binding_lhs_vars_for_this_arg, binding_expr_arg)
                elseif isa(binding_expr_arg, Expr) && binding_expr_arg.head === :block
                    for item_in_block in binding_expr_arg.args
                        item_in_block === nothing && continue
                        isa(item_in_block, LineNumberNode) && continue
                        if isa(item_in_block, Expr) && item_in_block.head === :(=)
                            push!(assignments_to_process_for_this_arg, item_in_block)
                        elseif isa(item_in_block, Symbol)
                            _walk(:(nothing), defined_for_all_rhs_analysis)
                            push!(current_binding_lhs_vars_for_this_arg, item_in_block)
                        end
                    end
                end

                for assign_expr in assignments_to_process_for_this_arg
                    single_lhs = assign_expr.args[1]
                    single_rhs = assign_expr.args[2]
                    used_rhs, _ = _walk(single_rhs, defined_for_all_rhs_analysis)
                    used_total = union(used_total, used_rhs)
                    if isa(single_lhs, Symbol)
                        push!(current_binding_lhs_vars_for_this_arg, single_lhs)
                    elseif isa(single_lhs, Expr) && single_lhs.head === :tuple
                        for sym_in_tuple in single_lhs.args
                            if isa(sym_in_tuple, Symbol)
                                push!(current_binding_lhs_vars_for_this_arg, sym_in_tuple)
                            end
                        end
                    end
                end
                append!(lhs_vars_in_let, current_binding_lhs_vars_for_this_arg)
            end
            
            for lhs_var in lhs_vars_in_let
                push!(defined_for_body_walk, lhs_var)
            end
            
            used_from_body, _ = _walk(body_arg, defined_for_body_walk)
            used_total = union(used_total, used_from_body)
            
            return (used_total, defined) # Definitions in `let` do not escape.

        # 2.6) Function call
        elseif h === :call
            func_expr = expr.args[1]
            known_safe_funcs = (:string, :htmlesc, :escape_string, :+, :-, :*, :/, :<, :>, :(==), :!=, :<=, :>=, :length, :get, :print, :println, :typeof, :isa, :in, :iterate, :zip, :enumerate, :Pair, :Dict, :Set, :Vector, :tuple, :repr, :Symbol, :Expr, :error, :throw, :identity, :first, :last, :getindex, :setindex!, :keys, :values, :haskey, :sort, :sort!, :unique, :unique!, :filter, :filter!, :map, :map!, :reduce, :sum, :prod, :any, :all, :count, :startswith, :endswith, :join, :split, :replace, :strip, :lstrip, :rstrip, :uppercase, :lowercase, :titlecase, :rand, :randn, :abs, :sqrt, :log, :log10, :exp, :sin, :cos, :tan)

            if !isa(func_expr, Symbol) || # It's an expression like (get_func())()
               (!(func_expr in defined) && 
                !isdefined(Main, func_expr) && 
                !(func_expr in known_safe_funcs))
                used_func, _ = _walk(func_expr, defined)
                used_total = union(used_total, used_func)
            end

            for i in 2:length(expr.args) 
                used_arg, _ = _walk(expr.args[i], defined)
                used_total = union(used_total, used_arg)
            end
            return (used_total, defined)

        # 2.7) Dot operator for field/module access
        elseif h === :. && length(expr.args) == 2 && isa(expr.args[2], QuoteNode)
            used_obj_or_mod, _ = _walk(expr.args[1], defined)
            used_total = union(used_total, used_obj_or_mod)
            return (used_total, defined)

        # 2.8) Indexing
        elseif h === :ref 
            for arg in expr.args
                used_arg, _ = _walk(arg, defined)
                used_total = union(used_total, used_arg)
            end
            return (used_total, defined)
        
        # 2.9) Other expression types (generic fallback)
        else
            for arg in expr.args
                if isa(arg, Union{Expr, Symbol})
                    used_arg, _ = _walk(arg, defined)
                    used_total = union(used_total, used_arg)
                end
            end
            return (used_total, defined) 
        end

    # 3) If `expr` is a literal or other non-Symbol, non-Expr types.
    else
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

#=
#     build_renderer(elements::CodeBlockVector, autoescape::Bool)
#
# This function builds a renderer function for the given elements and autoescape setting.
# It constructs a function that takes a variable number of arguments and returns a string.
# The function iterates over the elements and generates code to concatenate strings.
#
# The function handles different types of elements:
#   - AbstractString: Appends the string to the result.
#   - TmpCodeBlock: Calls the block with the autoescape setting.
#   - TmpBlock: Calls the block with the autoescape setting.
#   - VariableBlock: Handles variable expressions, applying filters if necessary.
#   - SuperBlock: Throws an error if encountered.
#
# The function returns a tuple containing the generated renderer function and a set of undefined symbols.
# The undefined symbols are collected during the construction of the renderer function.
# The renderer function is defined using `Expr(:->, ...)` and takes a tuple of arguments.
# The renderer function is constructed using `eval` to create a callable function.
# The filters are defined in the `filters_alias` dictionary, which maps filter names to their corresponding functions.
=#
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
                exp_parts = map(strip, split(e.exp, "|>"))
                var_expr_str = exp_parts[1]
                filter_name_str = exp_parts[2]
                
                f = filters_alias[filter_name_str]
                # MODIFIED: Use Meta.parse for the variable part of the expression
                parsed_var_expr = Meta.parse(var_expr_str)
                if autoescape && f != htmlesc
                    push!(render.args, :(txt *= htmlesc(string($f($parsed_var_expr)))))
                else
                    push!(render.args, :(txt *= string($f($parsed_var_expr))))
                end
            else
                # MODIFIED: Use Meta.parse for the expression
                parsed_expr = Meta.parse(e.exp)
                if autoescape
                    push!(render.args, :(txt *= htmlesc(string($parsed_expr))))
                else
                    push!(render.args, :(txt *= string($parsed_expr)))
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
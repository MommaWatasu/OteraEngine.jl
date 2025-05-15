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
        # Ignore common built-in types/values that might appear as symbols in ASTs
        # but are not variables we'd pass from `init`.
        # This list might need refinement based on OteraEngine's AST generation.
        if expr in (:nothing, :true, :false, :Int, :String, :Any, :Symbol, :Expr)
             return (Set{Symbol}(), defined)
        end
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

            # For compound assignments like += or -=, the LHS is also read before being written
            # So we need to track LHS as potentially undefined in these cases
            is_compound = h in (:+=, :-=, :*=, :/=)
            
            # Get undefined symbols from RHS
            used_rhs, defined_after_rhs = _walk(rhs, defined)

            # (b) Check the LHS
            if isa(lhs, Symbol)
                if is_compound && !(lhs in defined)
                    # For compound assignments, if LHS is not defined, add it to used set
                    used_total = union(used_rhs, Set([lhs]))
                else
                    used_total = used_rhs
                end
                # LHS is newly defined from now on
                local_defined = union(defined_after_rhs, Set([lhs]))
                return (used_total, local_defined)
            elseif isa(lhs, Expr) && lhs.head === :tuple # Destructuring assignment: (a,b) = ...
                # In destructuring assignment, only the RHS has potentially undefined symbols
                # The LHS tuple elements are being defined, not used
                used_total = used_rhs
                
                # Now define all symbols in the tuple
                local_defined = copy(defined_after_rhs) 
                for var_in_tuple in lhs.args
                    if isa(var_in_tuple, Symbol)
                        push!(local_defined, var_in_tuple)
                    elseif isa(var_in_tuple, Expr)
                        # Handle nested expressions in tuple, but only gather symbols
                        for arg in var_in_tuple.args
                            if isa(arg, Symbol)
                                push!(local_defined, arg)
                            end
                        end
                    end
                end
                return (used_total, local_defined)
            else
                # Other complex LHS, e.g., array indexing A[i] = ...
                # The LHS itself might contain used variables (like A and i)
                used_lhs_expr, defined_after_lhs_expr = _walk(lhs, defined_after_rhs)
                used_total = union(used_rhs, used_lhs_expr)
                # For A[i]=v, A and i are used, not defined in the `defined_after_lhs_expr` sense for new scope.
                # `defined_after_lhs_expr` would be same as `defined_after_rhs` unless LHS walk changes it.
                return (used_total, defined_after_rhs) # LHS of A[i]=v doesn't create new scope vars like plain `a=v`
            end

        # 2.2) If block: multiple statements in a row
        elseif h === :block
            used_total = Set{Symbol}()
            local_defined = copy(defined)
            for st in expr.args
                # Skip `nothing` which can appear in blocks (e.g., from Meta.parse(";;"))
                st === nothing && continue 
                used_st, local_defined = _walk(st, local_defined)
                used_total = union(used_total, used_st)
            end
            return (used_total, local_defined)

        # 2.3) if expression
        elseif h === :if
            used_total = Set{Symbol}()
            # `if` conditions and branches don't create a new scope that persists *after* the if.
            # Variables defined inside `if` are local to their branch.
            # All parts of the `if` expression are evaluated in the `defined` scope.
            # We need to collect `used` from all branches and the condition.
            # The `new_defined` returned should be the original `defined` set.
            
            # Condition
            used_cond, _ = _walk(expr.args[1], defined)
            used_total = union(used_total, used_cond)
            
            # Then-branch
            used_then, _ = _walk(expr.args[2], defined) # Vars defined in `then` don't escape
            used_total = union(used_total, used_then)
            
            # Else-branch (if present)
            if length(expr.args) == 3
                used_else, _ = _walk(expr.args[3], defined) # Vars defined in `else` don't escape
                used_total = union(used_total, used_else)
            end
            return (used_total, defined) # `defined` set is unchanged by the if block itself for outer scope

        # 2.4) for loop
        elseif h === :for
            used_total = Set{Symbol}()
            # `local_defined_outer` is the scope before the for loop.
            local_defined_outer = defined

            if !isempty(expr.args) && isa(expr.args[1], Expr) && expr.args[1].head === :(=)
                assignment_expr = expr.args[1] # e.g., Expr(:(=), :i, :iterable) or Expr(:(=), (:i,:j), :iterable)
                loop_vars_expr = assignment_expr.args[1] 
                iter_expr = assignment_expr.args[2]

                used_iter, _ = _walk(iter_expr, local_defined_outer) # Iterable is in outer scope
                used_total = union(used_total, used_iter)

                # Scope for the loop body: outer scope + loop variable(s)
                defined_for_body = copy(local_defined_outer)
                if isa(loop_vars_expr, Symbol)
                    push!(defined_for_body, loop_vars_expr)
                elseif isa(loop_vars_expr, Expr) && loop_vars_expr.head === :tuple 
                    for loop_var in loop_vars_expr.args
                        if isa(loop_var, Symbol)
                            push!(defined_for_body, loop_var)
                        end
                    end
                end
                
                # Walk the body (expr.args[2] is the block)
                used_body, _ = _walk(expr.args[2], defined_for_body) 
                
                # Special handling for function calls in the body
                # Scan for any direct function calls and add them to used set
                if isa(expr.args[2], Expr) && expr.args[2].head === :block
                    for stmt in expr.args[2].args
                        if isa(stmt, Expr) && stmt.head === :call
                            if isa(stmt.args[1], Symbol) && 
                              !(stmt.args[1] in defined_for_body) && 
                              !(stmt.args[1] in (:string, :htmlesc, :uppercase, :lowercase, :+, :-, :*, :/, :<, :>, :(==)))
                                push!(used_total, stmt.args[1])
                            end
                        end
                    end
                end
                
                used_total = union(used_total, used_body)
                
                return (used_total, local_defined_outer)  # Loop variables don't escape the for loop
            else
                # Fallback for other `for` forms or if AST is unexpected
                for subexpr in expr.args
                    used_sub, _ = _walk(subexpr, local_defined_outer)
                    used_total = union(used_total, used_sub)
                end
                return (used_total, local_defined_outer)
            end

        # 2.5) let expression (MODIFIED for strict parallel RHS analysis)
        elseif h === :let
            used_total = Set{Symbol}()
            
            # This scope is for evaluating ALL RHS expressions in the let block.
            # It is the scope *before* any variables from this let block are defined.
            defined_for_all_rhs_analysis = defined 

            # This scope is for evaluating the BODY of the let block.
            # It starts as the outer scope, then gets augmented with the LHS variables from this let block.
            defined_for_body_walk = copy(defined)

            assignments_arg = expr.args[1] # This is Expr(:(=), var, val) or Expr(:block, assign1, assign2)
            body_arg = expr.args[2]

            lhs_vars_in_let = Symbol[] # To store LHS symbols defined in this let

            if isa(assignments_arg, Expr) && assignments_arg.head === :block
                # Multiple assignments: e.g., let a=x, b=y; body end
                for assign_expr in assignments_arg.args
                    if assign_expr === nothing # Skip if it's just `nothing` from parsing like `let ; body end`
                        continue
                    end
                    if isa(assign_expr, Expr) && assign_expr.head === :(=)
                        lhs = assign_expr.args[1]
                        rhs = assign_expr.args[2]
                        
                        # Analyze RHS using the scope *before* this let block's own definitions
                        used_from_rhs, _ = _walk(rhs, defined_for_all_rhs_analysis)
                        used_total = union(used_total, used_from_rhs)
                        
                        if isa(lhs, Symbol)
                            push!(lhs_vars_in_let, lhs)
                        # Handle tuple destructuring on LHS if OteraEngine supports `let (a,b) = ...`
                        elseif isa(lhs, Expr) && lhs.head === :tuple
                            for var_in_tuple in lhs.args
                                if isa(var_in_tuple, Symbol)
                                    push!(lhs_vars_in_let, var_in_tuple)
                                end
                            end
                        end
                    else
                        # If not an assignment, it might be a stray expression. Walk it in outer scope.
                        used_stray, _ = _walk(assign_expr, defined_for_all_rhs_analysis)
                        used_total = union(used_total, used_stray)
                    end
                end
            elseif isa(assignments_arg, Expr) && assignments_arg.head === :(=)
                # Single assignment: e.g., let a=x; body end
                lhs = assignments_arg.args[1]
                rhs = assignments_arg.args[2]

                # Analyze RHS using the scope *before* this let block's own definitions
                used_from_rhs, _ = _walk(rhs, defined_for_all_rhs_analysis)
                used_total = union(used_total, used_from_rhs)

                if isa(lhs, Symbol)
                    push!(lhs_vars_in_let, lhs)
                # Handle tuple destructuring on LHS
                elseif isa(lhs, Expr) && lhs.head === :tuple
                    for var_in_tuple in lhs.args
                        if isa(var_in_tuple, Symbol)
                            push!(lhs_vars_in_let, var_in_tuple)
                        end
                    end
                end
            elseif assignments_arg !== nothing # If assignments_arg is not an Expr, but also not nothing (e.g. a Symbol)
                # This case means `let some_symbol; body; end`, which is unusual for variable binding.
                # Treat `some_symbol` as if it's part of the body, walked with outer scope.
                # Or, if it's meant to be `let some_symbol=true; body; end` this needs parser change.
                # For now, assume it's an expression to be walked.
                used_stray, _ = _walk(assignments_arg, defined_for_all_rhs_analysis)
                used_total = union(used_total, used_stray)
            end

            # Add all collected LHS variables to the scope for the body
            for lhs_var in lhs_vars_in_let
                push!(defined_for_body_walk, lhs_var)
            end
            
            # Walk the body of the let block
            used_from_body, _ = _walk(body_arg, defined_for_body_walk)
            used_total = union(used_total, used_from_body)
            
            # Definitions in `let` do not escape to the `new_defined` set for the outer scope.
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
        
        #=
        elseif h === :call
            used_total = Set{Symbol}()

            # expr.args[1] is the function being called.
            # If it's a Symbol (e.g., :my_func), it could be an undefined variable or a known function.
            # If it's an Expr (e.g., (get_func()).()), walk it.
            if !isa(expr.args[1], Symbol) 
                 used_func_expr, _ = _walk(expr.args[1], defined)
                 used_total = union(used_total, used_func_expr)
            elseif !(expr.args[1] in defined) && !(isdefined(Main, expr.args[1]) || expr.args[1] in (:string, :htmlesc, :uppercase, :lowercase, :+, :-, :*, :/, :<, :>, :(==))) # Check if it's a known global/builtin
                # If it's a symbol, not defined locally, and not a common global/operator, it might be a user variable used as function.
                # This is heuristic. A more robust way would be to have a list of known "safe" functions.
                # For now, if it's a symbol like `my_custom_func_var` and not defined, treat it as used.
                # This part is tricky; Otera's filters are handled differently.
                # Let's assume function names that are symbols are generally not what we are tracking as `init` vars.
                # The original logic `!isa(expr.args[1], Symbol)` was safer.
                # Reverting to: if it's a symbol, we assume it's a function name and don't add to `used_total` here.
                # If it's an expression, it might contain variables.
                # No, the original `!isa(expr.args[1], Symbol)` means if it *is* a symbol, it's skipped.
                # If it's an Expr like `(obj.method)(args)`, then `obj.method` is walked.
                # This is correct.
        =#

        # 2.7) Other expression types
        else
            used_total = Set{Symbol}()
            
            if h === :. && length(expr.args) == 2 && isa(expr.args[1], Symbol) && isa(expr.args[2], QuoteNode)
                # Specifically for variable.field like job.id -> Expr(:., :job, QuoteNode(:id))
                # We only care if :job (expr.args[1]) is defined. QuoteNode is not a variable.
                used_base, _ = _walk(expr.args[1], defined)
                used_total = union(used_total, used_base)
                return (used_total, defined)
            elseif h === :ref && length(expr.args) >= 2 # For array[index] or dict[key]
                # First arg is the collection (e.g., :my_array), others are indices/keys.
                # Walk the collection
                used_collection, _ = _walk(expr.args[1], defined)
                used_total = union(used_total, used_collection)
                # Walk indices/keys
                for i in 2:length(expr.args)
                    used_idx, _ = _walk(expr.args[i], defined)
                    used_total = union(used_total, used_idx)
                end
                return (used_total, defined)
            else
                # Generic traversal for other Expr types if not specifically handled
                # Each subexpression is evaluated in the same `defined` scope.
                for subexpr in expr.args
                    if subexpr === nothing continue end # Skip `nothing`
                    used_sub, _ = _walk(subexpr, defined) # `defined` set does not change for siblings
                    used_total = union(used_total, used_sub)
                end
                return (used_total, defined) 
            end
        end

    # 3) If `expr` is a literal (integer, string, float, bool, QuoteNode etc.)
    #    or other non-Symbol, non-Expr types.
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
struct SafeString
    str::String
end

function htmlesc(str::String)
    return Markdown.htmlesc(str)
end

function htmlesc(str::SafeString)
    return str.str
end

function safe(str::String)
    return SafeString(str)
end

function safe(str::SafeString)
    return str
end

function Base.string(str::SafeString)
    return str
end

filters_alias = Dict(
    "e" => :htmlesc,
    "escape" => :htmlesc,
    "upper" => :uppercase,
    "lower" => :lowercase,
    "safe" => :safe,
)

"""
    @filter func
    @filter alias func
This macro registers `func` into OteraEngine, then the function is availble as a filter.
The form of `func` should be normal or one-line definition but not anonymous.
And you can also define filter with alias.

# Example
```julia-repr
julia> @filter function greet(x)
            return x * "Hello"
        end
julia> @filter hello function greet(x)
            return x * "Hello"
        end
julia> @filter say_twice(x) = x*x
julia> @filter double say_twice(x) = x*x
```
After define filters like this, you can use them as `greet`, `hello`, `say_twice`, `double`.
"""
macro filter(func::Expr)
    name = :none
    if func.head == :function
        name = func.args[1].args[1]
    elseif func.head == :(=) && func.args[1].head == :call
        name = func.args[1].args[1]
    else
        error("Invalid Filter: failed to get the name of the filter")
    end
    return quote
        Core.eval(OteraEngine, Meta.parse($(string(func))))
        OteraEngine.filters_alias[$(string(name))] = Symbol($(string(name)))
        $func
    end
end

macro filter(alias::Symbol, func::Expr)
    name = :none
    if func.head == :function
        name = func.args[1].args[1]
    elseif func.head == :(=) && func.args[1].head == :call
        name = func.args[1].args[1]
    else
        error("Invalid Filter: failed to get the name of the filter")
    end
    return quote
        Core.eval(OteraEngine, Meta.parse($(string(func))))
        OteraEngine.filters_alias[$(string(alias))] = Symbol($(string(name)))
        $func
    end
end
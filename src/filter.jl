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

filters = Expr[:(e=htmlesc), :(escape=htmlesc), :(upper=uppercase), :(lower=lowercase), :(safe=safe)]

"""
    @filter func
This macro registers `func` into OteraEngine, then you can use it as a filter(of course you have to pass it to filters argument of Template function).
The form of `func` should be normal or one-line definition but not lambda.

# Example
```julia-repr
julia> @filter function greet(x)
            return x * "Hello"
        end
julia> @filter say_twice(x) = x*x
```
"""
macro filter(func::Expr)
    name = :none
    if func.head == :function
        name = func.args[1]
    elseif func.head == :(=) && func.args[1].head == :call
        name = func.args[1].args[1]
    else
        error("Invalid Filter: failed to get the name of the filter")
    end
    return quote
        push!(OteraEngine.filters, Meta.parse($(string(func))))
        $func
    end
end
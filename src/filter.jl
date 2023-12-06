filters = Vector{Expr}(undef, 0)

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
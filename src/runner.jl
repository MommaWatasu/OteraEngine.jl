struct RunnerError <: Exception
    msg::String
end

Base.showerror(io::IO, e::ParserError) = print(io, "ParserError: "*e.msg)

struct Runner
    txt::String
    top_codes::Array{String, 1}
    jl_codes::Array{String, 1}
    tmp_codes::Array{TmpCodeBlock, 1}
end

function (R::Runner)(tmp_init::Dict{String, Any}, jl_init::Dict{String, ANy})
    tmp_args = ""
    for v in keys(tmp_init)
        tmp_args*=(v*",")
    end
    
    jl_args = ""
    for v in keys(jl_init)
        jl_args*=(v*",")
    end
    
    out_txt = R.txt
    tmp_def = "function tmp_func("*tmp_args*");txts=Array{String}(undef, $(length(R.tmp_codes)));"
    for (i, tmp_code) in enumerate(R.tmp_codes)
        tmp_def*=tmp_code(i)
    end
    tmp_def*="end"
    eval(tmp_def)
    txts = tmp_func(values(tmp_init)...)
    for (i, txt) in enumerate(txts)
        replace(out_txt, "<tmpcode$i>"=>txt)
    end
    
    for top_code in R.top_codes
        eval(Meta.parse(top_code))
    end
    
    for (i, jl_code) in enumerate(R.jl_codes)
        eval(Meta.parse("function f("*jl_args*");"*jl_code*"end"))
        out_txt = replace(out_txt, "<jl_code$i>"=>string(Base.invokelatest(f, values(jl_init)...)))
    end
    return out_txt
end

function assign_variables(txt, tmp_init::Dict{String, Any})
    for m in eachmatch(r"{{[\\s\\S]*?}}")
    end
end
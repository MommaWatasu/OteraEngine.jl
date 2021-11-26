module OteraEngine

using TOML

export Template

function parse_config(filename::String)
    if filename[end-3:end] != "toml"
        throw(ArgumentError("Suffix of config file must be `toml`! Now, it is `$(filename[end-3:end])`."))
    end
    config = ""
    open(filename, "r") do f
        config = read(f, String)
    end
    return TOML.parse(config)
end

"""
    Template(html::String; path::Bool=true, config_path::String="",
        config::Dict{String, T} = Dict(
            "code_block_start"=>"```",
            "code_block_stop"=>"```"
        )
    )
This is the only structure and function of this package.
This structure has 2 parameter,
- `html` is the path to the HTML file or HTML of String type.
- `path` determines whether the parameter `html` represents the file path. The default value is `true`.
- `config_path` is path to config file. The suffix of config file must be `toml`.
- `config` is configuration of Template. It is type of `Dict`, and now there are two settings bellow.
    - `code_block_start` : The string at the start of code blocks.
    - `code_block_stop` : The string at the end of code blocks.

# Config File
A config file must be written in TOML format. like this:
```
code_block_start = "{{"
code_block_stop = "}}"
```
The item is the same as the argiment `config`.

# HTML
You can write the code of Template in JuliaLang, and just write the variables you want to output to a HTML at the end of the code.
The code needs to be enclosed by ```(This can be changed by `config` variable).

For exmaple, this HTML work:
```
<html>
    <head><title>OteraEngine Test</title></head>
    <body>
        Hello, ```usr```!
    </body>
</html>
```

# Rendering
After you create a Template, you just have to execute the codes! For this, you use the Function-like Object of Template structure.`tmp(; init::Dict{String, T}) where T <: Any` variables are initialized by `init`(`init` is the parameter for Function-like Object). `init` must be `Dict`type. If you don't pass the `init`, the initialization won't be done.
Please see the example below.

# Example
```@repl
tmp = Template("./test1.html") #The last HTML code
init = Dict("usr"=>"OteraEngine")
result = tmp(init)
println(result)
```
"""
struct Template
    splitted_html::Array{String, 1}
    codes::Array{String, 1}
end

function Template(html::String; path::Bool=true, config_path::String="",
        config::Dict{String, T} = Dict(
            "code_block_start"=>"```",
            "code_block_stop"=>"```"
        )
    ) where T<:Any
    if path
        open(html, "r") do f
            html = read(f, String)
        end
    end
    if config_path!=""
        conf_file = parse_config(config_path)
        for v in keys(conf_file)
            config[v] = conf_file[v]
        end
    end
    code = ""
    codes = Array{String}(undef, 0)
    splitted_html = Array{String}(undef, 0)
    i = 1
    code_block_start, code_block_stop = config["code_block_start"], config["code_block_stop"]
    start_len, stop_len = length(code_block_start), length(code_block_stop)
    regex = Regex(code_block_start*"[\\s\\S]*?"*code_block_stop)
    codes_indices = findall(regex, html)
    for index in codes_indices
        s, e = index.start, index.stop
        push!(codes, replace(html[s+start_len:e-stop_len], "\n"=>"; ")) #Does it work without replace?
        push!(splitted_html, html[i:s-1])
        i = e+1
    end
    push!(splitted_html, html[i:end])
    return Template(splitted_html, codes)
end

function (tmp::Template)(init::Dict{String, T}) where T <: Any
    html = tmp.splitted_html[1]
    arg_string = ""
    for v in keys(init)
        arg_string*=(v*",")
    end
    for (part_of_html, code) in zip(tmp.splitted_html[2:end], tmp.codes)
        eval(Meta.parse("function f("*arg_string*"); "*code*";end"))
        html*=string(Base.invokelatest(f, values(init)...))*part_of_html
    end
    return html
end

function (tmp::Template)()
    html = tmp.splitted_html[1]
    for (part_of_html, code) in zip(tmp.splitted_html[2:end], tmp.codes)
        eval(Meta.parse("function f();"*code*";end"))
        html*=string(Base.invokelatest(f))*part_of_html
    end
    return html
end

end

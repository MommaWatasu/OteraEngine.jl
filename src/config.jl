struct ConfigError <: Exception
    msg::String
end

Base.showerror(io::IO, e::ConfigError) = print(io, "ConfigError: "*e.msg)

struct ParserConfig
    control_block::Tuple{String, String}
    expression_block::Tuple{String, String}
    comment_block::Tuple{String, String}
    newline::String
    autospace::Bool
    lstrip_blocks::Bool
    trim_blocks::Bool
    autoescape::Bool
    dir::String
    function ParserConfig(config::Dict{String, Union{String, Bool}})
        if config["autospace"] == true
            if !config["lstrip_blocks"]
                @warn "lstrip_blocks is ignored since autospace is enabled"
                config["lstrip_blocks"] = true
            end
            if !config["trim_blocks"]
                @warn "trim_blocks is ignored since autospace is enabled"
                config["trim_blocks"] = true
            end
        end
            if (
                config["control_block_start"] == config["control_block_end"]
                || config["expression_block_start"] == config["expression_block_end"]
                || config["comment_block_start"] == config["comment_block_end"]
            )
                throw(ConfigError("invalid configuration: start token and end token must be different"))
            end
        return new(
            (config["control_block_start"], config["control_block_end"]),
            (config["expression_block_start"], config["expression_block_end"]),
            (config["comment_block_start"], config["comment_block_end"]),
            config["newline"],
            config["autospace"],
            config["lstrip_blocks"],
            config["trim_blocks"],
            config["autoescape"],
            config["dir"]
        )
    end
end

config2dict(config::ParserConfig) = Dict{String, Union{String, Bool}}(
    "control_block_start" => config.control_block[1],
    "control_block_end" => config.control_block[2],
    "expression_block_start" => config.expression_block[1],
    "expression_block_end" => config.expression_block[2],
    "comment_block_start" => config.comment_block[1],
    "comment_block_end" => config.comment_block[2],
    "newline" => config.newline,
    "autospace" => config.autospace,
    "lstrip_blocks" => config.lstrip_blocks,
    "trim_blocks" => config.trim_blocks,
    "autoescape" => config.autoescape,
    "dir" => config.dir
)

# configuration(TOML format) parser
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
module OteraEngine

using TOML
import Markdown: htmlesc

export Template

include("config.jl")
include("block.jl")
include("macro.jl")
include("parser.jl")
include("template.jl")

end

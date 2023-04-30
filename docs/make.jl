include("../src/OteraEngine.jl")
using .OteraEngine
using Documenter

makedocs(;
    modules=[OteraEngine],
    authors="MommaWatasu <ascendwatson@gmail.com> and contributors",
    sitename="OteraEngine.jl",
    pages=[
        "Home" => "index.md",
        "Tutorial" => "tutorial.md"
    ],
)

deploydocs(
    repo = "github.com/MommaWatasu/OteraEngine.jl.git",
)

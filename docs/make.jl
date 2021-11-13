include("../src/OteraEngine.jl")
using .OteraEngine
using Documenter

makedocs(;
    modules=[OteraEngine],
    authors="QGMW22 <ascendwatson@gmail.com> and contributors",
    sitename="OteraEngine.jl",
    pages=[
        "Home" => "index.md",
        "Tutorial" => "tutorial.md"
    ],
)
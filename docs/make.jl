include("../src/Jinja.jl")
using .Jinja
using Documenter

makedocs(;
    modules=[Jinja],
    authors="QGMW22 <ascendwatson@gmail.com> and contributors",
    sitename="Jinja.jl",
    pages=[
        "Home" => "index.md",
        "Tutorial" => "tutorial.md"
    ],
)
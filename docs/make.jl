include("../src/Jinja.jl")
using .Jinja
using Documenter

DocMeta.setdocmeta!(Jinja, :DocTestSetup, :(using DocsPackage); recursive=true)

makedocs(;
    modules=[Jinja],
    authors="QGMW22 <ascendwatson@gmail.com> and contributors",
    sitename="Jinja.jl",
    pages=[
        "Home" => "index.md",
        "Tutorial" => "tutorial.md"
    ],
)
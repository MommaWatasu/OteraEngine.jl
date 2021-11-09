using Jinja
using Test

@testset "Jinja.jl" begin
    #When initializing variables directly
    @test_nowarn Template("./test1.html")
    tmp = Template("./test1.html")
    result = ""
    open("./test2.html", "r") do f
        result = read(f, String)
    end
    init = Dict("usr"=>"Julia")
    @test result == tmp(init)
    
    #In case of no params
    tmp = Template("./test3.html")
    @test_nowarn tmp()
end

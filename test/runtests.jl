using Jinja
using Test

@testset "Jinja.jl" begin
    @test_nowarn Template("./test1.html")
    tmp = Template("./test1.html")
    result = ""
    open("./test2.html", "r") do f
        result = read(f, String)
    end
    init = quote
        usr="Julia"
    end
    @test result == tmp(init)
end

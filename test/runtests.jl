using OteraEngine
using Test

@testset "OteraEngine.jl" begin
    #When initializing variables directly
    @test_nowarn Template("test1.html")
    tmp = Template("test1.html")
    result = ""
    open("test2.html", "r") do f
        result = read(f, String)
    end
    init = Dict("usr"=>"Julia")
    @test result == tmp(init)
    
    #In case of no params and specified config
    tmp = Template("test3.html", config=Dict("code_block_start"=>"{{", "code_block_stop"=>"}}"))
    regex = r"<strong>[\s\S]*?([0-9]{2})[\s\S]*?</strong>"
    m = match(regex, tmp())
    @test 0 <= m.offset <= 100
    
    #include config file
    @test_throws ArgumentError Template("test3.html", config_path="test.conf")
    tmp = Template("test3.html", config_path="test.toml")
    regex = r"<strong>[\s\S]*?([0-9]{2})[\s\S]*?</strong>"
    m = match(regex, tmp())
    @test 0 <= m.offset <= 100
end

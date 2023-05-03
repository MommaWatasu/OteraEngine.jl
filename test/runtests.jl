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
    @test result == tmp(jl_init=Dict("usr"=>"Julia"))
    
    #In case of no params and specified config
    tmp = Template("test3.html", config=Dict("jl_block_start"=>"{{", "jl_block_stop"=>"}}"))
    regex = r"<strong>\s*(?<value>[0-9]*)\s*?</strong>"
    m = match(regex, tmp())
    @test 0 <= parse(Int, m[:value]) <= 100
    
    #include config file
    @test_throws ArgumentError Template("test3.html", config_path="test.conf")
    tmp = Template("test3.html", config_path="test.toml")
    regex = r"<strong>\s*(?<value>[0-9]*)\s*?</strong>"
    m = match(regex, tmp())
    @test 0 <= parse(Int, m[:value]) <= 100
    
    #check `using` is available
    tmp = Template("test4.html")
    println(tmp())
    @test_nowarn tmp()
end

using OteraEngine
using Test

@testset "OteraEngine.jl" begin
    #When initializing variables directly
    @test_nowarn Template("test1-1.html")
    tmp = Template("test1-1.html")
    result = ""
    open("test1-2.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp(jl_init=Dict("usr"=>"Julia"))
    
    #In case of no params and specified config
    tmp = Template("test2.html", config=Dict("jl_block_start"=>"{{", "jl_block_stop"=>"}}"))
    regex = r"<strong>\s*(?<value>[0-9]*)\s*?</strong>"
    m = match(regex, tmp())
    @test 0 <= parse(Int, m[:value]) <= 100
    
    #include config file
    @test_throws ArgumentError Template("test2.html", config_path="test.conf")
    tmp = Template("test2.html", config_path="test.toml")
    regex = r"<strong>\s*(?<value>[0-9]*)\s*?</strong>"
    m = match(regex, tmp())
    @test 0 <= parse(Int, m[:value]) <= 100
    
    #check `using` is available
    tmp = Template("test3.html")
    @test_nowarn tmp()
    
    #check tmp codes work properly
    tmp = Template("test4-1.html")
    result = ""
    open("test4-2.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()
end

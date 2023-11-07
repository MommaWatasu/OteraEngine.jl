using OteraEngine
using Test

@testset "OteraEngine.jl" begin
    result = ""
    # When initializing variables directly
    @test_nowarn Template("jl_block1.html")
    tmp = Template("jl_block1.html")
    open("jl_block2.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp(jl_init=Dict("usr"=>"Julia"))
    
    # In case of no params and specified config
    tmp = Template("config.html", config=Dict("jl_block"=>"@@@"))
    regex = r"<strong>\s*(?<value>[0-9]*)\s*?</strong>"
    m = match(regex, tmp())
    @test 0 <= parse(Int, m[:value]) <= 100
    
    # include config file
    @test_throws ArgumentError Template("config.html", config_path="test.conf")
    tmp = Template("config.html", config_path="test.toml")
    regex = r"<strong>\s*(?<value>[0-9]*)\s*?</strong>"
    m = match(regex, tmp())
    @test 0 <= parse(Int, m[:value]) <= 100
    
    # check `using` is available
    tmp = Template("jl_using1.html")
    open("jl_using2.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()
    
    # check tmp codes work properly
    tmp = Template("tmp_block1.html")
    open("tmp_block2.html", "r") do f
        result = read(f, String)
    end
    @test replace(result, "\r"=>"") == replace(tmp(), "\r"=>"")

    # check `include` and `extends` is available
    tmp = Template("include_extends1.html")
    open("include_extends4.html", "r") do f
        result = read(f, String)
    end
    @test replace(result, "\r"=>"") == replace(tmp(), "\r"=>"")

    # check if `dir` option is working
    tmp = Template("wd_test/dir1.html")
    open("wd_test/dir3.html", "r") do f
        result = read(f, String)
    end
    @test replace(result, "\r"=>"") == replace(tmp(), "\r"=>"")
    
    tmp = Template("wd_test/dir1.html", config = Dict("dir"=>"wd_test"))
    open("wd_test/dir3.html", "r") do f
        result = read(f, String)
    end
    @test replace(result, "\r"=>"") == replace(tmp(), "\r"=>"")
end
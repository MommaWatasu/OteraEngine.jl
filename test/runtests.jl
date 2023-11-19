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
    tmp = Template("config.html", config=Dict("jl_block_start"=>"```", "jl_block_end"=>"```"))
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
    tmp = Template("tmp_block1.html", config=Dict("lstrip_blocks"=>true, "trim_blocks"=>true))
    open("tmp_block2.html", "r") do f
        result = read(f, String)
    end
    @test replace(result, "\r"=>"") == replace(tmp(), "\r"=>"")

    # check `include` and `extends` is available
    tmp = Template("include_extends1.html", config=Dict("lstrip_blocks"=>true, "trim_blocks"=>true))
    open("include_extends4.html", "r") do f
        result = read(f, String)
    end
    @test replace(result, "\r"=>"") == replace(tmp(), "\r"=>"")

    # check if `dir` option is working
    tmp = Template("wd_test/dir1.html", config=Dict("lstrip_blocks"=>true, "trim_blocks"=>true))
    open("wd_test/dir3.html", "r") do f
        result = read(f, String)
    end
    @test replace(result, "\r"=>"") == replace(tmp(), "\r"=>"")
    
    tmp = Template("wd_test/dir1.html", config = Dict("dir"=>"wd_test", "lstrip_blocks"=>true, "trim_blocks"=>true))
    open("wd_test/dir3.html", "r") do f
        result = read(f, String)
    end
    @test replace(result, "\r"=>"") == replace(tmp(), "\r"=>"")

    # filters
    say_twice(txt) = txt*txt
    filters = Dict(
        "repeat" => say_twice
    )
    tmp = Template("filter1.html", filters=filters)
    open("filter2.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp(tmp_init=Dict("title"=>"upper case", "greet"=>"Hello"))

    # macro
    tmp = Template("macro1.html")
    open("macro2.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()

    # autospace
    test_logger = TestLogger();
    Base.with_logger(test_logger) do
        Template("macro1.html", config=Dict("autospace"=>true, "lstrip_blocks"=>true))
        Template("macro1.html", config=Dict("autospace"=>true, "trim_blocks"=>true))
    end
    @test test_logger.logs[1].message == "trim_blocks is ignored since autospace is enabled"
    @test test_logger.logs[2].message == "lstrip_blocks is ignored since autospace is enabled"
    tmp = Template("macro1.html", config=Dict("autospace"=>true, "lstrip_blocks"=>true, "trim_blocks"=>true))
    open("autospace.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()

    # disable autoescape
    tmp = Template("autoescape1.html", config=Dict("autoescape"=>false))
    open("autoescape2.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp(tmp_init=Dict("attack"=>"<script>This is injection attack</script>"))
end
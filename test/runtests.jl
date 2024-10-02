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
    @test result == tmp(init=Dict("usr"=>"Julia"))
    
    # In case of no params and specified config
    tmp = Template("config.html", config=Dict("jl_block_start"=>"```code", "jl_block_end"=>"```"))
    regex = r"<strong>\s*(?<value>[0-9]*)\s*?</strong>"
    m = match(regex, tmp())
    @test 0 <= parse(Int, m[:value]) <= 100
    
    # include config file
    @test_throws ArgumentError Template("config.html", config_path="test.conf")
    tmp = Template("config.html", config_path="test.toml")
    regex = r"<strong>\s*(?<value>[0-9]*)\s*?</strong>"
    m = match(regex, tmp())
    @test 0 <= parse(Int, m[:value]) <= 100
    
    # check tmp codes work properly
    tmp = Template("tmp_block1.html", config=Dict("lstrip_blocks"=>true, "trim_blocks"=>true))
    open("tmp_block2.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()

    # check include block
    tmp = Template("include1.html", config=Dict("lstrip_blocks"=>true, "trim_blocks"=>true))
    open("include3.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()

    # check extends block
    tmp = Template("extends1.html", config=Dict("lstrip_blocks"=>true, "trim_blocks"=>true))
    open("extends3.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()

    # check empty extends block
    tmp = Template("extendsempty1.html", config=Dict("lstrip_blocks"=>true, "trim_blocks"=>true))
    open("extendsempty2.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()

    # check nested extends block
    tmp = Template("nestedextends1.html", config=Dict("lstrip_blocks"=>true, "trim_blocks"=>true))
    open("extends4.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()

    # check super block
    tmp = Template("super1.html", config=Dict("lstrip_blocks"=>true, "trim_blocks"=>true))
    open("super3.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()

    # check Julia block inside inherited block
    tmp = Template("super4.html", config=Dict("lstrip_blocks"=>true, "trim_blocks"=>true))
    @test occursin("Hello from Julia", tmp())

    # check TmpBlock
    tmp = Template("block1.html", config=Dict("lstrip_blocks"=>true, "trim_blocks"=>true))
    open("block2.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp(init=Dict("name"=>"watasu", "age"=>15))

    # check if `dir` option is working
    tmp = Template("wd_test/dir1.html", config=Dict("lstrip_blocks"=>true, "trim_blocks"=>true))
    open("wd_test/dir3.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()
    
    tmp = Template("wd_test/dir1.html", config = Dict("dir"=>"wd_test", "lstrip_blocks"=>true, "trim_blocks"=>true))
    open("wd_test/dir3.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()

    # filters
    @test_nowarn @filter function test_filter(txt)
        if txt == "Hello"
            return "World"
        else
            return "Let's say Hello!"
        end
    end
    @filter say_twice(txt) = txt*txt
    filters = Dict(
        "repeat" => :say_twice
    )
    tmp = Template("filter1.html", filters=filters)
    open("filter2.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp(init=Dict("title"=>"upper case", "greet"=>"Hello"))

    # macro
    tmp = Template("macro1.html", config=Dict("autospace"=>true, "trim_blocks"=>true, "lstrip_blocks"=>true))
    open("macro2.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()

    # check import block
    tmp = Template("import1.html", config=Dict("lstrip_blocks"=>true, "trim_blocks"=>true, "autospace"=>true))
    @test result == tmp()

    tmp = Template("from1.html", config=Dict("lstrip_blocks"=>true, "trim_blocks"=>true, "autospace"=>true))
    open("from3.html", "r") do f
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
    @test result == tmp(init=Dict("attack"=>"<script>This is injection attack</script>"))

    # use |> safe filter
    tmp = Template("safe.html")
    open("autoescape2.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp(init=Dict("attack"=>"<script>This is injection attack</script>"))

    tmp = Template("space_control1.html")
    open("space_control2.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()

    # test for character code
    tmp = Template("char_code1.html")
    open("char_code2.html", "r") do f
        result = read(f, String)
    end
    @test tmp() == result
end

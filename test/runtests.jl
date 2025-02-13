using OteraEngine
import OteraEngine: SafeString, safe, ParserError, TemplateError, ParserConfig, ConfigError, config2dict, quote_sql
using Test

@testset "OteraEngine.jl" begin
    @testset "config" begin
        @test_throws ConfigError ParserConfig(
            Dict{String, Union{String, Bool}}(
                "control_block_start" => "{%",
                "control_block_end" => "{%",
                "expression_block_start" => "{{",
                "expression_block_end" => "}}",
                "comment_block_start" => "{#",
                "comment_block_end" => "#}",
                "autospace" => true,
                "lstrip_blocks" => true,
                "trim_blocks" => true,
                "autoescape" => false,
                "dir" => "templates"
            )
        )

        # Create a sample ParserConfig instance
        test_dict = Dict{String, Union{String, Bool}}(
            "control_block_start" => "{%",
            "control_block_end" => "%}",
            "expression_block_start" => "{{",
            "expression_block_end" => "}}",
            "comment_block_start" => "{#",
            "comment_block_end" => "#}",
            "autospace" => true,
            "lstrip_blocks" => true,
            "trim_blocks" => true,
            "autoescape" => false,
            "dir" => "templates"
        )
        @test config2dict(ParserConfig(test_dict)) == test_dict
    end

    @testset "error" begin
        # Test TemplateError display
        err = TemplateError("test error message")
        io = IOBuffer()
        Base.showerror(io, err)
        @test String(take!(io)) == "TemplateError: test error message"

        # Test ParserError display
        err = ParserError("test error message")
        Base.showerror(io, err)
        @test String(take!(io)) == "ParserError: test error message"

        # Test ConfigError display
        err = ConfigError("test error message")
        Base.showerror(io, err)
        @test String(take!(io)) == "ConfigError: test error message"
    end

    result = ""
    
    # When initializing variables directly
    @test_nowarn Template("config1.html")
    # In case of no params and specified config
    tmp = Template("config1.html", config=Dict("control_block_start"=>"{:", "control_block_end"=>":}"))
    open("config2.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()
    
    # include config file
    @test_throws ArgumentError Template("config1.html", config_path="test.conf")
    tmp = Template("config1.html", config_path="test.toml")
    @test result == tmp()
    
    # check tmp codes work properly
    tmp = Template("tmp_block1.html")
    open("tmp_block2.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()

    # check include block
    tmp = Template("include1.html")
    open("include3.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()

    # check extends block
    tmp = Template("extends1.html")
    open("extends3.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()

    # check empty extends block
    tmp = Template("extendsempty1.html")
    open("extendsempty2.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()

    # check super block
    tmp = Template("super1.html")
    open("super3.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()

    # check nested extends block
    tmp = Template("nestedextends1.html")
    open("nestedextends4.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()

    # check Julia block inside inherited block
    tmp = Template("super4.html")
    @test occursin("Hello from Julia", tmp())

    # check TmpBlock
    tmp = Template("block1.html")
    open("block2.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp(init=Dict(:name=>"watasu", :age=>15))

    # check if `dir` option is working
    tmp = Template("wd_test/dir1.html")
    open("wd_test/dir3.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()
    
    tmp = Template("wd_test/dir1.html", config = Dict("dir"=>"wd_test"))
    open("wd_test/dir3.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()

    # filters
    # Test safe function
    @testset "safe tests" begin
        @test safe("Hello") == SafeString("Hello")
        @test safe(SafeString("Already Safe")) == SafeString("Already Safe")
        @test string(SafeString("Convert Me")) == SafeString("Convert Me")
    end

    # Test @filter macro
    @testset "filter macro tests" begin
        @filter function greet(x)
            return "Hello" * x
        end
        @filter hello(x) = "Hello"*x
        @filter evening function greet2(x)
            return "Good evening" * x
        end
        @filter morning greet3(x) = "Good morning" * x
        # Assuming OteraEngine.filters is defined somewhere
        @test ("greet"=>:greet) in [f for f in OteraEngine.filters_alias]
        @test ("hello"=>:hello) in [f for f in OteraEngine.filters_alias]
        @test ("evening"=>:greet2) in [f for f in OteraEngine.filters_alias]
        @test ("morning"=>:greet3) in [f for f in OteraEngine.filters_alias]
    end

    @testset "builtin filter tests" begin
        @test quote_sql(1.234) == "1.234"
        @test quote_sql("Hello") == "'Hello'"
        @test quote_sql(1:3) == "1, 2, 3"
        @test quote_sql([1, 2, 3]) == "1, 2, 3"
        @test quote_sql(true) == "TRUE"
        @test quote_sql([1, "c", true]) == "1, 'c', TRUE"
    end

    @filter repeat say_twice(txt) = txt*txt
    tmp = Template("filter1.html")
    open("filter2.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp(init=Dict(:title=>"upper case", :test=>"Hello", :sql=>false))

    # macro
    tmp = Template("macro1.html")
    open("macro2.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()

    # check import block
    tmp = Template("import1.html")
    @test result == tmp()

    tmp = Template("from1.html")
    open("from3.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()

    # autospace
    test_logger = TestLogger();
    Base.with_logger(test_logger) do
        Template("macro1.html", config = Dict("trim_blocks"=>false))
        Template("macro1.html", config = Dict("lstrip_blocks"=>false))
    end
    @test test_logger.logs[1].message == "trim_blocks is ignored since autospace is enabled"
    @test test_logger.logs[2].message == "lstrip_blocks is ignored since autospace is enabled"
    tmp = Template("macro1.html")
    open("autospace.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()

    # disable autoescape
    tmp = Template("autoescape1.html", config=Dict("autoescape"=>false))
    open("autoescape2.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp(init=Dict(:attack=>"<script>This is injection attack</script>"))

    # use |> safe filter
    tmp = Template("safe.html")
    open("autoescape2.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp(init=Dict(:attack=>"<script>This is injection attack</script>"))

    tmp = Template("space_control1.html", config=Dict("autospace"=>false, "lstrip_blocks"=>false, "trim_blocks"=>false))
    open("space_control2.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp()

    # test for character code
    tmp = Template("char_code1.html", config=Dict("autospace"=>false, "lstrip_blocks"=>false, "trim_blocks"=>false))
    open("char_code2.html", "r") do f
        result = read(f, String)
    end
    @test tmp() == result

    tmp = Template("assign1.html")
    open("assign2.html", "r") do f
        result = read(f, String)
    end
    @test result == tmp(init = Dict(
            :names => ["gate", "horse", "watasu"],
    ))
end

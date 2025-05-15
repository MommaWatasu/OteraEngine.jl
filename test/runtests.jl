using OteraEngine
import OteraEngine: SafeString, safe, ParserError, TemplateError, ParserConfig, ConfigError, config2dict, quote_sql, undefined_symbols
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

    @testset "test undefined_symbols" begin
        # Basic cases
        @test undefined_symbols(1) == Set{Symbol}()
        @test undefined_symbols("hello") == Set{Symbol}()
        @test undefined_symbols(:(:quoted_symbol)) == Set{Symbol}() # QuoteNode
        @test undefined_symbols(:x) == Set([:x])
        @test undefined_symbols(:(true)) == Set{Symbol}() # Known symbol
        @test undefined_symbols(:(nothing)) == Set{Symbol}() # Known symbol

        # Assignment
        @test undefined_symbols(:(a = 1)) == Set{Symbol}()
        @test undefined_symbols(:(a = b)) == Set([:b])
        @test undefined_symbols(:(a = a)) == Set([:a]) # RHS 'a' is undefined before this statement
        # For a += b, 'a' is read and written, 'b' is read.
        # If 'a' is not defined before, both 'a' and 'b' are undefined.
        @test undefined_symbols(:(a += b)) == Set([:a, :b])
        @test undefined_symbols(:(a[i] = x)) == Set([:a, :i, :x])
        @test undefined_symbols(:((x,y) = z)) == Set([:z])

        # Blocks
        @test undefined_symbols(:(begin a = 1; b = a end)) == Set{Symbol}()
        @test undefined_symbols(:(begin a = x; b = a end)) == Set([:x])
        @test undefined_symbols(:(begin b = a; a = 1 end)) == Set([:a])
        @test undefined_symbols(:(begin x; y end)) == Set([:x, :y])

        # If statements
        @test undefined_symbols(:(if cond; then_expr; else else_expr end)) == Set([:cond, :then_expr, :else_expr])
        @test undefined_symbols(:(if true; x; else y end)) == Set([:x, :y])
        @test undefined_symbols(:(if cond; a=1; else b=2 end)) == Set([:cond]) # a,b defined locally
        @test undefined_symbols(:(if (begin c = c_val; c end); x; else y end)) == Set([:c_val, :x, :y])

        # For loops (assuming standard interpretation: i is local, iter is evaluated in outer scope)
        @test undefined_symbols(:(for i = iter; use(i) end)) == Set([:iter, :use])
        @test undefined_symbols(:(for i = 1:N; use(i) end)) == Set([:N, :use])
        @test undefined_symbols(:(for i = 1:3; x = i end)) == Set{Symbol}() # x is defined and used locally

        # Let blocks (assuming standard interpretation: vars are local, RHS evaluated in outer scope or sequentially)
        # The "strict parallel RHS analysis" implies RHS see scope *before* let-vars.
        # Note: Current _walk implementation for :let is incomplete.
        @test undefined_symbols(:(let x = 1; y = x; x + y end)) == Set{Symbol}()
        @test undefined_symbols(:(let x = ext; y = x; x + y end)) == Set([:ext])
        @test undefined_symbols(:(let x = val_x, y = val_y; x + y + z end)) == Set([:val_x, :val_y, :z])
        # Test for "strict parallel RHS": y = x where x is from *outer* scope, not the x = 1 in the same let.
        @test undefined_symbols(:(let x = 1, y = x_outer; x + y end)) == Set([:x_outer])


        # Function calls
        @test undefined_symbols(:(f(a,b))) == Set([:a, :b])
        @test undefined_symbols(:(string(a))) == Set([:a]) # string is known
        @test undefined_symbols(:(+(a,b))) == Set([:a, :b]) # + is known
        @test undefined_symbols(:(obj.field)) == Set([:obj]) # obj is used, field is a property

        # More complex nested structures
        @test_broken undefined_symbols(:(
            begin
                a = val_a
                let x = a, y = val_y
                    if x > 10
                        z = f1(x, y)
                    else
                        z = f2(val_z)
                    end
                    res = z
                end
            end
        )) == Set([:val_a, :val_y, :f1, :f2, :val_z])

        # Test case from a user comment (adapted)
        # `let` RHS are analyzed in outer scope. `let` body uses `let`-defined vars.
        # `if` branches use their surrounding scope. Vars defined in `if` are local to branch.
        # Final `c` is not defined by `if` or `let` in its scope.
        @test undefined_symbols(:(let a=x; if cond; c_in_if=1; else; c_in_if=2; end; c_final end)) == Set([:x, :cond, :c_final])
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

        # with autoescape
        tmp = Template("{{ sql |> quote_sql }}", path = false)
        @test tmp(init=Dict(:sql=>false)) == "FALSE"
        @test tmp(init=Dict(:sql=>1)) == "1"
        @test tmp(init=Dict(:sql=>1:3)) == "1, 2, 3"
        @test tmp(init=Dict(:sql=>"Hello")) == "&#39;Hello&#39;"

        # without autoescape
        tmp = Template("{{ sql |> quote_sql }}", path=false, config=Dict("autoescape"=>false))
        @test tmp(init=Dict(:sql=>false)) == "FALSE"
        @test tmp(init=Dict(:sql=>1)) == "1"
        @test tmp(init=Dict(:sql=>1:3)) == "1, 2, 3"
        @test tmp(init=Dict(:sql=>"Hello")) == "'Hello'"
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

# Tutorial

## Installation

OteraEngine can be installed using the Julia package manager. From the Julia REPL, type ] to enter the Pkg REPL mode and run.
```
pkg > add OteraEngine
```

## Usage

Acutually, this package has only one structure, but these are very powerful because of Metaprogramming function of Julia.

```@docs
Template
```
Learn about grammer and configuration in the sections below.

### Syntax
Actually, you have two way to write template. The first way is to write the code in julia. This is example:
```
<html>
    <head><title>MyPage</title></head>
    <body>
        The current time is <strong>
        ```
        using Dates
        now()
        ```
        </strong>
    </body>
</html>
```
the code inside
```
    ```...```
```
is executed as julia code(with the default configuration). In this case, OteraEngine insert the output of `now()`.

The second way is to use Jinja like syntax. Have you ever seen template like this?:
```
#input
<html>
    <head><title>MyPage</title></head>
    <body>
        {% set name = "watasu" %}
        {% if name=="watasu" %}
        your name is {{ name }}, right?
        {% end %}
        {% for i in 1 : 10 %}
        Hello {{i}}
        {% end %}
        {% with age = 15 %}
        and your age is {{ age }}.
        {% end %}
    </body>
</html>
#output
<html>
    <head><title>MyPage</title></head>
    <body>
        your name is watasu, right?
        Hello 1
        Hello 2
        Hello 3
        Hello 4
        Hello 5
        Hello 6
        Hello 7
        Hello 8
        Hello 9
        Hello 10
        and your age is 15.
        </body>
</html>
```
these statement is available:
- `if` : insert the content in this statement if the expression is true.
- `for` : loop and insert values to variables.
- `with` : assign a value to a variable. variables defined with this statement is available until `end`
- `set` : assign a value to a variable. variables defined with this statement don't have a scope.
- `end` : represent the end of a statement. this is necessary for `if`, `for`, `with`.
these code will be executed after transformed to julia code. So the basic syntax is the same as Julia.

And you can also insert variables in the text. Here is an example(`tmp_init = Dict("name"=>"watasu")`):
```
#input
my name is {{ name }}.
#output
my name is watasu
```
the variables inside
```
{{...}}
```
is replaced with values defined in `tmp_init` or template code.

### Configurations
there are six configurations:
- `jl_block_start`: The string at the start of jl code blocks.
- `jl_block_stop` : The string at the end of jl code blocks.
- `tmp_block_start`: The string at the start of tmp code blocks.
- `tmp_block_start` : The string at the end of tmp code blocks.
- `variable_block_start` : The string at the start of variable blocks.
- `variable_block_stop` : The string at the end of variable blocks.
and the default configuration is this:
```
    "jl_block_start"=>"```",
    "jl_block_stop"=>"```",
    "tmp_block_start"=>"{%",
    "tmp_block_stop"=>"%}",
    "variable_block_start"=>"{{",
    "variable_block_stop"=>"}}"
```
configurations can be loaded from TOML file. You don't have to specify all the configurations(The rest uses the default settings).
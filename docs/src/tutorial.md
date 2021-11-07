# Tutorial

Acutually, this package has only two structure and function, but these are very powerful because of Metaprogramming function of Julia.

```@docs
Template
```

Specifically, you can also do this.
```
#HTML Template File
<html>
    </head><title>MyPage</title><head>
    <body>
        The current time is <strong>
        `
        using Dates
        now()
        `
        </strong>
    </body>
</html>
```

```
#Julia code
using Jinja

tmp = Template("./time.html") #The last HTML
println(tmp())
#The current time comes in the last HTML code intead of the Julia code and returns it.
```
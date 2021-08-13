module Setup

function wrap_print_args(f, args...; kwargs...)
    println("* Running wrap_print_args with arguments:")
    for (i, arg) in enumerate(args)
        println("* i = $i, arg = $arg")
    end
    for (k, v) in kwargs
        println("* k = $k, v = $v")
    end
    return f(args...; kwargs...)
end

mul2(x) = x .* 2

end # module Setup

using .Setup

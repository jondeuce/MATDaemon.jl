push!(LOAD_PATH, joinpath(@__DIR__))
push!(LOAD_PATH, joinpath(@__DIR__, ".."))
using Documenter, MATDaemon

makedocs(;
    modules = [MATDaemon],
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
    ),
    sitename = "MATDaemon.jl",
    authors = "Jonathan Doucette",
    pages = [
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo = "github.com/jondeuce/MATDaemon.jl.git",
    push_preview = true,
    deploy_config = Documenter.GitHubActions(),
)

push!(LOAD_PATH, joinpath(@__DIR__))
push!(LOAD_PATH, joinpath(@__DIR__, ".."))
using Documenter, JuliaFromMATLAB

makedocs(;
    modules = [JuliaFromMATLAB],
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
    ),
    sitename = "JuliaFromMATLAB.jl",
    authors = "Jonathan Doucette",
    pages = [
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo = "github.com/jondeuce/JuliaFromMATLAB.jl.git",
    push_preview = true,
    deploy_config = Documenter.GitHubActions(),
)

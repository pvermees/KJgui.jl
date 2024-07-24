if !(@isdefined rerun)
    using Revise, Pkg
    Pkg.activate("/home/pvermees/git/PTgui")
    Pkg.instantiate()
    Pkg.precompile()
    cd("/home/pvermees/git/PTgui/test")
end

rerun = true

include("runtests.jl")

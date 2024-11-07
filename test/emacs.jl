if !(@isdefined rerun)
    using Revise, Pkg
    Pkg.activate("/home/pvermees/git/PTgui.jl")
    Pkg.instantiate()
    Pkg.precompile()
    cd("/home/pvermees/git/PTgui.jl/test")
end

rerun = true

include("runtests.jl")

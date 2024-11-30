if !(@isdefined rerun)
    using Revise, Pkg
    Pkg.activate("/home/pvermees/git/KJgui.jl")
    Pkg.instantiate()
    Pkg.precompile()
    cd("/home/pvermees/git/KJgui.jl/test")
end

rerun = true

include("runtests.jl")

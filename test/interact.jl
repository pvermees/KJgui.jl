if !(@isdefined rerun)
    using Pkg
    Pkg.activate("/home/pvermees/git/KJgui.jl")
    Pkg.instantiate()
    Pkg.precompile()
    cd("/home/pvermees/git/KJgui.jl/test")
end

rerun = true

using Revise, KJgui, Test, Infiltrator
import KJ

KJ.TUI(KJgui)

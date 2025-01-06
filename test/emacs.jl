if !(@isdefined rerun)
    using Pkg
    Pkg.activate("/home/pvermees/git/KJgui.jl")
    Pkg.instantiate()
    Pkg.precompile()
    cd("/home/pvermees/git/KJgui.jl/test")
    using Revise, KJgui
    import KJ
end

rerun = true

KJ.TUI(KJgui,logbook="plot.log")

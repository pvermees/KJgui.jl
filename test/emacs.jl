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
if false
    KJ.TUI(KJgui;logbook="logs/test.log",reset=true)
else
    include("runtests.jl")
end

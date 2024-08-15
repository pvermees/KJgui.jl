if !(@isdefined rerun)
    using Pkg
    Pkg.activate("/home/pvermees/git/PTgui")
    Pkg.instantiate()
    Pkg.precompile()
    cd("/home/pvermees/git/PTgui/test")
end

rerun = true

using Revise, PTgui, Test, Infiltrator
import Plasmatrace

Plasmatrace.PT(PTgui)

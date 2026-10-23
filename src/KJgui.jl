module KJgui

using GLMakie, Makie, KJ, DataFrames

include("recipes.jl")
include("interferences.jl")
include("gui.jl")
include("interference_popup.jl")

export run_gui, open!, close!

end

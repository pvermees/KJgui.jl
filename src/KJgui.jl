module KJgui

using GLMakie, Makie, KJ, DataFrames

include("recipes.jl")
include("popup.jl")
include("gui.jl")

export run_gui

end

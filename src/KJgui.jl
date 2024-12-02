module KJgui

using Infiltrator, Gtk4, Makie, KJ, DataFrames
import Random, CSV

include("dialogs.jl")
include("main.jl")
include("MakiePlots.jl")
include("plots.jl")

end

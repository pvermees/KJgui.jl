# Installing KJgui

```julia
using Pkg
pkg"add https://github.com/MakieOrg/Makie.jl.git#sd/breaking-gui:ComputePipeline https://github.com/MakieOrg/Makie.jl.git#sd/breaking-gui:Makie https://github.com/MakieOrg/Makie.jl.git#sd/breaking-gui:GLMakie https://github.com/pvermees/KJ.jl https://github.com/pvermees/KJgui.jl#sd/makie-gui2"
```

Then `using KJgui; KJgui.run_gui(path="…")`.

Requires Julia ≥ 1.10 and an OpenGL 3.3 GPU (or `Xvfb` for headless).

# Installing KJgui

```julia
using Pkg
pkg"add ComputePipeline#sd/breaking-gui Makie#sd/breaking-gui GLMakie#sd/breaking-gui https://github.com/pvermees/KJ.jl https://github.com/pvermees/KJgui.jl#sd/makie-gui2"
```

Then `using KJgui; KJgui.run_gui(path="…")`.

Requires Julia ≥ 1.10 and an OpenGL 3.3 GPU (or `Xvfb` for headless).

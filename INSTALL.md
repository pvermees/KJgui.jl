# Installing KJgui

```julia
using Pkg
Pkg.add([
    PackageSpec(url="https://github.com/MakieOrg/Makie.jl.git", subdir="ComputePipeline", rev="sd/breaking-gui"),
    PackageSpec(url="https://github.com/MakieOrg/Makie.jl.git", subdir="Makie",           rev="sd/breaking-gui"),
    PackageSpec(url="https://github.com/MakieOrg/Makie.jl.git", subdir="GLMakie",         rev="sd/breaking-gui"),
    PackageSpec(url="https://github.com/pvermees/KJ.jl",    rev="main"),
    PackageSpec(url="https://github.com/pvermees/KJgui.jl", rev="sd/makie-gui2"),
])
```

Then `using KJgui; KJgui.run_gui(path="…")`.

Requires Julia ≥ 1.10 and an OpenGL 3.3 GPU (or `Xvfb` for headless).

# KJgui

## GUI for KJ

[KJ](https://github.com/pvermees/KJ.jl) is a free and open data
reduction software package for LA-ICP-MS written in
[Julia](https://julialang.org/). KJgui is an extension that provides a
graphical user interface to KJ.

## Installation

Enter the following commands at the Julia console (a.k.a REPL):

```
import Pkg
Pkg.add(url="https://github.com/pvermees/KJ.jl.git")
Pkg.add(url="https://github.com/pvermees/KJgui.jl.git")
```

## Minimal working example

```
julia> using KJ, KJgui
julia> TUI(KJgui)
----------
 KJ 0.1.1
----------

r: Read data files[*]
m: Specify the method[*]
t: Tabulate the samples
s: Mark mineral standards[*]
g: Mark reference glasses[*]
v: View and adjust each sample
p: Process the data[*]
e: Export the results
l: Logs and templates
o: Options
u: Update
c: Clear
a: Extra
x: Exit
?: Help
x

julia> 
```


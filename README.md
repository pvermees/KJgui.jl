# PTgui

## GUI for Plasmatrace

Plasmatrace is a free and open data reduction software package for
LA-ICP-MS written in [Julia](https://julialang.org/). PTgui is an
extension that provides a graphical user interface to Plasmatrace.

## Installation

Enter the following commands at the Julia console (a.k.a REPL):

```
import Pkg
Pkg.add(url="https://github.com/pvermees/Plasmatrace.jl.git")
Pkg.add(url="https://github.com/pvermees/PTgui.jl.git")
```

## Minimal working example

```
julia> using Plasmatrace, PTgui
julia> PT(PTgui)
-------------------
 Plasmatrace 0.6.4
-------------------

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
x: Exit
?: Help
x

julia> 
```


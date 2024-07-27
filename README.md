# PTgui

## GUI for Plasmatrace

Plasmatrace is a free and open data reduction software package for
LA-ICP-MS written in [Julia](https://julialang.org/). PTgui is an
extension that provides a graphical user interface to Plasmatrace.

## Installation

```
import Pkg
Pkg.add(url="https://github.com/pvermees/Plasmatrace.git")
Pkg.add(url="https://github.com/pvermees/PTgui.git")
```

## Example

At the Julia REPL:

```
julia> using Plasmatrace, PTgui
julia> PT!(PTgui)
-------------------
 Plasmatrace 0.6.1
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
```


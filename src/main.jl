function extend!(_KJ::AbstractDict)

    _KJ["ctrl"]["gui"] = GtkWindow("KJ",-1,-1,true,false)

    _KJ["tree"]["top"].action["r"] = GUIread!
    
    _KJ["tree"]["top"].action["c"] = GUIclear!
    
    updateTree!(_KJ["tree"],"dir|file",
                action = Dict("d" => GUIloadICPdir!,
                              "p" => GUIloadICPfile!))

    updateTree!(_KJ["tree"],"log";
                action = Dict(
                    "i" => GUIimportLog!,
                    "e" => GUIexportLog,
                    "o" => GUIopenTemplate!,
                    "s" => GUIsaveTemplate
                ))

    updateTree!(_KJ["tree"],"format";
                action = Dict(
                    "c" => GUIexport2csv,
                    "j" => GUIexport2json
                ))

    updateTree!(_KJ["tree"],"export";
                action = GUIsubset!)

    _KJ["tree"]["top"].action["v"] = GUIviewer!

    updateTree!(_KJ["tree"],"view";
                message = 
                "n: Next\n" * 
                "p: Previous\n" * 
                "g: Go to\n" * 
                "t: Tabulate all the samples in the session\n" * 
                "r: Plot signals or ratios?\n" * 
                "w: Selection window(s)\n" * 
                "d: Choose a data transformation\n" * 
                "x: Exit\n" * 
                "?: Help",
                help =
                "It is useful to view all the samples in your analytical " * 
                "sequence at least once, to modify blank and signal " * 
                "windows or checking the fit to the standards.",
                action = Dict(
                    "n" => GUInext!,
                    "p" => GUIprevious!,
                    "g" => "goto",
                    "t" => KJ.TUItabulate,
                    "r" => "setDen",
                    "w" => "setWin",
                    "d" => "transformation"
                ))

    updateTree!(_KJ["tree"],"goto";
                action=GUIgoto!)
    
    updateTree!(_KJ["tree"],"setDen";
                action=GUIratios!)

    updateTree!(_KJ["tree"],"setWin";
                message = 
                "Choose an option to set t0 and/or the blank and/or signal window(s):\n" * 
                "a: Automatic (current sample)\n" * 
                "A: Automatic (all samples)\n" *
                "x: Exit this menu and use the mouse to select your windows " *
                "on the time resolved signal plot:\n" *
                "   drag    : Manually set a one-part window (this sample)\n" *
                "   a + drag: Manually set a one-part window (all samples)\n" *
                "   m + drag: Manually set a multi-part window (this sample)\n" * 
                "?: Help",
                help =
                "Specify 'time zero' by dragging a line, or the blank and " *
                "signal windows by dragging a rectangle across the " *
                "relevants part of the time-resolved signal plot, " *
                "or trust KJ to choose them automatically. " *
                "The blanks of all the analyses (samples + standards) will " *
                "be combined and interpolated under the signal.",
                action = Dict(
                    "a" => GUIoneAutoWindow!,
                    "A" => GUIallAutoWindow!
                ))

    updateTree!(_KJ["tree"],"transformation";
                action=GUItransformation!)
    
    Gtk4.GLib.G_.set_prgname("KJ")

end
export extend!

function updateTree!(tree::AbstractDict,
                     key::AbstractString;
                     message=tree[key].message,
                     help=tree[key].help,
                     action=tree[key].action)
    tree[key] = (message=message,help=help,action=action)
end

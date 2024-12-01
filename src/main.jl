function extend!(_KJ::AbstractDict)

    _KJ["ctrl"]["gui"] = GtkWindow("KJ",-1,-1,true,false)

    _KJ["tree"]["top"].action["r"] = GUIread!
    
    _KJ["tree"]["top"].action["c"] = GUIclear!

    _KJ["tree"]["top"].action["v"] = GUIviewer!
    
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
    
    updateTree!(_KJ["tree"],"view";
                action = Dict(
                    "n" => GUInext!,
                    "p" => GUIprevious!,
                    "g" => "goto",
                    "t" => KJ.TUItabulate,
                    "r" => "setDen",
                    "b" => "Bwin",
                    "s" => "Swin",
                    "d" => "transformation"
                ))

    updateTree!(_KJ["tree"],"goto";
                action=GUIgoto!)

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

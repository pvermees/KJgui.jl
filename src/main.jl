function extend!(_PT::AbstractDict)

    _PT["ctrl"]["gui"] = GtkWindow("Plasmatrace",-1,-1,true,false)

    _PT["tree"]["top"].action["r"] = GUIread!
    
    _PT["tree"]["top"].action["c"] = GUIclear!

    updateTree!(_PT["tree"],"dir|file",
                action = Dict("d" => GUIloadICPdir!,
                              "p" => GUIloadICPfile!))

    updateTree!(_PT["tree"],"log";
                action = Dict(
                    "i" => GUIimportLog!,
                    "e" => GUIexportLog,
                    "o" => GUIopenTemplate!,
                    "s" => GUIsaveTemplate
                ))

    updateTree!(_PT["tree"],"format";
                action = Dict(
                    "c" => GUIexport2csv,
                    "j" => GUIexport2json
                ))

    updateTree!(_PT["tree"],"export";
                action = GUIsubset!)

    updateTree!(_PT["tree","view"];
                action = Dict(
                    "n" => GUInext!,
                    "p" => GUIprevious!,
                    "g" => GUIgoto!,
                    "t" => TUItabulate,
                    "r" => "setDen",
                    "b" => "Bwin",
                    "s" => "Swin",
                    "d" => "transformation"
                ))

    Gtk4.GLib.G_.set_prgname("Plasmatrace")

end
export extend!

function updateTree!(tree::AbstractDict,
                     key::AbstractString;
                     message=tree[key].message,
                     help=tree[key].help,
                     action=tree[key].action)
    tree[key] = (message=message,help=help,action=action)
end

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

function GUIread!(ctrl::AbstractDict)
    if ctrl["template"]
        if ctrl["multifile"]
            return GUIloadICPdir!(ctrl)
        else
            return GUIloadICPfile!(ctrl)
        end
    else
        return "instrument"
    end
end

function GUIclear!(ctrl::AbstractDict)
    default = Plasmatrace.TUIinit()
    for (k,v) in default
        ctrl[k] = v
    end
    return nothing
end

function GUIloadICPdir!(ctrl::AbstractDict)
    if !ctrl["log"]
        open_dialog("Choose a folder",ctrl["gui"];
                    select_folder=true,
                    start_folder=splitdir(ctrl["ICPpath"])[1]) do dname
                        @async Plasmatrace.TUIloadICPdir!(ctrl,dname)
                        push!(ctrl["history"],["loadICPdir",dname])
                    end
    end
    ctrl["priority"]["load"] = false
    return "xx"
end
export GUIloadICPdir!

function GUIloadICPfile!(ctrl::AbstractDict)
    if !ctrl["log"]
        open_dialog("Choose an ICP-MS data file",ctrl["gui"];
                    start_folder=splitdir(ctrl["ICPpath"])[1]) do ICPpath
                        ctrl["ICPpath"] = ICPpath
                        push!(ctrl["history"],["loadICPfile",ICPpath])
                        @async open_dialog("Choose a laser log file",ctrl["gui"];
                                           start_folder=splitdir(ICPpath)[1]) do LApath
                                               @async Plasmatrace.TUIloadLAfile!(ctrl,LApath)
                                               push!(ctrl["history"],["loadLAfile",LApath])
                                           end
                    end
    end
    ctrl["priority"]["load"] = false
    return "xx"
end
export GUIloadICPfile!

function GUIimportLog!(ctrl::AbstractDict)
    open_dialog("Choose a session log",ctrl["gui"]) do fname
        @async Plasmatrace.TUIimportLog!(ctrl,fname)
        push!(ctrl["history"],["importLog",fname])
    end
    return nothing
end
export GUIimportLog!

function GUIexportLog(ctrl::AbstractDict)
    save_dialog("Choose a file name",ctrl["gui"]) do fname
        @async Plasmatrace.TUIexportLog(ctrl,fname)
    end
    return "x"
end
export GUIexportLog

function GUIopenTemplate!(ctrl::AbstractDict)
    open_dialog("Choose a Plasmatrace template",ctrl["gui"]) do fname
        @async Plasmatrace.TUIopenTemplate!(ctrl,fname)
        push!(ctrl["history"],["openTemplate",fname])
    end
    ctrl["priority"]["method"] = false
    ctrl["priority"]["standards"] = false
    ctrl["priority"]["glass"] = false
    return "x"
end
export GUIopenTemplate!

function GUIsaveTemplate(ctrl::AbstractDict)
    save_dialog("Choose a file name",ctrl["gui"]) do fname
        @async Plasmatrace.TUIsaveTemplate(ctrl,fname)
        push!(ctrl["history"],["saveTemplate",fname])
    end
    return "xx"
end
export GUIsaveTemplate

function GUIsubset!(ctrl::AbstractDict,
                    response::AbstractString)
    out = Plasmatrace.TUIsubset!(ctrl,response)
    if out == "csv"
        return GUIexport2csv(ctrl)
    else
        return "format"
    end
end

function GUIexport2csv(ctrl::AbstractDict)
    save_dialog("Choose a csv file name",ctrl["gui"]) do fname
        @async Plasmatrace.TUIexport2csv(ctrl,fname)
        push!(ctrl["history"],["csv",fname])
    end
    if ctrl["method"] == "concentrations"
        return "x"
    else
        return "xx"
    end
end
export GUIexport2csv

function GUIexport2json(ctrl::AbstractDict)
    save_dialog("Choose a json file name",ctrl["gui"]) do fname
        @async Plasmatrace.TUIexport2json(ctrl,fname)
        push!(ctrl["history"],["json",fname])
    end
    return "xx"
end
export GUIexport2json

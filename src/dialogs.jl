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
    default = KJ.TUIinit()
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
                        @async KJ.TUIloadICPdir!(ctrl,dname)
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
                                               @async KJ.TUIloadLAfile!(ctrl,LApath)
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
        @async KJ.TUIimportLog!(ctrl,fname)
        push!(ctrl["history"],["importLog",fname])
    end
    return nothing
end
export GUIimportLog!

function GUIexportLog(ctrl::AbstractDict)
    save_dialog("Choose a file name",ctrl["gui"]) do fname
        @async KJ.TUIexportLog(ctrl,fname)
    end
    return "x"
end
export GUIexportLog

function GUIopenTemplate!(ctrl::AbstractDict)
    open_dialog("Choose a KJ template",ctrl["gui"]) do fname
        @async KJ.TUIopenTemplate!(ctrl,fname)
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
        @async KJ.TUIsaveTemplate(ctrl,fname)
        push!(ctrl["history"],["saveTemplate",fname])
    end
    return "x"
end
export GUIsaveTemplate

function GUIsubset!(ctrl::AbstractDict,
                    response::AbstractString)
    out = KJ.TUIsubset!(ctrl,response)
    if out == "csv"
        return GUIexport2csv(ctrl)
    else
        return "format"
    end
end

function GUIexport2csv(ctrl::AbstractDict)
    save_dialog("Choose a csv file name",ctrl["gui"]) do fname
        @async KJ.TUIexport2csv(ctrl,fname)
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
        @async KJ.TUIexport2json(ctrl,fname)
        push!(ctrl["history"],["json",fname])
    end
    return "xx"
end
export GUIexport2json

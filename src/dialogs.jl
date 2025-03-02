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
    if ctrl["log"]
        out = nothing
    else
        open_dialog("Choose a folder",ctrl["gui"];
                    select_folder=true,
                    start_folder=splitdir(ctrl["ICPpath"])[1]) do dname
                        KJ.TUIloadICPdir!(ctrl,dname)
                        push!(ctrl["history"],["loadICPdir",dname])
                    end
        out = "xx"
    end
    ctrl["priority"]["load"] = false
    return out
end
export GUIloadICPdir!

function GUIloadICPfile!(ctrl::AbstractDict)
    if ctrl["log"]
        out = nothing
    else
        open_dialog("Choose an ICP-MS data file",ctrl["gui"];
                    start_folder=splitdir(ctrl["ICPpath"])[1]) do ICPpath
                        ctrl["ICPpath"] = ICPpath
                        push!(ctrl["history"],["loadICPfile",ICPpath])
                        open_dialog("Choose a laser log file",ctrl["gui"];
                                           start_folder=splitdir(ICPpath)[1]) do LApath
                                               push!(ctrl["history"],["loadLAfile",LApath])
                                               KJ.TUIloadLAfile!(ctrl,LApath)
                                           end
                    end
        out = "xx"
    end
    ctrl["priority"]["load"] = false
    return out
end
export GUIloadICPfile!

function GUIimportLog!(ctrl::AbstractDict)
    open_dialog("Choose a session log",ctrl["gui"]) do fname
        KJ.TUIimportLog!(ctrl,fname;verbose=false)
    end
    return "x"
end
export GUIimportLog!

function GUIexportLog(ctrl::AbstractDict)
    save_dialog("Choose a file name",ctrl["gui"]) do fname
        KJ.TUIexportLog(ctrl,fname)
    end
    return "x"
end
export GUIexportLog

function GUIopenTemplate!(ctrl::AbstractDict)
    open_dialog("Choose a KJ template",ctrl["gui"]) do fname
        KJ.TUIopenTemplate!(ctrl,fname)
    end
    ctrl["priority"]["method"] = false
    ctrl["priority"]["standards"] = false
    ctrl["priority"]["glass"] = false
    return "x"
end
export GUIopenTemplate!

function GUIsaveTemplate(ctrl::AbstractDict)
    save_dialog("Choose a file name",ctrl["gui"]) do fname
        KJ.TUIsaveTemplate(ctrl,fname)
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
    if ctrl["log"]
        out = nothing
    else
        save_dialog("Choose a csv file name",ctrl["gui"]) do fname
            push!(ctrl["history"],["csv",fname])
            KJ.TUIexport2csv(ctrl,fname)
        end
        out = ctrl["method"] == "concentrations" ? "x" : "xx"
    end
    return out
end
export GUIexport2csv

function GUIexport2json(ctrl::AbstractDict)
    if ctrl["log"]
        out = nothing
    else
        save_dialog("Choose a json file name",ctrl["gui"]) do fname
            push!(ctrl["history"],["json",fname])
            KJ.TUIexport2json(ctrl,fname)
        end
        out = "xx"
    end
    return out
end
export GUIexport2json

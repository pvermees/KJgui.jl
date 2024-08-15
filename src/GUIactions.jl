function GUIloadICPdir!(ctrl::AbstractDict)
    open_dialog("Choose a folder",ctrl["gui"];
                select_folder=true,
                start_folder=splitdir(ctrl["ICPpath"])[1]) do dname
                    @async Plasmatrace.TUIloadICPdir!(ctrl,dname)
                    push!(ctrl["history"],["loadICPdir",dname])
                end
    ctrl["priority"]["load"] = false
    return "xx"
end
export GUIloadICPdir!

function GUIloadICPfile!(ctrl::AbstractDict)
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
    ctrl["priority"]["load"] = false
    return "xx"
end
export GUIloadICPfile!

function GUIimportLog!(ctrl::AbstractDict)
    open_dialog("Choose a session log",ctrl["gui"]) do fname
        @async Plasmatrace.TUIimportLog!(ctrl,fname)
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
    end
    return "xx"
end
export GUIopenTemplate!

function GUIsaveTemplate(ctrl::AbstractDict)
    save_dialog("Choose a file name",ctrl["gui"]) do fname
        @async Plasmatrace.TUIsaveTemplate(ctrl,fname)
    end
    return "xx"
end
export GUIsaveTemplate

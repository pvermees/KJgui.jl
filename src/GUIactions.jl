function GUIloadICPdir!(ctrl::AbstractDict)
    open_dialog("Choose a folder",ctrl["gui"];
                select_folder=true,
                start_folder=splitdir(ctrl["ICPpath"])[1]) do dname
                    @async Plasmatrace.TUIloadICPdir!(ctrl,dname)
                end
    ctrl["priority"]["load"] = false
    return "xx"
end
export GUIloadICPdir!

function GUIloadICPfile!(ctrl::AbstractDict)
    open_dialog("Choose an ICP-MS data file",ctrl["gui"];
                start_folder=splitdir(ctrl["ICPpath"])[1]) do ICPpath
                    ctrl["ICPpath"] = ICPpath
                    @async open_dialog("Choose a laser log file",ctrl["gui"];
                                       start_folder=splitdir(ICPpath)[1]) do LApath
                                           Plasmatrace.TUIloadLAfile!(ctrl,LApath)
                                       end
                end
    ctrl["priority"]["load"] = false
    return "xx"
end
export GUIloadICPfile!

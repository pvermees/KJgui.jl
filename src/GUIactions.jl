function GUIloadICPdir!(ctrl::AbstractDict)
    dname = open_dialog("Choose a folder",ctrl["gui"];
                        select_folder=true,
                        start_folder=splitdir(ctrl["ICPpath"])[1])
    Plasmatrace.TUIloadICPdir!(ctrl,dname)
    return "xx"
end
export GUIloadICPdir!

function GUIloadICPfile!(ctrl::AbstractDict)
    ctrl["ICPpath"] = open_dialog("Choose an ICP-MS data file",ctrl["gui"];
                                  start_folder=splitdir(ctrl["ICPpath"])[1])
    LApath = open_dialog("Choose a laser log file",ctrl["gui"];
                         start_folder=splitdir(ctrl["ICPpath"])[1])
    Plasmatrace.TUIloadLAfile!(ctrl,LApath)
    return "xx"
end
export GUIloadICPfile!

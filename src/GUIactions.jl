function GUIloadICPdir!(ctrl::AbstractDict)
    dname = open_dialog("Choose a folder",ctrl["gui"];
                        select_folder=true,
                        start_folder=ctrl["ICPpath"])
    Plasmatrace.TUIloadICPdir!(ctrl,dname)
    return "xx"
end
export GUIloadICPdir!

function GUIloadICPfile!(ctrl::AbstractDict)
    fname = open_dialog("Choose a file",ctrl["gui"];
                        start_folder=ctrl["ICPpath"])
    return Plasmatrace.TUIloadICPfile!(ctrl,fname)
end
export GUIloadICPfile!

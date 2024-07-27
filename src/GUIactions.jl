function GUIloadICPdir!(ctrl::AbstractDict)
    dname = Gtk4.open_dialog("Choose a folder";select_folder=true)
    Plasmatrace.TUIloadICPdir!(ctrl,dname)
    return "top"
end
export GUIloadICPdir!

function GUIloadICPfile!(ctrl::AbstractDict)
    fname = Gtk4.open_dialog("Choose a file")
    return Plasmatrace.TUIloadICPfile!(ctrl,fname)
end
export GUIloadICPfile!

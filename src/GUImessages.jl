function GUIloadICPdir(ctrl::AbstractDict)
    dname = Gtk4.open_dialog("Choose a folder";select_folder=true)
    return dname
end
export GUIloadICPdir

function GUIloadICPfile(ctrl::AbstractDict)
    fname = Gtk4.open_dialog("Choose a file")
    return fname
end
export GUIloadICPfile



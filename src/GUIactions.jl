function GUIloadICPdir!(ctrl::AbstractDict)
    win = GtkWindow("Plasmatrace")
    dname = open_dialog("Choose a folder",win;select_folder=true,start_folder=pwd())
    Plasmatrace.TUIloadICPdir!(ctrl,dname)
    destroy(win)
    return "xx"
end
export GUIloadICPdir!

function GUIloadICPfile!(ctrl::AbstractDict)
    win = GtkWindow("My First Gtk4.jl Program",-1,-1,true,false)
    fname = open_dialog("Choose a file",win;
                        start_folder=pwd())
    return Plasmatrace.TUIloadICPfile!(ctrl,fname)
end
export GUIloadICPfile!

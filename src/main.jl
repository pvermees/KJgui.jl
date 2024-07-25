function main()
    win = GtkWindow("My First Gtk.jl Program", 400, 200)
    b = GtkButton("Click Me")
    push!(win,b)
    showall(win)
    dump(Plasmatrace.PTree())
end
export main

function PT()

    tree = Plasmatrace.PTree()

    cb = GtkComboBoxText()

    choices = collect(keys(tree["top"].action))
    
    for choice in choices
        push!(cb,choice)
    end
    
    cb.active = 0 # default choice

    signal_connect(cb, "changed") do widget, others...
        # get the active index
        idx = cb.active
        # get the active string
        str = Gtk4.active_text(cb)
        println("Active element is \"$str\" at index $idx")
    end

    win = GtkWindow("ComboBoxText Example")
    push!(win, cb)

    show(win)
    
end
export PT

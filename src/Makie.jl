using Makie

function create_gui()
    scene = Scene()
    button = Button(scene, "Click me!")
    label = Label(scene, "Hello, Julia!")

    vbox = VBox(button, label)
    layout(scene, vbox)
end

create_gui()

function PTree!(tree::AbstractDict)

    tree["instrument"] = (
        message =
        "PTgui test!\n"*
        "a: Agilent\n"*
        "t: ThermoFisher\n"*
        "x: Exit\n"*
        "?: Help",
        help = "Choose a file format. Email us if you don't "*
        "find your instrument in this list.",
        action = Plasmatrace.TUIinstrument!
    )
    
end
export PTree!

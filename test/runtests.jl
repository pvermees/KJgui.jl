using KJ, KJgui, Test, Infiltrator

function MakieTest()
    method = Gmethod(name="Lu-Hf",
                     P=Pairing(ion="Lu176",proxy="Lu175",channel="Lu175 -> 175"),
                     D=Pairing(ion="Hf176", channel="Hf176 -> 258"),
                     d=Pairing(ion="Hf177", proxy="Hf178",channel="Hf178 -> 260"),
                     groups = Dict("BP" => "BP"))
    myrun = load("Lu-Hf";format="Agilent")
    fit = KJ.process!(myrun,method)
    ctrl = Dict(
        "run" => myrun,
        "i" => 1,
        "den" => "", # "Hf176 -> 258"
        "method" => method,
        "fit" => fit,
        "transformation" => "log"
    )
    GUIinitPlotter!(ctrl)
end

function ExtensionTest()
    KJ.TUI(KJgui;debug=true)
end

# @testset "Makie test" begin MakieTest() end
@testset "Extension test" begin ExtensionTest() end
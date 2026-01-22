using KJ, KJgui, Test, Infiltrator

function MakieTest()
    method = Gmethod("Lu-Hf";
                     channels = (P="Lu175 -> 175",D="Hf176 -> 258",d="Hf178 -> 260"),
                     standards = ["BP"],
                     bias = Dict("Hf" => ["NIST612"]),
                     nbias = 2)
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

@testset "Makie test" begin MakieTest() end
@testset "Extension test" begin ExtensionTest() end

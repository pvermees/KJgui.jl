using KJ, KJgui, Makie, Test, Infiltrator

function MakieTest()
    myrun = load("Lu-Hf",instrument="Agilent")
    dt = dwelltime(myrun)
    method = "Lu-Hf";
    channels = Dict("d"=>"Hf178 -> 260",
                    "D"=>"Hf176 -> 258",
                    "P"=>"Lu175 -> 175");
    standards = Dict("Hogsbo_gt" => "hogsbo")#"BP_gt" => "BP")#
    glass = Dict("NIST612" => "NIST612p")
    blk, fit = process!(myrun,dt,method,channels,standards,glass,
                        nblank=2,ndrift=1,ndown=1);
    ctrl = Dict(
        "run" => myrun,
        "i" => 1,
        "den" => nothing,
        "method" => method,
        "channels" => channels,
        "standards" => standards,
        "glass" => glass,
        "PAcutoff" => nothing,
        "blank" => blk,
        "dwell" => dt,
        "par" => fit,
        "transformation" => "log"
    )
    GUIinitPlotter!(ctrl)
    MakiePlot!(ctrl,channels;transformation="log")
end

function ExtensionTest()
    KJ.TUI(KJgui,logbook="test.log")
end

@testset "Makie test" begin MakieTest() end
#@testset "Extension test" begin ExtensionTest() end

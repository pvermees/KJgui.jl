using KJ, KJgui, Makie, Test, Infiltrator

function MakieTest()
    if true
        myrun = load("/home/pvermees/Documents/Plasmatrace/NHM/240708_PV_Zircon.Iolite.csv",
                     "/home/pvermees/Documents/Plasmatrace/NHM/240708_PV_Zircon_Maps.csv",
                     instrument="Agilent")
        method = "Lu-Hf";
        channels = Dict("d"=>"Hf178 -> 260",
                        "D"=>"Hf176 -> 258",
                        "P"=>"Lu175 -> 175");
        standards = Dict("Hogsbo_gt" => "hogsbo")
        glass = Dict("NIST612" => "NIST612p")
    else
        myrun = load("Lu-Hf",instrument="Agilent")
        method = "Lu-Hf";
        channels = Dict("d"=>"Hf178 -> 260",
                        "D"=>"Hf176 -> 258",
                        "P"=>"Lu175 -> 175");
        standards = Dict("Hogsbo_gt" => "hogsbo")
        glass = Dict("NIST612" => "NIST612p")
    end
    dt = dwelltime(myrun)
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

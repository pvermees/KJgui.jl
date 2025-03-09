using KJ, KJgui, Makie, Test, Infiltrator

function MakieTest()
    if true
        myrun = load("/home/pvermees/Dropbox/Plasmatrace/Abdulkadir",
                     instrument="Agilent")
        sett0!(myrun,6.5)
        setBwin!(myrun)
        setSwin!(myrun)
        method = "U-Pb"
        channels = Dict("d"=>"Pb207",
                        "D"=>"Pb206",
                        "P"=>"U238")
        standards = Dict("MAD_ap" => "MAD")
        glass = Dict("NIST612" => "GLASS")
        den = nothing
    end
    if false
        myrun = load("/home/pvermees/Documents/Plasmatrace/NHM/240708_PV_Zircon_Maps.csv",
                     "/home/pvermees/Documents/Plasmatrace/NHM/240708_PV_Zircon.Iolite.csv",
                     instrument="Agilent")
        method = "U-Pb"
        channels = Dict("d"=>"Pb207",
                        "D"=>"Pb206",
                        "P"=>"U238")
        standards = Dict("91500_zr" => "91500")
        glass = Dict("NIST612" => "NIST612")
        den = "Pb206"
    end
    if false
        myrun = load("Lu-Hf",instrument="Agilent")
        method = "Lu-Hf"
        channels = Dict("d"=>"Hf178 -> 260",
                        "D"=>"Hf176 -> 258",
                        "P"=>"Lu175 -> 175")
        standards = Dict("Hogsbo_gt" => "hogsbo")
        glass = Dict("NIST612" => "NIST612p")
        den = nothing
    end
    blk, fit = KJ.process!(myrun,method,channels,standards,glass;
                           nblank=2,ndrift=1,ndown=0)
    ctrl = Dict(
        "run" => myrun,
        "i" => 1,
        "den" => den,
        "method" => method,
        "channels" => channels,
        "standards" => standards,
        "glass" => glass,
        "PAcutoff" => nothing,
        "blank" => blk,
        "par" => fit,
        "transformation" => "sqrt"
    )
    GUIinitPlotter!(ctrl)
end

function ExtensionTest()
    KJ.TUI(KJgui,logbook="logs/test.log")
end

@testset "Makie test" begin MakieTest() end
#@testset "Extension test" begin ExtensionTest() end

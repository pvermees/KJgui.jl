using KJ, KJgui, Makie, Test, Infiltrator

function MakieTest()
    if false
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
    if true
        myrun = load("Lu-Hf",instrument="Agilent")
        method = "Lu-Hf"
        channels = Dict("d"=>"Hf178 -> 260",
                        "D"=>"Hf176 -> 258",
                        "P"=>"Lu175 -> 175")
        standards = Dict("Hogsbo_gt" => "hogsbo")
        glass = Dict("NIST612" => "NIST612p")
        den = "Hf176 -> 258"
    end
    #blk, fit = KJ.process!(myrun,method,channels,standards,glass;
    #                       nblank=2,ndrift=1,ndown=0)
    ctrl = Dict(
        "run" => myrun,
        "i" => 1,
        "den" => nothing, #den,
        "method" => "", #method,
        "channels" => getChannels(myrun), #channels,
        "standards" => Dict{String,Union{Nothing,String}}(), #standards,
        "glass" => Dict{String,Union{Nothing,String}}(), #glass,
        "PAcutoff" => nothing,
        "blank" => nothing, #blk,
        "par" => nothing, #fit,
        "transformation" => "log"
    )
    GUIinitPlotter!(ctrl)
end

function ExtensionTest()
    KJ.TUI(KJgui)#,logbook="logs/test.log")
end

#@testset "Makie test" begin MakieTest() end
@testset "Extension test" begin ExtensionTest() end

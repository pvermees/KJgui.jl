using PTgui, Test, Infiltrator, GLMakie
import Plasmatrace

function ExtensionTest()
    Plasmatrace.PT(PTgui,logbook="test.log")
end

function MakieTest()
    fig = MakiePlot()
    display(fig)
end

#@testset "Extension test" begin ExtensionTest() end
@testset "Makie test" begin MakieTest() end

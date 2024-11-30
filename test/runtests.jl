using KJgui, Test, Infiltrator, GLMakie
import KJ

function ExtensionTest()
    KJ.TUI(KJgui,logbook="test.log")
end

function MakieTest()
    fig = MakiePlot()
    display(fig)
end

@testset "Extension test" begin ExtensionTest() end
@testset "Makie test" begin MakieTest() end

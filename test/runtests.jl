using KJgui, Test, Infiltrator
import KJ

function ExtensionTest()
    KJ.TUI(KJgui,logbook="test.log")
end

@testset "Extension test" begin ExtensionTest() end

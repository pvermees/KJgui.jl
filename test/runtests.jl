using PTgui, Test, Infiltrator
import Plasmatrace

function ExtensionTest()
    Plasmatrace.PT(PTgui,logbook="test.log")
end

@testset "Extension test" begin ExtensionTest() end

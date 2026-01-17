using KJ, KJgui, Test, Infiltrator

function ExtensionTest()
    KJ.TUI(KJgui)
end

@testset "Extension test" begin ExtensionTest() end

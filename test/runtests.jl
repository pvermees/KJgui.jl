using PTgui, Plasmatrace, Test, Infiltrator

function PlasmatraceTest()
    Plasmatrace.PT!(logbook="test.log")
end

function ExtensionTest()
    Plasmatrace.PT!(PTgui,logbook="instrument.log")
end

@testset "Plasmatrace test" begin PlasmatraceTest() end
@testset "Extension test" begin ExtensionTest() end

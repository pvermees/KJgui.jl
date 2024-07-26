using PTgui, Plasmatrace, Test, Infiltrator

function PTtest()
    Plasmatrace.PT!(PTgui,logbook="test.log")
end

@testset "top menu test" begin PTtest() end

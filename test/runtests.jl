using PTgui, Test, Infiltrator

function maintest()
    main()
end

@testset "top menu test" begin maintest() end

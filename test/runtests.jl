using PTgui, Gtk, Test

function maintest()
    main()
end

@testset "main test" begin maintest() end

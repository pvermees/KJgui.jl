using KJ, KJgui, GLMakie, Makie, Test

const LUHF = joinpath(@__DIR__, "Lu-Hf")

@testset "Dashboard: layout and reactivity" begin
    GLMakie.activate!(visible=false)
    result = KJgui.run_gui(path=LUHF)
    fig = result.fig

    @test !isnothing(result.state[])
    @test length(result.state[]) > 0

    blocks = [typeof(b) for b in fig.content]
    @test count(==(Axis), blocks) == 3          # count-rate + P/D + S/D
    @test count(==(Legend), blocks) == 1        # count-rate only
    @test count(==(Table), blocks) == 1
    @test count(==(Button), blocks) >= length(KJgui.STUB_BUTTONS) + 1  # + Read

    table = result.table
    @test table.i_selected[] == 1

    # Click a different row → sample observable updates.
    table.i_selected[] = 5
    @test result.sample_obs[].sname == result.state[][5].sname

    # Prev / Next still wrap correctly via navigate!.
    KJgui.navigate!(table, result.state, +1)
    @test table.i_selected[] == 6
    KJgui.navigate!(table, result.state, -10)
    @test table.i_selected[] in 1:length(result.state[])

    # User-click path: Makie's Table writes `t.selection[]` (the documented
    # output observable) on left-click but does NOT write back to
    # `t.i_selected`. The dashboard bridges selection → i_selected, so a
    # click-simulated `t.selection[]` write must navigate the plot.
    tableplot = filter(p -> p isa Makie.Plot, table.blockscene.plots)[1]
    Makie.update!(tableplot.attributes; i_selected=12, i_selected_cell=(12, 1))
    table.selection[] = Makie.get_row_data(tableplot, 12)
    @test table.i_selected[] == 12
    @test result.sample_obs[].sname == result.state[][12].sname
end

@testset "SamplePlot exposes labels through get_plots → Legend(fig, ax) works" begin
    GLMakie.activate!(visible=false)
    myrun = KJ.load(LUHF; format="Agilent")

    fig = Figure()
    ax = Axis(fig[1, 1])
    KJgui.sampleplot!(ax, myrun[1])
    leg = Legend(fig[1, 2], ax)
    @test leg isa Legend
    @test leg.layoutobservables.gridcontent[] !== nothing
    @test length(leg.entrygroups[][1][2]) == 18
end

@testset "RatioPlot exposes labels through get_plots → Legend(fig, ax) works" begin
    GLMakie.activate!(visible=false)
    myrun = KJ.load(LUHF; format="Agilent")
    chans = KJ.getChannels(myrun[1])

    fig = Figure()
    ax = Axis(fig[1, 1])
    KJgui.ratioplot!(ax, myrun[1];
                     numerators=[chans[1], chans[2]],
                     denominator=chans[end])
    leg = Legend(fig[1, 2], ax)
    @test leg isa Legend
    @test length(leg.entrygroups[][1][2]) == 2
end

@testset "Method panel builds a Gmethod and drives the ratio plot" begin
    GLMakie.activate!(visible=false)
    result = KJgui.run_gui(path=LUHF)

    # On first load, the panel defaults to Lu-Hf and seeds P/D/d from
    # the channels actually present in the run.
    m = result.method[]
    @test m isa KJ.Gmethod
    @test m.name == "Lu-Hf"
    @test m.P.ion == "Lu176"
    @test m.D.ion == "Hf176"
    @test m.d.ion == "Hf177"
    @test m.D.channel == "Hf176 -> 258"      # exact ion match
    @test startswith(m.P.channel, "Lu")      # element-only fallback
    @test startswith(m.d.channel, "Hf")

    # The ratio panel draws P/D and d/D in two side-by-side plots —
    # matching KJ's `averat` (which exports those exact two ratios) and the
    # README §Analysis ("P/D and S/D", where S = d). D is the common
    # denominator.
    @test result.numerators[]  == [m.P.channel, m.d.channel]
    @test result.denominator[] == m.D.channel
    @test result.bot_panel.ax_pd.title[] == "P / D"
    @test result.bot_panel.ax_sd.title[] == "S / D"

    # Switching method through every supported decay system must not throw
    # (it would crash if the suggestion fell back to a single channel
    # filling all three slots — see the `c != den` filter in the recipe).
    for mname in ("Rb-Sr", "U-Pb", "K-Ca", "Re-Os", "Lu-Hf")
        idx = findfirst(==(mname), result.bot_panel.method_menu.options[])
        result.bot_panel.method_menu.i_selected[] = idx
        @test result.method[].name == mname
        # All three channels must be distinct so the series plot keeps
        # exactly two ratios.
        p, d, s = result.method[].P.channel,
                  result.method[].D.channel,
                  result.method[].d.channel
        @test length(unique((p, d, s))) == 3
    end
end

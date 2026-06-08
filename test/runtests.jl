using KJ, KJgui, GLMakie, Makie, Test

const LUHF = joinpath(@__DIR__, "Lu-Hf")

@testset "Dashboard: layout and reactivity" begin
    GLMakie.activate!(visible=false)
    result = KJgui.run_gui(path=LUHF)
    fig = result.fig

    @test !isnothing(result.state[])
    @test length(result.state[]) > 0

    blocks = [typeof(b) for b in fig.content]
    @test count(==(Axis), blocks) == 2          # count-rate + biplot (ratio stack empty)
    @test count(==(Legend), blocks) == 0        # axislegend is per-ratio-plot, none yet
    @test count(==(Table), blocks) == 1
    @test count(==(Button), blocks) >= length(KJgui.STUB_BUTTONS) + 1  # + Read (method is a Menu)

    # In geochronology mode the config row is collapsed — P/D/S come from
    # the Key's radio columns. Internal-standard picker stays hidden too.
    @test result.bot_panel.internal_menu.blockscene.visible[] == false

    # The Key has ON + HL per channel (no role columns — method's P/D/S come
    # from `suggest_channel_indices`, not a user override).
    key = result.top_panel.key_ref[]
    sp = result.top_panel.plot_ref[]
    nchan = length(sp.channel_names[])
    @test length(key.on_boxes) == nchan
    @test length(key.hl_boxes) == nchan
    key.on_boxes[1].checked[] = false           # switch channel 1 off
    @test sp.channel_visible[][1] == false
    key.hl_boxes[2].checked[] = true            # highlight channel 2
    @test sp.channel_highlight[][2] == true

    # Biplot is on by default and toggles via the Panels checkbox / observable.
    bp_panel = result.biplot_panel
    @test bp_panel.ax.title[] == "Isochron"
    @test bp_panel.ax.blockscene.visible[] == true
    @test !isnothing(bp_panel.plot_ref[])
    result.biplot_visible[] = false
    @test bp_panel.ax.blockscene.visible[] == false
    result.biplot_visible[] = true
    @test bp_panel.ax.blockscene.visible[] == true

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

    # Method channels are exposed as observables (driven by the Key's P/D/S
    # radio columns). The biplot reads these directly.
    @test result.bot_panel.p_channel[]      == m.P.channel
    @test result.bot_panel.d_channel[]      == m.D.channel
    @test result.bot_panel.sister_channel[] == m.d.channel

    # Ratio stack starts empty — the user composes plots via the popup.
    @test isempty(result.bot_panel.ratio_defs[])

    # `add_def!` (the popup's Apply target, exposed for tests) pushes a ratio
    # plot into the stack with the chosen numerators + denominator.
    result.bot_panel.add_def!([m.P.channel, m.d.channel], m.D.channel)
    @test length(result.bot_panel.ratio_defs[]) == 1
    def = result.bot_panel.ratio_defs[][1]
    @test sort(def.numerators[]) == sort([m.P.channel, m.d.channel])
    @test def.denominator[]      == m.D.channel

    # × close = remove_def! removes from the stack.
    result.bot_panel.remove_def!(def)
    @test isempty(result.bot_panel.ratio_defs[])

    # Switching method through every supported decay system must not throw
    # (it would crash if the suggestion fell back to a single channel
    # filling all three slots — see the `c != den` filter in the recipe).
    for mname in ("Rb-Sr", "U-Pb", "K-Ca", "Re-Os", "Lu-Hf")
        result.method_choice[] = mname
        @test result.method[].name == mname
        # All three channels must be distinct so the series plot keeps
        # exactly two ratios.
        p, d, s = result.method[].P.channel,
                  result.method[].D.channel,
                  result.method[].d.channel
        @test length(unique((p, d, s))) == 3
    end
end

@testset "Concentration mode collapses the ratio + biplot sections" begin
    GLMakie.activate!(visible=false)
    result = KJgui.run_gui(path=LUHF)
    bp = result.bot_panel

    # Default geochronology mode keeps the biplot visible.
    @test result.method[] isa KJ.Gmethod
    @test result.biplot_panel.ax.blockscene.visible[] == true

    # Switching to Concentration builds a Cmethod, hides the biplot, and
    # surfaces the internal-standard picker.
    result.method_choice[] = KJgui.CONCENTRATION_OPTION
    @test result.method[] isa KJ.Cmethod
    @test result.biplot_visible[] == true
    @test result.biplot_panel.ax.blockscene.visible[] == false
    @test bp.internal_menu.blockscene.visible[] == true

    # Switching back to a decay system restores geochronology mode.
    result.method_choice[] = "Lu-Hf"
    @test result.method[] isa KJ.Gmethod
    @test result.biplot_panel.ax.blockscene.visible[] == true
    @test bp.internal_menu.blockscene.visible[] == false
end

@testset "BiPlot recipe scatters one ratio pair per time step" begin
    GLMakie.activate!(visible=false)
    myrun = KJ.load(LUHF; format="Agilent")
    chans = KJ.getChannels(myrun[1])

    fig = Figure()
    ax = Axis(fig[1, 1])
    bp = KJgui.biplot!(ax, myrun[1];
                       x_numerator=chans[end-1],   # Hf176 -> 258
                       y_numerator=chans[end],     # Hf178 -> 260
                       denominator=chans[end-1])   # use Hf176 → trivial y=1 col
    # One scatter child, with as many points as the sample has rows.
    sc = filter(p -> p isa Makie.Scatter, bp.plots)[1]
    n_rows = length(myrun[1].dat[!, 1])
    @test length(sc[1][]) == n_rows
end

@testset "Groups auto-detected, References panel drives method.groups" begin
    GLMakie.activate!(visible=false)
    result = KJgui.run_gui(path=LUHF)

    # Loader leaves every sample at group="sample"; auto_assign_groups! parses
    # the "<prefix> - <n>" naming convention used in the Lu-Hf test data.
    groups = unique(s.group for s in result.state[])
    @test sort(groups) == ["BP", "NIST612p", "hogsbo_pul"]

    # References panel shows one row per group with an RM picker.
    refs = result.refs_panel
    @test length(refs.menus[]) == 3
    @test length(refs.labels[]) == 3
    @test KJgui.RM_NONE in refs.menus[][1].options[]   # "(none)" sentinel
    @test "BP" in refs.menus[][1].options[]             # Lu-Hf RM list
    @test "NIST612" in refs.menus[][1].options[]

    # Auto-preselection runs on data load — group names get matched fuzzily
    # to RMs (BP→BP, NIST612p→NIST612, hogsbo_pul→Hogsbo) and assignments
    # populate immediately.
    @test result.group_rm_assignments[] == Dict(
        "BP"         => "BP",
        "NIST612p"   => "NIST612",
        "hogsbo_pul" => "Hogsbo",
    )
    @test result.method[].groups == result.group_rm_assignments[]

    # Re-assert the same dict after explicitly setting it — sanity check
    # that user override still drives method.groups correctly.
    result.group_rm_assignments[] = Dict(
        "BP"         => "BP",
        "NIST612p"   => "NIST612",
        "hogsbo_pul" => "Hogsbo",
    )
    m = result.method[]
    @test m.groups == Dict("BP" => "BP",
                           "NIST612p" => "NIST612",
                           "hogsbo_pul" => "Hogsbo")
    @test m.standards == Set(["BP", "NIST612p", "hogsbo_pul"])

    # Switching a role to :massbias moves the group out of `standards` and
    # into `bias.standards` (via KJ.Calibration!) — matches the docs example
    # where NIST612p is the mass-bias standard and hogsbo is the fractionation
    # standard.
    result.group_roles[] = Dict(
        "hogsbo_pul" => :standard,
        "NIST612p"   => :massbias,
        "BP"         => :none,
    )
    m = result.method[]
    @test m.standards == Set(["hogsbo_pul"])
    @test m.bias.standards == Set(["NIST612p"])

    # Switching method swaps the RM list in each menu (U-Pb has different RMs).
    result.method_choice[] = "U-Pb"
    @test "91500" in refs.menus[][1].options[]
    @test !("Hogsbo" in refs.menus[][1].options[])
end

@testset "Process button runs KJ.process! and populates fit" begin
    GLMakie.activate!(visible=false)
    result = KJgui.run_gui(path=LUHF)

    # Auto-preselection has already assigned RMs by name match, so clear
    # them to exercise the "no RMs" path: Process refuses and fit stays nothing.
    @test result.fit[] === nothing
    result.group_rm_assignments[] = Dict{String,String}()
    result.process_btn.clicks[] += 1
    @test result.fit[] === nothing

    # Assign one RM, fire Process → fit becomes a Gfit.
    result.group_rm_assignments[] = Dict("hogsbo_pul" => "Hogsbo")
    @test !isempty(result.method[].groups)
    result.process_btn.clicks[] += 1
    @test result.fit[] isa KJ.Gfit

    # The biplot switches to processed mode: isochron line + uncertainty
    # ribbon + age annotation populated for the currently selected sample.
    bp = result.biplot_panel.plot_ref[]
    @test length(bp.line_xs[]) == 2          # line endpoints: (0, y0) and (x0, 0)
    @test length(bp.line_ys[]) == 2
    @test bp.line_xs[][1] == 0.0
    @test bp.line_ys[][2] == 0.0
    @test occursin("Ma", bp.age_text[])      # "t = … ± … Ma"

    # Ribbon: same x grid (50 points), and lo <= hi pointwise.
    @test length(bp.ribbon_xs[]) == 50
    @test length(bp.ribbon_lo[]) == 50
    @test length(bp.ribbon_hi[]) == 50
    @test all(bp.ribbon_lo[] .<= bp.ribbon_hi[])
end

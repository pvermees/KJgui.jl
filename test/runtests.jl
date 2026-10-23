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
    # +1 for Read, +1 for Method (now a Button too), +1 for References, +1 for Channels.
    @test count(==(Button), blocks) >= length(KJgui.STUB_BUTTONS) + 1

    # In geochronology mode the config row is collapsed — P/D/S come from
    # the method's suggested channels. Internal-standard picker stays hidden.
    @test result.bot_panel.internal_menu.blockscene.visible[] == false

    # Default channel visibility = only P/D/d on; the Channels popup lets
    # the user toggle individual channels.
    sp = result.top_panel.plot_ref[]
    chans = result.bot_panel.channels_obs[]
    roles = (result.bot_panel.p_channel[], result.bot_panel.d_channel[],
             result.bot_panel.sister_channel[])
    @test sp.channel_visible[] == Bool[c in roles for c in chans]
    @test sp.channel_highlight[] == falses(length(chans))

    # Biplot is hidden by default — only meaningful after `KJ.process!`
    # produces a fit. The strip header shows the on/off checkbox so the
    # user knows the panel exists.
    bp_panel = result.biplot_panel
    @test bp_panel.ax.title[] == "Isochron"
    @test !isnothing(bp_panel.plot_ref[])
    @test bp_panel.ax.blockscene.visible[] == false
    # Simulating a fit reveals the biplot; the user-visible checkbox
    # still gates it independently.
    result.fit[] = KJ.Gfit(result.method[])   # real stand-in Gfit
    @test bp_panel.ax.blockscene.visible[] == true
    result.biplot_visible[] = false
    @test bp_panel.ax.blockscene.visible[] == false
    result.biplot_visible[] = true
    @test bp_panel.ax.blockscene.visible[] == true
    result.fit[] = nothing
    @test bp_panel.ax.blockscene.visible[] == false

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

    # User-click path: Makie's Table writes `t.selection[]` on left-click and
    # updates `t.i_selected` via the block's own compute graph. The dashboard
    # bridges selection → i_selected so the plot navigates on synthesized clicks.
    tableplot = filter(p -> p isa Makie.Plot, table.blockscene.plots)[1]
    Makie.update!(table.attributes; i_selected=12, i_selected_cell=(12, 1))
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
    @test isempty(result.bot_panel.ratio_defs)

    # `add_def!` (the popup's Apply target) creates one slot bundling all
    # numerators against the shared denominator.
    KJgui.add_def!(result.bot_panel, [m.P.channel, m.d.channel], m.D.channel)
    @test length(result.bot_panel.ratio_defs) == 1
    slot = only(result.bot_panel.ratio_defs)
    @test sort(slot.numerators[]) == sort([m.P.channel, m.d.channel])
    @test slot.denominator[] == m.D.channel

    # × close = remove_def! drops the slot.
    KJgui.remove_def!(result.bot_panel, slot)
    @test isempty(result.bot_panel.ratio_defs)

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

    # Default geochronology mode: biplot stays hidden until a fit exists.
    @test result.method[] isa KJ.Gmethod
    result.fit[] = KJ.Gfit(result.method[])
    @test result.biplot_panel.ax.blockscene.visible[] == true

    # Switching to Concentration builds a Cmethod, hides the biplot, and
    # collapses the ratio-plot controls. The internal-standard picker
    # lives inside the Method popup (opened via commit path in tests).
    # Add a ratio plot first: collapsing the row to zero height is not enough,
    # because the axis keeps drawing its ylabel/ticks/legend against a
    # one-pixel bbox and they land on the count-rate plot underneath.
    KJgui.ensure_popup!(bp)
    bp.add_btn.clicks[] += 1
    bp.popup_ref[].apply_btn.clicks[] += 1
    @test length(bp.ratio_defs) == 1
    ratio_axes() = [ax for s in bp.ratio_defs for ax in s.axes]
    @test all(ax -> ax.blockscene.visible[], ratio_axes())

    result.method_choice[] = KJgui.CONCENTRATION_OPTION
    @test result.method[] isa KJ.Cmethod
    @test result.biplot_visible[] == true
    @test result.biplot_panel.ax.blockscene.visible[] == false
    @test bp.add_btn.blockscene.visible[] == false
    @test bp.mode_menu.blockscene.visible[] == false
    @test !any(ax -> ax.blockscene.visible[], ratio_axes())
    @test !any(lg -> lg.blockscene.visible[],
               [lg for s in bp.ratio_defs for lg in s.legends])

    # Switching back to a decay system restores geochronology mode. The
    # fit is dropped on any method switch (it references the old method's
    # anchors), so the biplot axis stays hidden until Process runs again.
    result.method_choice[] = "Lu-Hf"
    @test result.method[] isa KJ.Gmethod
    @test result.fit[] === nothing
    @test result.biplot_panel.ax.blockscene.visible[] == false
    @test bp.add_btn.blockscene.visible[] == true
    @test bp.mode_menu.blockscene.visible[] == true
    @test all(ax -> ax.blockscene.visible[], ratio_axes())   # restored

    # ...and comes back once a fit exists again.
    result.fit[] = KJ.Gfit(result.method[])
    @test result.biplot_panel.ax.blockscene.visible[] == true
end

@testset "Concordia overlay toggles by plot-type menu + method" begin
    GLMakie.activate!(visible=false)
    result = KJgui.run_gui(path=LUHF)
    bp = result.biplot_panel

    # Default state: Isochron title, no overlay.
    @test bp.ax.title[] == "Isochron"
    @test bp.concordia_line_ref[]   === nothing
    @test bp.concordia_notice_ref[] === nothing

    # Concordia + Lu-Hf → notice shown, no curve (Concordia is U-Pb only).
    result.plot_type_menu.i_selected[] =
        findfirst(==("Concordia"), result.plot_type_menu.options[])
    @test bp.ax.title[] == "Concordia"
    @test bp.concordia_line_ref[]   === nothing
    @test bp.concordia_notice_ref[] !== nothing

    # Switching the method to U-Pb (Concordia still selected) → curve appears,
    # notice clears.
    result.method_choice[] = "U-Pb"
    @test bp.concordia_line_ref[]   !== nothing
    @test bp.concordia_notice_ref[] === nothing

    # Back to Isochron → both clear.
    result.plot_type_menu.i_selected[] =
        findfirst(==("Isochron"), result.plot_type_menu.options[])
    @test bp.ax.title[] == "Isochron"
    @test bp.concordia_line_ref[]   === nothing
    @test bp.concordia_notice_ref[] === nothing
end

@testset "Ratio mode Split↔Combined keeps defs but swaps axis topology" begin
    GLMakie.activate!(visible=false)
    result = KJgui.run_gui(path=LUHF)
    bot = result.bot_panel
    d1 = bot.d_channel[]

    # One slot with two numerators in Combined mode → 1 Axis with both
    # ratios overlaid, a combined legend, and the slot's single × button.
    KJgui.add_def!(bot, [bot.p_channel[], bot.sister_channel[]], d1)
    @test length(bot.ratio_defs) == 1
    slot = only(bot.ratio_defs)
    @test length(slot.axes) == 1
    @test length(slot.plots) == 2
    @test !isnothing(slot.close_btn)
    @test !isempty(slot.legends)

    # Flip to Split → same slot, now N stacked axes, one per numerator,
    # X-linked. Still one × per slot.
    bot.mode_menu.i_selected[] =
        findfirst(==("Split"), bot.mode_menu.options[])
    @test length(bot.ratio_defs) == 1
    slot = only(bot.ratio_defs)
    @test length(slot.axes) == 2

    # Add a second slot in Split mode.
    third_num = first(filter(c -> c != d1 &&
                                  c != bot.p_channel[] &&
                                  c != bot.sister_channel[],
                              bot.channels_obs[]))
    KJgui.add_def!(bot, [third_num], d1)
    @test length(bot.ratio_defs) == 2

    # Flip back to Combined → slots preserved, each collapses to 1 Axis.
    bot.mode_menu.i_selected[] =
        findfirst(==("Combined"), bot.mode_menu.options[])
    @test length(bot.ratio_defs) == 2
    @test all(length(s.axes) == 1 for s in bot.ratio_defs)
end

@testset "Format picker switches KJ.load format on Read" begin
    GLMakie.activate!(visible=false)
    result = KJgui.run_gui(path=LUHF)

    # Default format is Agilent.
    @test result.format_menu.selection[] == "Agilent"
    @test result.format_menu.options[]   == KJgui.DATA_FORMATS
    @test result.state[][1].sname == "BP - 01"  # Agilent test data

    # Switch the picker to ThermoFisher and point at the iCap test data.
    result.format_menu.i_selected[] =
        findfirst(==("ThermoFisher"), result.format_menu.options[])
    @test result.format_menu.selection[] == "ThermoFisher"

    # Drive the full load-button pipeline via `load_folder!`, which is
    # what the click handler calls once `pick_folder()` returns a path.
    # This covers format inference, format-menu sync, path-label update,
    # and the KJ.load call.
    icap = joinpath(@__DIR__, "..", "..", "KJ", "test", "data", "iCap")
    KJgui.load_folder!(result.state, result.format_menu, result.pathbox_label,
                       icap, "Agilent")
    sleep(0.1)
    @test length(result.state[]) > 0
    @test result.state[][1].sname == "610-1"   # ThermoFisher iCap test data
    @test result.pathbox_label.text[] == basename(icap)
    # iCap folder is `.csv`, so infer_format keeps the current pick — the
    # test set ThermoFisher above.
    @test result.format_menu.selection[] == "ThermoFisher"

    # Switch back to Agilent + reload — the picker+format survive a re-load.
    result.format_menu.i_selected[] =
        findfirst(==("Agilent"), result.format_menu.options[])
    KJgui.load_folder!(result.state, result.format_menu, result.pathbox_label,
                       LUHF, "Agilent")
    sleep(0.1)
    @test result.state[][1].sname == "BP - 01"
    @test result.pathbox_label.text[] == basename(LUHF)
end

@testset "Method popup proxy override propagates through commit_method!" begin
    GLMakie.activate!(visible=false)
    result = KJgui.run_gui(path=LUHF)
    bot = result.bot_panel

    # Default: proxies come from KJ.channel2proxy inference on the channel.
    m = result.method[]
    @test m.P.proxy == "Lu175"   # inferred from "Lu175 -> 175"
    @test m.D.proxy == "Hf176"
    @test m.d.proxy == "Hf178"   # inferred from "Hf178 -> 260" (proxy for 177Hf)

    # Explicit non-inferred override on d → Pairing.proxy changes.
    KJgui.commit_method!(bot, "Lu-Hf",
        bot.p_channel[], bot.d_channel[], bot.sister_channel[];
        s_pr="Hf179")
    @test result.method[].d.proxy == "Hf179"
    @test bot.sister_proxy[]      == "Hf179"

    # Clearing the override (empty string) reverts to inference.
    KJgui.commit_method!(bot, "Lu-Hf",
        bot.p_channel[], bot.d_channel[], bot.sister_channel[];
        s_pr="")
    @test result.method[].d.proxy == "Hf178"
    @test isempty(bot.sister_proxy[])

    # Open the popup: each proxy menu is populated with the role element's
    # full isotope list (not just the channel-inferred one).
    notify(result.method_btn.clicks)
    @test result.method_popup_ref[].proxy_menus[:P].options[] == ["Lu175", "Lu176"]
    @test result.method_popup_ref[].proxy_menus[:D].options[] ==
          ["Hf174", "Hf176", "Hf177", "Hf178", "Hf179", "Hf180"]
    @test result.method_popup_ref[].proxy_menus[:d].options[] ==
          ["Hf174", "Hf176", "Hf177", "Hf178", "Hf179", "Hf180"]
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

@testset "Top axis drag resizes bwin/swin edges and syncs panels" begin
    GLMakie.activate!(visible=false)
    result = KJgui.run_gui(path=LUHF)
    top = result.top_panel
    result.table.i_selected[] = 1; sleep(0.1)
    samp = result.sample_obs[]

    fn = Makie.interactions(top.ax)[:window_drag][2]
    me(t, x) = Makie.MouseEvent(t, 0.0, Point2d(x, 0), Point2f(0,0),
                                 0.0, Point2d(0,0), Point2f(0,0))
    times = samp.dat[!, 1]

    # Drag swin's right edge inwards.
    s_right_t = times[samp.swin[1][2]]
    @test fn(me(Makie.MouseEventTypes.leftdragstart, s_right_t), top.ax) ==
          Makie.Consume(true)
    fn(me(Makie.MouseEventTypes.leftdrag, s_right_t - 10.0), top.ax)
    fn(me(Makie.MouseEventTypes.leftdragstop, s_right_t - 10.0), top.ax)
    @test samp.swin[1][2] < 136
    @test samp.swin[1][1] == 68

    # Drag bwin's left edge to the right.
    b_left_t = times[samp.bwin[1][1]]
    fn(me(Makie.MouseEventTypes.leftdragstart, b_left_t), top.ax)
    fn(me(Makie.MouseEventTypes.leftdrag, b_left_t + 5.0), top.ax)
    fn(me(Makie.MouseEventTypes.leftdragstop, b_left_t + 5.0), top.ax)
    @test samp.bwin[1][1] > 2
    @test samp.bwin[1][2] == 60

    # Pointer not close to any edge → ignored (defers to other interactions).
    midpoint = (b_left_t + times[samp.bwin[1][2]]) / 2 + 0.5
    @test fn(me(Makie.MouseEventTypes.leftdragstart, midpoint), top.ax) ==
          Makie.Consume(false)
end

@testset "Ctrl-drag start on top axis appends a new bwin/swin sub-window" begin
    GLMakie.activate!(visible=false)
    result = KJgui.run_gui(path=LUHF)
    result.table.i_selected[] = 1; sleep(0.1)
    samp = result.sample_obs[]

    bwin_n0, swin_n0 = length(samp.bwin), length(samp.swin)
    times = samp.dat[!, 1]
    t0 = Float64(samp.t0)

    # Below t0 → new bwin segment.
    x_before = t0 - (t0 - times[1]) / 3
    target_b = KJgui.append_window!(samp, :bwin, x_before)
    @test length(samp.bwin) == bwin_n0 + 1
    @test target_b isa KJgui.BwinDrag
    @test target_b.side === :right
    a, b = samp.bwin[end]
    @test b == a + 1
    @test 1 <= a <= length(times) - 1

    # After t0 → new swin segment.
    x_after = t0 + (times[end] - t0) / 3
    target_s = KJgui.append_window!(samp, :swin, x_after)
    @test length(samp.swin) == swin_n0 + 1
    @test target_s isa KJgui.SwinDrag
    @test target_s.side === :right

    # New segment can be grown by the shared edge drag.
    grow_to = min(a + 4, length(times))
    KJgui.drag_to!(samp, target_b, Float64(times[grow_to]))
    @test samp.bwin[end][2] == grow_to
end

@testset "Double-click on count-rate axis toggles nearest-row outlier" begin
    GLMakie.activate!(visible=false)
    result = KJgui.run_gui(path=LUHF)
    top = result.top_panel
    result.table.i_selected[] = 1; sleep(0.1)
    samp = result.sample_obs[]
    times = samp.dat[!, 1]

    fn = Makie.interactions(top.ax)[:toggle_outlier_time][2]
    row = 42
    me(t) = Makie.MouseEvent(t, 0.0, Point2d(Float64(times[row]), 0),
                              Point2f(0,0), 0.0, Point2d(0,0), Point2f(0,0))

    @test all(.!samp.dat.outlier)
    fn(me(Makie.MouseEventTypes.leftdoubleclick), top.ax)
    @test samp.dat.outlier[row] == true

    # Toggle off.
    fn(me(Makie.MouseEventTypes.leftdoubleclick), top.ax)
    @test samp.dat.outlier[row] == false

    # Non-doubleclick ignored.
    fn(me(Makie.MouseEventTypes.leftclick), top.ax)
    @test sum(samp.dat.outlier) == 0

    # Ratio-slot axes also carry the interaction — need at least one def.
    chans = result.bot_panel.channels_obs[]
    if !isempty(chans)
        KJgui.add_def!(result.bot_panel, [chans[1]], chans[end]); sleep(0.05)
        ratio_ax = first(result.bot_panel.ratio_defs[1].axes)
        fn_r = Makie.interactions(ratio_ax)[:toggle_outlier_time][2]
        fn_r(me(Makie.MouseEventTypes.leftdoubleclick), ratio_ax)
        @test samp.dat.outlier[row] == true
    end
end

@testset "Biplot double-click toggles outliers on the underlying sample" begin
    GLMakie.activate!(visible=false)
    result = KJgui.run_gui(path=LUHF)
    biplot = result.biplot_panel
    ax = biplot.ax

    # First sample's biplot is built lazily — kick it by selecting row 1.
    result.table.i_selected[] = 1; sleep(0.2)
    samp = result.sample_obs[]
    @test all(.!samp.dat.outlier)
    @test hasproperty(samp.dat, :outlier)

    fn = Makie.interactions(ax)[:toggle_outlier][2]
    xs = biplot.plot_ref[].xs[]
    ys = biplot.plot_ref[].ys[]
    k = findfirst(i -> !isnan(xs[i]) && !isnan(ys[i]) && (xs[i] != 0 || ys[i] != 0),
                  eachindex(xs))
    me(t) = Makie.MouseEvent(t, 0.0, Point2d(xs[k], ys[k]), Point2f(0,0),
                              0.0, Point2d(0,0), Point2f(0,0))

    # Raw mode (no fit) — scatter index = `samp.dat` row directly.
    fn(me(Makie.MouseEventTypes.leftdoubleclick), ax)
    @test samp.dat.outlier[k] == true
    @test sum(samp.dat.outlier) == 1

    # Double-click again → flip off.
    fn(me(Makie.MouseEventTypes.leftdoubleclick), ax)
    @test samp.dat.outlier[k] == false
    @test sum(samp.dat.outlier) == 0

    # Non-doubleclick events ignored.
    fn(me(Makie.MouseEventTypes.leftclick), ax)
    @test sum(samp.dat.outlier) == 0
end

@testset "Table-based grouping drives method.groups" begin
    GLMakie.activate!(visible=false)
    result = KJgui.run_gui(path=LUHF)

    # Every sample starts at "sample"; grouping happens via group-column clicks.
    @test all(s.group == "sample" for s in result.state[])
    @test isempty(result.group_rm_assignments[])
    @test isempty(result.method[].groups)
    @test isempty(result.method[].standards)

    # group_prefix strips trailing digits from the longest common prefix.
    @test KJgui.group_prefix("BP - 01", "BP - 02") == "BP - "
    @test KJgui.group_prefix("hogsbo_pul - 01", "hogsbo_pul - 02") == "hogsbo_pul - "
    @test KJgui.group_prefix("NIST612p - 01", "NIST612p - 02") == "NIST612p - "
    @test KJgui.group_prefix("abc", "def") == ""

    # First pick: only that one sample lands in the group; no expansion.
    run = result.state[]
    bp1_idx = findfirst(s -> s.sname == "BP - 01", run)
    bp2_idx = findfirst(s -> s.sname == "BP - 02", run)
    @test bp1_idx !== nothing && bp2_idx !== nothing
    KJgui.open_with_defaults!(result.group_picker, run[bp1_idx].sname,
                                            run[bp1_idx].group, bp1_idx)
    # Drive the pick programmatically by clicking the BP button in the
    # picker's button list (button 2 after the "(sample)" reset).
    bp_btn = first(b for b in result.group_picker.rm_buttons
                     if b.label[] == "BP")
    notify(bp_btn.clicks)
    @test count(s -> s.group == "BP - ", run) == 1
    @test run[bp1_idx].group == "BP - "

    # Second pick to the SAME RM triggers LCS auto-expansion: every BP - NN
    # sample now joins the group.
    KJgui.open_with_defaults!(result.group_picker, run[bp2_idx].sname,
                                            run[bp2_idx].group, bp2_idx)
    notify(bp_btn.clicks)
    n_bp_samples = count(s -> startswith(s.sname, "BP - "), run)
    @test count(s -> s.group == "BP - ", run) == n_bp_samples
    # The group is named for the prefix; "BP" is the reference material it maps to.
    @test result.group_rm_assignments[] == Dict("BP - " => "BP")
    @test result.method[].groups == Dict("BP - " => "BP")

    # Reset by picking "(sample)" — BULK-clears every sample sharing the
    # clicked row's current group. Mirrors the LCS bulk-assign so the
    # user can undo a whole group with one click.
    KJgui.open_with_defaults!(result.group_picker, run[bp1_idx].sname,
                                            run[bp1_idx].group, bp1_idx)
    sample_reset_btn = first(b for b in result.group_picker.rm_buttons
                                 if b.label[] == "(sample)")
    notify(sample_reset_btn.clicks)
    @test count(s -> s.group == "BP - ", run) == 0
    @test run[bp1_idx].group == "sample"
    @test run[bp2_idx].group == "sample"

    # The lcs_done flag for "BP" was forgotten with the bulk clear, so a
    # future second pick is allowed to re-expand.
    # First pick — single sample.
    KJgui.open_with_defaults!(result.group_picker, run[bp1_idx].sname,
                                            run[bp1_idx].group, bp1_idx)
    notify(bp_btn.clicks)
    @test count(s -> s.group == "BP - ", run) == 1
    # Second pick — full expansion fires again on a fresh group.
    KJgui.open_with_defaults!(result.group_picker, run[bp2_idx].sname,
                                            run[bp2_idx].group, bp2_idx)
    notify(bp_btn.clicks)
    @test count(s -> s.group == "BP - ", run) ==
          count(s -> startswith(s.sname, "BP - "), run)

    # Now drive the full Lu-Hf assignment dict directly (skipping the picker)
    # and verify the standards/bias-role wiring still works.
    for s in run; s.group = "sample"; end
    for s in run
        if startswith(s.sname, "BP - ")
            s.group = "BP"
        elseif startswith(s.sname, "NIST612p - ")
            s.group = "NIST612p"
        elseif startswith(s.sname, "hogsbo_pul - ")
            s.group = "hogsbo_pul"
        end
    end
    result.group_rm_assignments[] = Dict(
        "BP"         => "BP",
        "NIST612p"   => "NIST612",
        "hogsbo_pul" => "Hogsbo",
    )
    m = result.method[]
    @test m.groups == Dict("BP" => "BP",
                           "NIST612p" => "NIST612",
                           "hogsbo_pul" => "Hogsbo")
    @test m.standards == Set(["BP", "hogsbo_pul"])   # NIST612p is glass-backed → :none

    # Switching a role to :massbias moves the group out of `standards` and
    # into `bias.standards` (via KJ.Calibration!).
    result.group_roles[] = Dict(
        "hogsbo_pul" => :standard,
        "NIST612p"   => :massbias,
        "BP"         => :none,
    )
    m = result.method[]
    @test m.standards == Set(["hogsbo_pul"])
    @test m.bias.standards == Set(["NIST612p"])

    # Switching method swaps the RM list in each menu (U-Pb has different RMs).
    # `notify(result.state)` first to refresh refs popup with the manually
    # mutated sample groups, so it builds menus for BP/NIST612p/hogsbo_pul.
    notify(result.state)
    result.method_choice[] = "U-Pb"
    refs = result.refs_panel
    @test "91500" in refs.rm_menus[1].options[]
    @test !("Hogsbo" in refs.rm_menus[1].options[])
end

@testset "Process button runs KJ.process! and populates fit" begin
    GLMakie.activate!(visible=false)
    result = KJgui.run_gui(path=LUHF)

    # All samples default to group "sample" now; Process refuses with no
    # RM-assigned groups and fit stays nothing.
    @test result.fit[] === nothing
    result.process_btn.clicks[] += 1
    @test result.fit[] === nothing

    # Tag the "hogsbo_pul - NN" samples into a group, wire the RM mapping,
    # then fire Process → fit becomes a Gfit.
    for s in result.state[]
        startswith(s.sname, "hogsbo_pul - ") && (s.group = "hogsbo_pul")
    end
    result.group_rm_assignments[] = Dict("hogsbo_pul" => "Hogsbo")
    @test !isempty(result.method[].groups)
    result.process_btn.clicks[] += 1
    # `run_process!` spawns the heavy fit on a worker thread; poll for
    # completion instead of racing the async task. First run compiles
    # KJ.process!'s heavy code — give it up to 60s.
    let deadline = time() + 60.0
        while isnothing(result.fit[]) && time() < deadline; sleep(0.05); end
    end
    @test result.fit[] isa KJ.Gfit

    # Biplot switches to processed mode: isochron line, uncertainty
    # ribbon, age annotation.
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

    # A fit belongs to the method it was started from. Switching method
    # mid-fit clears `fit_obs`; the in-flight result must not land afterwards
    # and re-populate it with a fit the new method knows nothing about.
    result.process_btn.clicks[] += 1
    result.method_choice[] = "U-Pb"
    @test result.fit[] === nothing
    let deadline = time() + 60.0
        while time() < deadline && !isnothing(result.fit[]); sleep(0.05); end
        # give the worker time to finish and the tick handler to run
        sleep(3.0)
    end
    @test result.method[] isa KJ.Gmethod
    @test result.fit[] === nothing
end

@testset "Interference corrections mirror KJ's TUI flow" begin
    GLMakie.activate!(visible = false)
    result = KJgui.run_gui(path = LUHF)
    bp = result.bot_panel
    chans = bp.channels_obs[]

    # --- science layer: reproduces the configurations KJ's own tests use.
    # KJ's runtests.jl pairs the Lu176 interference on Hf176 with "Lu175 -> 257",
    # not the on-mass "Lu175 -> 175": the target is measured at a +82 mass shift.
    @test KJgui.default_proxy_channel("Lu176", "Hf176 -> 258", chans) == "Lu175 -> 257"

    spec = KJgui.InterferenceSpec("Lu176"; channel = "Lu175 -> 257")
    @test spec.proxy == "Lu175"                     # derived via channel2proxy
    @test KJgui.interference_key(spec) == "Lu176"
    built = KJgui.interference(spec)
    @test built isa KJ.Interference
    @test (built.proxy, built.channel) == ("Lu175", "Lu175 -> 257")

    # Re-Os poly: the proxy is derived from a mass-shifted channel too.
    @test KJgui.InterferenceSpec("Re187"; channel = "Re185 -> 249").proxy == "Re185"

    # Mono corrections are keyed by the interfering channel, per KJ.
    mono = KJgui.MonoInterferenceSpec(channel = "Tm169 -> 185", metal = "Lu175 -> 191",
                                      oxide = "Ir191 -> 191", standards = ["Nist_REEint"])
    @test KJgui.interference_key(mono) == "Tm169 -> 185"
    bm = KJgui.interference(mono)
    @test bm isa KJ.MonoInterference
    @test (bm.metal, bm.oxide) == ("Lu175 -> 191", "Ir191 -> 191")
    @test bm.standards == Set(["Nist_REEint"])

    # When channel2proxy cannot map the channel — KJ's `setInterferenceProxy`
    # state — the proxy is left blank and the isotopes of the element are offered.
    fallback = KJgui.InterferenceSpec("Lu176"; channel = "channel 7")
    @test isempty(fallback.proxy)
    @test KJgui.proxy_candidates("Lu176") == ["Lu175", "Lu176"]

    # --- the ratio cross-check catches the bad Lu row in KJ's settings/iratio.csv,
    # which holds a copy of the Re value. The Re row itself is correct.
    # Guard the constant table itself: it is parsed out of KJ's template, so a
    # format change would otherwise silently empty it and turn every
    # cross-check into a no-op `:unchecked`.
    @test length(KJgui.REFERENCE_IRATIOS) >= 40
    @test KJgui.REFERENCE_IRATIOS["Lu176Lu175"] == 0.02668
    @test KJgui.REFERENCE_IRATIOS["Re185Re187"] == 0.59738
    @test KJgui.REFERENCE_IRATIOS["U238U235"] == 137.818
    # Single-nuclide sections (`lambda`, `imass`) must not leak in as keys.
    @test !haskey(KJgui.REFERENCE_IRATIOS, "Re187")
    @test !haskey(KJgui.REFERENCE_IRATIOS, "U238")
    @test KJgui.reference_ratio("Lu175", "Lu176") == 1 / 0.02668   # reciprocal

    status, applied, reference = KJgui.ratio_check("Lu176", "Lu175")
    @test status === :mismatch
    @test applied / reference > 60
    @test KJgui.ratio_check("Re187", "Re185")[1] === :ok

    # --- panel: only D has an interferable mass in this run
    result.interference_btn.clicks[] += 1
    popup = result.interference_popup_ref[]
    @test !isnothing(popup)
    @test isopen(popup.modal)
    @test sort(collect(keys(popup.add_menus))) == [:D]
    @test Set(collect(popup.add_menus[:D].options[])) == Set(["Yb176", "Lu176"])

    # Adding it through the menu defaults the channel and reaches the method.
    popup.add_menus[:D].selection[] = "Lu176"
    @test KJgui.specs_for(bp, :D) == [KJgui.InterferenceSpec("Lu176", "Lu175", "Lu175 -> 257")]
    @test result.method[].D.interferences["Lu176"].channel == "Lu175 -> 257"

    # Choosing another channel re-derives the proxy, as KJ does on every choice.
    popup.row_menus[(:D, 1, :channel)].selection[] = "Lu175 -> 175"
    @test KJgui.specs_for(bp, :D)[1].channel == "Lu175 -> 175"
    @test KJgui.specs_for(bp, :D)[1].proxy == "Lu175"
    # ...and the mismatched mass shift is reported rather than silently applied.
    @test occursin("mass shift",
                   KJgui.interference_problem(KJgui.specs_for(bp, :D)[1],
                                              "Hf176 -> 258", chans))

    # A half-configured mono row stays in panel state but out of the method,
    # so it cannot key a blank entry into `Pairing.interferences`.
    popup.mono_buttons[:P].clicks[] += 1
    @test length(KJgui.specs_for(bp, :P)) == 1
    @test isempty(result.method[].P.interferences)

    popup.row_buttons[(:P, 1)].clicks[] += 1
    @test isempty(KJgui.specs_for(bp, :P))

    popup.row_buttons[(:D, 1)].clicks[] += 1
    @test isempty(KJgui.specs_for(bp, :D))
    @test isempty(result.method[].D.interferences)

    # A spec is only applied when every channel it names is in the run. A
    # channel that disappears with a reload leaves the row visible and
    # explained, but out of the method rather than handed to `process!`.
    stale = KJgui.InterferenceSpec("Lu176"; channel = "Lu175 -> 257")
    @test KJgui.is_applicable(stale, chans)
    @test !KJgui.is_applicable(stale, ["Aa1 -> 1"])
    @test occursin("not a channel in this run",
                   KJgui.interference_problem(stale, "Hf176 -> 258", ["Aa1 -> 1"]))
    popup.add_menus[:D].selection[] = "Lu176"
    @test !isempty(result.method[].D.interferences)
    bp.channels_obs[] = ["Aa1 -> 1", "Bb2 -> 2"]
    @test KJgui.specs_for(bp, :D) == [stale]        # kept, so it can be fixed
    @test isempty(result.method[].D.interferences)  # but never applied

    # Mono needs its three channels present too, not just non-empty.
    m3 = KJgui.MonoInterferenceSpec(channel = "Aa1 -> 1", metal = "Bb2 -> 2",
                                    oxide = "Aa1 -> 1", standards = ["g"])
    @test KJgui.is_applicable(m3, ["Aa1 -> 1", "Bb2 -> 2"])
    @test !KJgui.is_applicable(m3, ["Aa1 -> 1"])
end

@testset "Groups are identified by prefix, not by reference material" begin
    GLMakie.activate!(visible = false)
    result = KJgui.run_gui(path = LUHF)
    run = result.state[]
    gs = result.group_picker.owner

    @test KJgui.group_prefix("BP - 01") == "BP - "
    @test KJgui.group_prefix("Qmoly") == "Qmoly"     # nothing to strip

    # Reference glasses belong in every decay system's picker: they are the
    # interference and mass-bias standards. Re-Os's refmat table lists only
    # NiS-3 and QMolyHill, so without this the Re-Os workflow is unbuildable.
    opts = KJgui.rm_options_for("Re-Os")
    @test "QMolyHill" in opts
    @test "NIST610" in opts
    @test KJgui.is_reference_glass("NIST610")
    @test !KJgui.is_reference_glass("QMolyHill")
    # NIST612 is in BOTH tables — a Lu-Hf reference material and a glass — so
    # the name-based test calls it a glass and its group defaults to `:none`.
    @test "NIST612" in KJ._KJ["refmat"]["Lu-Hf"].names
    @test KJgui.is_reference_glass("NIST612")

    # Two distinct groups may map to one RM — the Re-Os configuration needs
    # Nist_massbias and Nist_REEint both assigned to NIST610.
    bp = findfirst(s -> s.sname == "BP - 01", run)
    hog = findfirst(s -> s.sname == "hogsbo_pul - 01", run)
    KJgui.assign_group!(gs, "NIST610", bp)
    KJgui.assign_group!(gs, "NIST610", hog)
    @test run[bp].group == "BP - "
    @test run[hog].group == "hogsbo_pul - "
    @test result.group_rm_assignments[] ==
          Dict("BP - " => "NIST610", "hogsbo_pul - " => "NIST610")
    @test result.method[].groups ==
          Dict("BP - " => "NIST610", "hogsbo_pul - " => "NIST610")

    # Glass-backed groups stay out of the fractionation fit until given a role.
    @test isempty(result.method[].standards)
    result.group_roles[] = Dict("BP - " => :standard)
    @test result.method[].standards == Set(["BP - "])
end

@testset "Concentration groups stay named for the glass" begin
    GLMakie.activate!(visible = false)
    result = KJgui.run_gui(path = LUHF)
    result.method_choice[] = KJgui.CONCENTRATION_OPTION
    run = result.state[]
    gs = result.group_picker.owner

    # `KJ.predict` resolves a concentration sample's group through
    # `_KJ["glass"]` (via `elements2concs`), so the group must BE the glass
    # name — prefix naming would break the calibration.
    @test KJgui.group_label(KJgui.CONCENTRATION_OPTION, "GLASS - 01", "NIST612") ==
          "NIST612"
    @test KJgui.group_label("Lu-Hf", "GLASS - 01", "NIST612") == "GLASS - "

    bp1 = findfirst(s -> s.sname == "BP - 01", run)
    bp2 = findfirst(s -> s.sname == "BP - 02", run)
    KJgui.assign_group!(gs, "NIST612", bp1)
    @test run[bp1].group == "NIST612"
    # Second pick still expands by sample-name prefix, not by the glass name.
    KJgui.assign_group!(gs, "NIST612", bp2)
    @test count(s -> s.group == "NIST612", run) ==
          count(s -> startswith(s.sname, "BP - "), run)
    @test result.group_rm_assignments[] == Dict("NIST612" => "NIST612")
end

@testset "Process covers the pointer while fitting" begin
    GLMakie.activate!(visible = false)
    result = KJgui.run_gui(path = LUHF)
    fig = result.fig
    # Over the sidebar buttons, which are what must stop responding.
    mp = Point2f(100, 500)

    @test result.fitting[] == false
    @test isnothing(Makie.find_topmost_cover(fig.scene, mp))

    # `KJ.process!` mutates the run on a worker thread while the render task
    # reads it, so the dashboard stops taking input for the duration.
    result.fitting[] = true
    cover = Makie.find_topmost_cover(fig.scene, mp)
    @test !isnothing(cover)
    @test cover.captures_mouse
    @test Makie.covers_pointer(cover)

    result.fitting[] = false
    @test isnothing(Makie.find_topmost_cover(fig.scene, mp))

    # End to end: a real Process arms and disarms it.
    run = result.state[]
    for s in run
        startswith(s.sname, "hogsbo_pul - ") && (s.group = "hogsbo_pul")
    end
    result.group_rm_assignments[] = Dict("hogsbo_pul" => "Hogsbo")
    result.process_btn.clicks[] += 1
    @test result.fitting[] == true
    let deadline = time() + 60.0
        while isnothing(result.fit[]) && time() < deadline; sleep(0.05); end
    end
    @test result.fit[] isa KJ.Gfit
    @test result.fitting[] == false
end

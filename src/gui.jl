"""
    run_gui(; path=nothing, format="Agilent")

Build and display the KJgui dashboard. The Table's `i_selected` is the
canonical "active sample" observable; prev/next buttons and the plot
panels read from it.

The active `method` decides the layout. A `KJ.Gmethod` (geochronology)
shows the two ratio plots (P/D and S/D); a `KJ.Cmethod` (concentrations)
hides them so the count-rate plot fills the panel. The method is picked
from a dropdown in the left column; channel assignment (P/D/S or internal
standard) sits in a row above the plots.
"""
function run_gui(; path::Union{Nothing,AbstractString}=nothing,
    format::AbstractString="Agilent")
    set_theme!(colors = Makie.derive_colors(accent = RGBf(0.16, 0.52, 0.46)))
    fig = Figure(size=(1700, 1050), backgroundcolor = RGBf(0.98, 0.98, 0.97))

    state = Observable{Union{Nothing,Vector{KJ.Sample}}}(nothing)
    ytransform = Observable{Function}(Makie.pseudolog10)
    method = Observable{Union{Nothing,KJ.KJmethod}}(nothing)
    sample_obs = Observable{Union{Nothing,KJ.Sample}}(nothing)
    # `KJ.process!` returns a Gfit (geochronology) or Cfit (concentration).
    # `nothing` until the user hits "Process data" with valid input.
    fit_obs = Observable{Union{Nothing, KJ.Gfit, KJ.Cfit}}(nothing)

    handles = build_dashboard!(fig, state, sample_obs,
        ytransform, method, fit_obs, format)

    isnothing(path) || load_path!(state, path, format)

    display(fig)
    return (; fig, state, sample_obs, ytransform, method,
        fit=fit_obs, handles...)
end

const STUB_BUTTONS = [
    "Interferences", "Fractionation", "Mass bias",
    "Process data", "Export results", "Logs / templates",
    "Options", "Clear", "Exit",
]

"Instrument CSV layouts accepted by `KJ.load(...; format=...)`."
const DATA_FORMATS = ["Agilent", "ThermoFisher", "FIN2"]

function build_dashboard!(fig::Figure,
    state::Observable,
    sample_obs::Observable,
    ytransform::Observable,
    method::Observable,
    fit_obs::Observable,
    default_format::AbstractString)
    left = fig[1, 1] = GridLayout()
    mid = fig[1, 2] = GridLayout()
    right = fig[1, 3] = GridLayout()

    colsize!(fig.layout, 1, Fixed(180))
    colsize!(fig.layout, 2, Fixed(460))
    # `Auto(false)` so the narrow button column doesn't squeeze the figure.
    rowsize!(fig.layout, 1, Auto(false))

    method_choice = Observable("Lu-Hf")
    biplot_visible = Observable(true)
    # `group → RM` picks; becomes `method.groups` on rebuild.
    group_rm_assignments = Observable(Dict{String,String}())
    # `group → role`: `:standard`, `:massbias`, or `:none`.
    group_roles = Observable(Dict{String,Symbol}())

    # One click opens the native folder picker; the format is auto-inferred
    # from the file extensions found in the folder (Agilent/ThermoFisher = .csv,
    # FIN2 = .FIN). The format menu is kept as an override for the ambiguous
    # .csv case.
    format_menu = Menu(left[1, 1]; options=DATA_FORMATS,
                       default=default_format, width=160)
    load_btn = Button(left[2, 1]; label="Load data folder…", width=160)
    pathbox_label = Label(left[3, 1], "(no folder)"; fontsize=9,
        color=RGBf(0.4, 0.4, 0.4), halign=:left, tellwidth=false, word_wrap=true)
    on(load_btn.clicks) do _
        picked = pick_folder()
        isnothing(picked) || load_folder!(state, format_menu, pathbox_label,
                                          picked, default_format)
    end

    method_btn = Button(left[4, 1];
        label=lift(m -> "Method: $m", method_choice), width=160)
    # Lazy: built once `bot_panel` exists (it owns `channels_obs`).
    method_popup_ref = Base.RefValue{Union{Nothing,MethodPopup}}(nothing)

    refs_btn = Button(left[5, 1]; label="References", width=160)
    refs_popup_ref = Base.RefValue{Union{Nothing,ReferencesPopup}}(nothing)

    channels_btn = Button(left[6, 1]; label="Channels", width=160)
    channels_popup_ref = Base.RefValue{Union{Nothing,ChannelsPopup}}(nothing)

    process_btn = nothing
    for (i, lbl) in enumerate(STUB_BUTTONS)
        b = Button(left[6+i, 1]; label=lbl, width=160)
        if lbl == "Process data"
            process_btn = b
            on(b.clicks) do _
                run_process!(state, method, fit_obs;
                    process_btn=process_btn, spinner=biplot_panel.spinner,
                    fig=fig)
            end
        else
            on(b.clicks) do _
                @info "not implemented yet" button = lbl
            end
        end
    end

    # Pin `mid`'s column width: an Auto column collapses to the table's
    # narrower autosize and lets the right column paint over it.
    colsize!(mid, 1, Fixed(460))
    # Row 1 is a fixed spacer for top margin; table lives at row 2.
    rowsize!(mid, 1, Fixed(20))
    table = build_sample_table!(mid, state, fig; row=2)

    title = Observable("")
    top_panel = build_count_rate_panel!(right, sample_obs, ytransform,
        title, table, state)
    bot_panel = build_bottom_panel!(right, sample_obs, state,
        method, method_choice,
        group_rm_assignments, group_roles, fig, top_panel.ax,
        ytransform, fit_obs)
    biplot_panel = build_biplot_panel!(right, sample_obs,
        bot_panel.p_channel, bot_panel.d_channel, bot_panel.sister_channel)
    register_outlier_toggle!(biplot_panel, sample_obs, method, fit_obs)
    register_window_drag!(top_panel, sample_obs)
    register_outlier_toggle!(top_panel.ax, sample_obs)

    # Biplot controls live with the other top-of-window plot controls
    # (log/linear picker, prev/next). Anchored at the right edge of the
    # top strip.
    ctrls = top_panel.ctrls
    Label(ctrls[1, 5], "biplot"; halign=:right, fontsize=10, tellwidth=true)
    plot_type_menu = Menu(ctrls[1, 6];
        options=["Isochron", "Concordia"], default="Isochron", width=110)
    biplot_cb = Checkbox(ctrls[1, 7]; checked=true)
    on(v -> (biplot_visible[] = v), biplot_cb.checked)
    on(plot_type_menu.selection) do sel
        sel === nothing && return
        apply_concordia_overlay!(biplot_panel, String(sel), method[])
    end
    on(method) do m
        apply_concordia_overlay!(biplot_panel,
            something(plot_type_menu.selection[], "Isochron"), m)
    end

    # `right` column 2 is unused (Key lives in `mid`).
    colsize!(right, 2, Fixed(0))

    # One popup variant per method type (Gmethod: P/D/d roles;
    # Cmethod: internal-standard picker). Same-type reopens reuse the
    # cached instance; type flips destroy and rebuild.
    function ensure_method_popup!()
        for_cmethod = method_choice[] == CONCENTRATION_OPTION
        cur = method_popup_ref[]
        if isnothing(cur) || cur.is_cmethod != for_cmethod
            if !isnothing(cur)
                try close!(cur.modal) catch _ end
            end
            method_popup_ref[] = build_method_popup!(fig, bot_panel; for_cmethod=for_cmethod)
        end
        return method_popup_ref[]
    end
    on(method_btn.clicks) do _
        isempty(bot_panel.channels_obs[]) && return
        open_with_defaults!(ensure_method_popup!())
    end
    # Auto-reopen with the correct type when the user picks a
    # different-type method inside the popup.
    on(method_choice) do _
        cur = method_popup_ref[]
        if !isnothing(cur) && isopen(cur.modal)
            open_with_defaults!(ensure_method_popup!())
        end
    end

    function ensure_refs_popup!()
        isnothing(refs_popup_ref[]) || return refs_popup_ref[]
        refs_popup_ref[] = build_references_popup!(fig,
            state, method_choice, group_rm_assignments, group_roles)
        return refs_popup_ref[]
    end
    # Eager so the auto-preselect runs on first data load.
    refs_panel = ensure_refs_popup!()
    on(refs_btn.clicks) do _
        open_with_defaults!(refs_panel)
    end

    function ensure_channels_popup!()
        isnothing(channels_popup_ref[]) || return channels_popup_ref[]
        # Built lazily on first click; SamplePlot must already exist.
        sp = top_panel.plot_ref[]
        isnothing(sp) && return nothing
        channels_popup_ref[] = build_channels_popup!(fig, sp,
            bot_panel.channels_obs,
            bot_panel.p_channel, bot_panel.d_channel, bot_panel.sister_channel)
        return channels_popup_ref[]
    end
    on(channels_btn.clicks) do _
        cp = ensure_channels_popup!()
        isnothing(cp) || open!(cp.modal)
    end

    group_state = GroupState(state, method_choice, group_rm_assignments)
    group_picker = build_group_picker_popup!(fig, group_state)
    # Column 4 = `:group` (see `build_sample_table!`'s `column_names`).
    table.on_cell_click[] = function (_t, row, col, _data)
        col == 4 || return
        run = state[]
        (isnothing(run) || row == 0 || row > length(run)) && return
        samp = run[row]
        open_with_defaults!(group_picker, samp.sname, samp.group, row)
    end

    # Section is visible whenever a fit exists or the spinner is busy
    # (the spinner needs a pane to render into). The axis only shows on
    # fit; while busy, only the spinner is in the cell.
    busy = biplot_panel.spinner.running
    onany(biplot_visible, method, fit_obs, busy; update=true) do vis, m, fit, b
        section_show = vis && !(m isa KJ.Cmethod) && (!isnothing(fit) || b)
        axis_show    = vis && !(m isa KJ.Cmethod) && !isnothing(fit) && !b
        rowsize!(right, 6, section_show ? Auto() : Fixed(0))
        set_block_visible!(biplot_panel.ax, axis_show)
    end

    # Hide the biplot controls (plot type + on/off) for Cmethod, which has
    # no biplot at all.
    onany(method; update=true) do m
        show = !(m isa KJ.Cmethod)
        set_block_visible!(plot_type_menu, show)
        set_block_visible!(biplot_cb, show)
        apply_mode_layout!(bot_panel, m)
        refresh_config_group!(bot_panel)
    end

    # Raw and processed modes have very different data scales, so any
    # fit change requires re-fitting the biplot's axis limits.
    on(_ -> isnothing(biplot_panel.plot_ref[]) || autolimits!(biplot_panel.ax),
       fit_obs)

    # Re-seed only on channel-set shape change; a method switch alone must
    # not clobber the user's manual channel picks.
    on(bot_panel.channels_obs) do chans
        sp = top_panel.plot_ref[]
        isnothing(sp) && return
        length(sp.channel_visible[]) == length(chans) && return
        default_channel_visibility!(sp, chans,
            bot_panel.p_channel[], bot_panel.d_channel[],
            bot_panel.sister_channel[])
        cp = channels_popup_ref[]
        isnothing(cp) || rebuild!(cp)
    end

    on(table.i_selected) do i
        run = state[]
        (isnothing(run) || isempty(run) || isnothing(i) ||
            i == 0 || i > length(run)) && return
        samp = run[i]
        sample_obs[] = samp
        title[] = "$(i)/$(length(run))  $(samp.sname)  [$(samp.group)]  ($(samp.datetime))"
        # Channel seeding first — biplot reads p/d/sister directly off
        # bot_panel; method-change handler also re-seeds them.
        ensure_ratio_plot!(bot_panel, sample_obs, samp)
        ensure_count_rate_plot!(top_panel, sample_obs, bot_panel)
        ensure_biplot!(biplot_panel, sample_obs, method, fit_obs)
        autolimits!(top_panel.ax)
        for slot in bot_panel.ratio_defs, ax in slot.axes
            autolimits!(ax)
        end
        autolimits!(biplot_panel.ax)
    end

    return (; table, top_panel, bot_panel, biplot_panel, refs_panel,
              refs_btn, refs_popup_ref, group_picker,
              method_choice, method_btn, method_popup_ref, biplot_visible,
              group_rm_assignments, group_roles, process_btn,
              load_btn, format_menu, pathbox_label,
              channels_btn, channels_popup_ref,
              plot_type_menu, biplot_cb)
end

"""
Run `KJ.process!` on the current run + method. `@warn`s on missing data /
method / RM groups instead of throwing. When a `spinner::Spinner` is
passed, the heavy fit runs on a worker thread (`Threads.@spawn`) while
the render loop animates the spinner. `fit_obs` and button-restore run
on the main thread once the compute finishes. Requires
`julia --threads=auto` for real parallelism; with one thread the compute
falls back to the main task and the spinner will freeze.
"""
function run_process!(state::Observable, method::Observable, fit_obs::Observable;
                      process_btn::Union{Nothing,Makie.Button}=nothing,
                      spinner::Union{Nothing,Makie.Spinner}=nothing,
                      fig::Union{Nothing,Figure}=nothing)
    run = state[]
    m = method[]
    if isnothing(run) || isempty(run)
        @warn "Process: load data first"
        return
    end
    if isnothing(m)
        @warn "Process: pick a method first"
        return
    end
    if hasproperty(m, :groups) && isempty(m.groups)
        @warn "Process: assign at least one Reference Material in the References panel"
        return
    end
    # Reject re-entry while a fit is in flight — `spinner.running` stays
    # true from start until the tick handler finalises.
    if !isnothing(spinner) && spinner.running[]
        @warn "Process: a fit is already running"
        return
    end
    original_label = nothing
    original_color = nothing
    if !isnothing(process_btn)
        original_label = process_btn.label[]
        original_color = process_btn.buttoncolor[]
        process_btn.label[] = "Processing…"
        process_btn.buttoncolor[] = RGBf(0.85, 0.90, 1.00)
    end
    finalize! = () -> begin
        isnothing(spinner) || (spinner.running = false)
        if !isnothing(process_btn)
            process_btn.label[] = something(original_label, "Process data")
            isnothing(original_color) ||
                (process_btn.buttoncolor[] = original_color)
        end
    end
    isnothing(spinner) || (spinner.running = true)

    if isnothing(fig)
        # Sync fallback (tests, headless without a render loop). Spinner
        # shows one frame and freezes for the duration of the fit.
        try
            yield()
            fit_obs[] = KJ.process!(run, m)
        catch err
            @warn "Process failed" exception=(err, catch_backtrace())
        finally
            finalize!()
        end
        return
    end

    # `KJ.process!` runs on a worker thread, its result is handed back
    # via a Channel, and picked up by a tick listener that fires on the
    # render task — so `fit_obs[] =` and its downstream `autolimits!`
    # never race GLMakie's compute graph. Requires --threads=auto.
    # Payload is `(:ok, fit)` / `(:err, exc, bt)` so a Cfit/Gfit that
    # happens to be `<: Exception` in some future refactor won't be
    # misread as failure.
    chan = Channel{Tuple}(1)
    listener = Ref{Any}(nothing)
    listener[] = on(events(fig).tick) do _
        isready(chan) || return
        payload = take!(chan)
        off(listener[])
        if payload[1] === :ok
            fit_obs[] = payload[2]
        else
            @warn "Process failed" exception=(payload[2], payload[3])
        end
        finalize!()
    end
    @async begin
        try
            put!(chan, (:ok, fetch(Threads.@spawn KJ.process!(run, m))))
        catch err
            put!(chan, (:err, err, catch_backtrace()))
        end
    end
    return
end

function build_sample_table!(mid::GridLayout, state::Observable, fig::Figure;
                             row::Int=1)
    initial = Dict{Symbol,Any}(
        :idx => [0],
        :name => ["(no data)"],
        :date => [""],
        :group => [""],
    )
    table_data = Observable(initial)
    table = Table(mid[row, 1];
        data=table_data,
        column_names=[:idx, :name, :date, :group],
        column_widths=Float32[40, 140, 180, 100],
        sortable=false,
        max_visible_rows=20,
        tellheight=false,
        valign=:top)

    # Fit `max_visible_rows` to the mid column so the table spans the full
    # figure height without leaving a big empty gap below (or overflowing).
    on(mid.layoutobservables.computedbbox; update=true) do bb
        rh  = Float64(table.row_height[])
        hh  = Float64(table.header_height[])
        h   = Float64(bb.widths[2])
        n = max(4, floor(Int, (h - hh - 8) / rh))
        table.max_visible_rows[] == n || (table.max_visible_rows[] = n)
    end

    on(state) do run
        if isnothing(run) || isempty(run)
            table_data[] = initial
            return
        end
        table_data[] = Dict{Symbol,Any}(
            :idx => collect(1:length(run)),
            :name => [s.sname for s in run],
            :date => [string(s.datetime) for s in run],
            :group => [s.group for s in run],
        )
        table.i_selected[] = 1
        table.i_selected_cell[] = (0, 0)
    end

    # User clicks only write `table.selection` (the documented output);
    # mirror them onto `i_selected` so the dashboard has a single source of truth.
    on(table.selection) do sel
        sel === nothing && return
        table.i_selected[] == sel.idx && return
        table.i_selected[] = sel.idx
    end

    return table
end

function build_count_rate_panel!(right::GridLayout,
    sample_obs::Observable,
    ytransform::Observable,
    title::Observable,
    table, state::Observable)
    ctrls = right[1, 1:2] = GridLayout()
    prev_btn = Button(ctrls[1, 1]; label="◀")
    next_btn = Button(ctrls[1, 2]; label="▶")
    # `pseudolog10` handles the zero count rates in the blank window.
    ymenu = Menu(ctrls[1, 3];
        options=zip(["log", "linear", "sqrt"],
            [Makie.pseudolog10, identity, sqrt]),
        default="log", width=110)
    Label(ctrls[1, 4], title; halign=:left, tellwidth=false)

    rowsize!(right, 1, Fixed(36))

    # `yautolimitmargin` lower bound is 0: `yscale = sqrt` inverts via
    # `square`, and a negative expanded limit raises DomainError.
    ax = Axis(right[3, 1];
        xlabel="Time [s]", ylabel="counts",
        yscale=ytransform[],
        yautolimitmargin=(0.0, 0.05),
        yticklabelspace=56.0, xticklabelspace=18.0)
    Makie.deactivate_interaction!(ax, :rectanglezoom)

    on(ytransform) do scale
        ax.yscale = scale
        reset_limits!(ax)
    end
    on(ymenu.selection) do scale
        scale === nothing || (ytransform[] = scale)
    end

    on(_ -> navigate!(table, state, -1), prev_btn.clicks)
    on(_ -> navigate!(table, state, +1), next_btn.clicks)

    return (; ax, ctrls, ymenu,
        plot_ref = Ref{Union{Nothing, Makie.AbstractPlot}}(nothing),
        right_layout = right)
end

function ensure_count_rate_plot!(panel, sample_obs::Observable, bp)
    isnothing(panel.plot_ref[]) || return
    sp = sampleplot!(panel.ax, sample_obs; fit = bp.fit_obs, method = bp.method_obs)
    # First build: seed defaults so the plot doesn't render 30 overlapping
    # channels. User picks after this are preserved for the session.
    default_channel_visibility!(sp, bp.channels_obs[],
        bp.p_channel[], bp.d_channel[], bp.sister_channel[])
    panel.plot_ref[] = sp
    return
end

"Mark channels matching the method's P/D/d roles as visible; hide the rest."
function default_channel_visibility!(sp, channel_names, p_ch, d_ch, s_ch)
    roles = (p_ch, d_ch, s_ch)
    sp.channel_visible[] = Bool[c in roles for c in channel_names]
    sp.channel_highlight[] = falses(length(channel_names))
    return
end

"""
Channels popup: lazy, rebuilt on every channels_obs change so the rows
follow the loaded data. Each row is `swatch | name | ON | HL`; defaults
to only P/D/d ON so the time-resolved plot isn't drowning in clutter.
"""
struct ChannelsPopup
    modal::Modal
    grid::GridLayout
    widgets::Vector{Makie.Block}
    sp::SamplePlot
    channels_obs::Observable{Vector{String}}
    p_channel::Observable{String}
    d_channel::Observable{String}
    sister_channel::Observable{String}
end

function build_channels_popup!(fig::Figure, sp::SamplePlot,
    channels_obs::Observable,
    p_channel::Observable, d_channel::Observable, sister_channel::Observable)
    modal = Modal(fig; min_size=(360, 200), title="Channels")
    grid = modal.layout[1, 1] = GridLayout()
    popup = ChannelsPopup(modal, grid, Makie.Block[], sp, channels_obs,
        p_channel, d_channel, sister_channel)
    rebuild!(popup)
    on(_ -> rebuild!(popup), channels_obs)
    return popup
end

function rebuild!(p::ChannelsPopup)
    delete_all!(p.widgets)
    names = collect(p.channels_obs[])
    isempty(names) && return
    cols = line_colors(p.sp.line_colormap[], length(names))
    visible = collect(p.sp.channel_visible[])
    highlight = collect(p.sp.channel_highlight[])
    # Re-seed defaults when the channel set doesn't match the new sample.
    length(visible) == length(names) ||
        (visible = Bool[n in (p.p_channel[], p.d_channel[], p.sister_channel[])
                        for n in names])
    length(highlight) == length(names) || (highlight = falses(length(names)))

    push!(p.widgets, Label(p.grid[1, 3], "ON"; fontsize=10, font=:bold))
    push!(p.widgets, Label(p.grid[1, 4], "HL"; fontsize=10, font=:bold))
    for (i, chan) in enumerate(names)
        r = i + 1
        push!(p.widgets, Box(p.grid[r, 1]; color=cols[i],
              strokevisible=false, width=14, height=14))
        push!(p.widgets, Label(p.grid[r, 2], chan; halign=:left,
              fontsize=10, tellwidth=false))
        on_cb = Checkbox(p.grid[r, 3]; checked=visible[i])
        hl_cb = Checkbox(p.grid[r, 4]; checked=highlight[i])
        on(on_cb.checked) do v
            vis = copy(p.sp.channel_visible[])
            length(vis) < i && resize!(vis, length(names))
            vis[i] = v
            p.sp.channel_visible[] = vis
        end
        on(hl_cb.checked) do v
            hl = copy(p.sp.channel_highlight[])
            length(hl) < i && resize!(hl, length(names))
            hl[i] = v
            p.sp.channel_highlight[] = hl
        end
        push!(p.widgets, on_cb, hl_cb)
    end
    Makie.GridLayoutBase.trim!(p.grid)
    rowgap!(p.grid, 2); colgap!(p.grid, 8)
    return
end

method_names() = collect(KJ._KJ["methods"].names)

function default_ions(method_name::AbstractString)
    m = KJ._KJ["methods"].dict[method_name]
    return (P=string(m.P), D=string(m.D), d=string(m.d))
end

"""
    suggest_channel_indices(method_name, channels)

Pick indices into `channels` for the parent/daughter/sister slots of
`method_name`. Tries an exact ion match first, then the first unused
channel of the same element. Falls back to any unused channel rather
than reusing one — duplicate channels would collapse the ratio plots'
series. The returned indices are ready to assign to a Menu's `i_selected`.
"""
function suggest_channel_indices(method_name::AbstractString,
    channels::AbstractVector{<:AbstractString})
    ions = default_ions(method_name)
    used = Int[]
    function pick(ion)
        for (i, c) in enumerate(channels)
            occursin(ion, c) && !(i in used) && (push!(used, i); return i)
        end
        m = match(r"^([A-Z][a-z]?)", ion)
        if !isnothing(m)
            elem = m.captures[1]
            for (i, c) in enumerate(channels)
                startswith(c, elem) && !(i in used) && (push!(used, i); return i)
            end
        end
        for i in eachindex(channels)
            !(i in used) && (push!(used, i); return i)
        end
        return firstindex(channels)
    end
    return (P=pick(ions.P), D=pick(ions.D), d=pick(ions.d))
end

function build_method(method_name::AbstractString,
    p_channel::AbstractString,
    d_channel::AbstractString,
    sister_channel::AbstractString;
    p_proxy::AbstractString="",
    d_proxy::AbstractString="",
    s_proxy::AbstractString="",
    groups::AbstractDict=Dict{String,String}(),
    roles::AbstractDict=Dict{String,Symbol}())
    ions = default_ions(method_name)
    # Manual override > `KJ.channel2proxy` inference > role's default ion.
    pair(ion, ch, manual) = KJ.Pairing(ion=ion,
        proxy=isempty(manual) ? something(KJ.channel2proxy(ch), ion) : manual,
        channel=ch)
    role_of(g) = get(roles, g, :standard)
    fractionation = Set{String}(g for g in keys(groups) if role_of(g) == :standard)
    mass_bias     = Set{String}(g for g in keys(groups) if role_of(g) == :massbias)
    method = KJ.Gmethod(name=method_name,
        groups=Dict{String,String}(groups),
        standards=fractionation,
        P=pair(ions.P, p_channel,      p_proxy),
        D=pair(ions.D, d_channel,      d_proxy),
        d=pair(ions.d, sister_channel, s_proxy))
    if !isempty(mass_bias)
        try
            KJ.Calibration!(method; standards=mass_bias)
        catch err
            @warn "Mass-bias calibration setup failed" exception=err
        end
    end
    return method
end

"Marker option that switches the dashboard from Gmethod to Cmethod mode."
const CONCENTRATION_OPTION = "Concentration"

"""
Abstract supertype for the bottom panel. Only exists to break a circular
type reference: `BottomPanel` needs to hold a `Ref{Union{Nothing,AddRatioPopup}}`
(so `popup_ref` is typed) while `AddRatioPopup` / `MethodPopup` need a
back-reference to their owning panel (so `bp` is typed). Since concrete
struct field types must be resolved at definition time, one side of the
cycle must be nominal — this abstract type. Callers always see the
concrete `BottomPanel`; dispatch on `bp::BottomPanel` still works because
`BottomPanel <: BottomPanelBase`.
"""
abstract type BottomPanelBase end

set_block_visible!(b, v) = (b.blockscene.visible[] = v; nothing)

"Delete every widget tracked in `xs` (each element is a `Block` or a tuple of
`Block`s) and empty the vector. Popup `rebuild!`s always do this pair together
before repopulating."
function delete_all!(xs::AbstractVector)
    for x in xs
        x isa Tuple ? foreach(delete!, x) : delete!(x)
    end
    empty!(xs)
end
# Axes have two scenes (blockscene + scene); hide both.
set_block_visible!(ax::Axis, v) =
    (ax.blockscene.visible[] = v; ax.scene.visible[] = v; nothing)

"""
"Add ratio plot" popup: two-column N/D picker. N is multi-select, D is
radio. Owns just data — the channel-name observable, the three role
observables (P/D/S) used to pre-check the default rows on rebuild, and
a back-reference to `BottomPanel` so Apply can call `add_def!(bp, ns, d)`
through the dispatched API.
"""
struct AddRatioPopup
    modal::Modal
    apply_btn::Makie.Button
    cancel_btn::Makie.Button
    n_boxes::Vector{Makie.Checkbox}
    d_boxes::Vector{Makie.Checkbox}
    row_labels::Vector{Makie.Label}
    content::GridLayout
    channels_obs::Observable{Vector{String}}
    p_channel::Observable{String}
    d_channel::Observable{String}
    sister_channel::Observable{String}
    bp::BottomPanelBase
end

"Default (N-set, D) pair — pre-checks P + sister in the N column and
the daughter in the D column when the popup opens."
function default_rows(p::AddRatioPopup)
    ns = Set{String}()
    isempty(p.p_channel[])       || push!(ns, p.p_channel[])
    isempty(p.sister_channel[])  || push!(ns, p.sister_channel[])
    return (ns, p.d_channel[])
end

function build_add_ratio_popup!(fig::Figure, channels_obs::Observable, bp,
    p_channel::Observable, d_channel::Observable, sister_channel::Observable)
    modal = Modal(fig; title="Add ratio plot", min_size=(320, 200))

    content = modal.layout[1, 1] = GridLayout()
    Label(content[1, 1], "Channel"; halign=:left, fontsize=11,
        font=:bold, tellwidth=false)
    Label(content[1, 2], "N"; fontsize=11, font=:bold)
    Label(content[1, 3], "D"; fontsize=11, font=:bold)
    colsize!(content, 2, Fixed(28))
    colsize!(content, 3, Fixed(28))
    colgap!(content, 8)

    footer = modal.layout[2, 1] = GridLayout()
    apply_btn  = Button(footer[1, 1]; label="Apply",  width=80)
    cancel_btn = Button(footer[1, 2]; label="Cancel", width=80)
    Label(footer[1, 3], ""; tellwidth=false)
    colgap!(footer, 8)
    rowsize!(modal.layout, 2, Fixed(36))

    popup = AddRatioPopup(modal, apply_btn, cancel_btn,
        Makie.Checkbox[], Makie.Checkbox[], Makie.Label[],
        content, channels_obs, p_channel, d_channel, sister_channel, bp)
    rebuild!(popup)
    on(_ -> rebuild!(popup), channels_obs)

    on(apply_btn.clicks) do _
        isopen(modal) || return
        chans = channels_obs[]
        ns, d = String[], ""
        for (i, ch) in enumerate(chans)
            i <= length(popup.n_boxes) && popup.n_boxes[i].checked[] && push!(ns, ch)
            i <= length(popup.d_boxes) && popup.d_boxes[i].checked[] && (d = ch)
        end
        (isempty(ns) || isempty(d)) && return
        add_def!(popup.bp, ns, d)
        close!(modal)
    end
    on(cancel_btn.clicks) do _
        isopen(modal) || return
        close!(modal)
    end
    return popup
end

function rebuild!(p::AddRatioPopup)
    delete_all!(p.n_boxes)
    delete_all!(p.d_boxes)
    delete_all!(p.row_labels)
    chans = p.channels_obs[]
    isempty(chans) && return
    default_ns, default_d = default_rows(p)
    for (i, ch) in enumerate(chans)
        r = i + 1
        lbl = Label(p.content[r, 1], ch;
            halign=:left, fontsize=10, tellwidth=false)
        ncb = Checkbox(p.content[r, 2]; checked=(ch in default_ns))
        dcb = Checkbox(p.content[r, 3]; checked=(ch == default_d))
        on(dcb.checked) do v
            v || return
            for (j, ob) in enumerate(p.d_boxes)
                j != i && ob.checked[] && (ob.checked[] = false)
            end
        end
        push!(p.n_boxes, ncb); push!(p.d_boxes, dcb); push!(p.row_labels, lbl)
    end
    rowgap!(p.content, 2)
    return
end

open_with_defaults!(p::AddRatioPopup) = (rebuild!(p); open!(p.modal); p)

"""
Method-picker popup. Every field is data — layouts/widgets, the
channels/method/proxy observables it reads from and writes back into,
and reentrancy guards. All behavior (`rebuild_chan_rows!`, `set_role!`,
`apply_method_defaults!`, `refresh_proxy_menu!`, `open_with_defaults!`)
lives in free functions below that dispatch on `MethodPopup`.

`bp` is the `BottomPanel` — Apply calls `commit_method!(bp, …)` through
the dispatched API instead of a stored callback.
"""
struct MethodPopup
    modal::Modal
    selected_idx::Observable
    role_P::Observable{Int}
    role_D::Observable{Int}
    role_d::Observable{Int}
    # Populated for Gmethod popups only (empty dicts for Cmethod).
    role_menus::Dict{Symbol, Makie.Menu}
    method_buttons::Vector{Makie.Button}
    proxy_menus::Dict{Symbol, Makie.Menu}
    # Populated for Cmethod popups only.
    internal_menu::Union{Nothing, Makie.Menu}
    apply_btn::Makie.Button
    cancel_btn::Makie.Button
    methods::Vector{String}
    method_choice::Observable{String}
    channels_obs::Observable{Vector{String}}
    p_channel::Observable{String}
    d_channel::Observable{String}
    sister_channel::Observable{String}
    p_proxy::Observable{String}
    d_proxy::Observable{String}
    sister_proxy::Observable{String}
    setting_roles::Base.RefValue{Bool}
    setting_proxy::Base.RefValue{Bool}
    bp::BottomPanelBase
    is_cmethod::Bool
end

const METHOD_ROLES = ("—", "P", "D", "d")

function element_of(ion::AbstractString)
    m = match(r"^([A-Z][a-z]?)", ion)
    return isnothing(m) ? "" : m.captures[1]
end

function isotope_options(element::AbstractString)
    isos = get(KJ._KJ["nuclides"], element, Int[])
    return [string(element, n) for n in isos]
end

function infer_proxy(channel::AbstractString, default_ion::AbstractString)
    isempty(channel) && return default_ion
    p = KJ.channel2proxy(channel)
    return isnothing(p) ? default_ion : p
end

"Set the role's channel by index (1-based into channels_obs).
i==0 clears the selection."
function set_role!(m::MethodPopup, i::Int, ion_role::Symbol)
    menu = m.role_menus[ion_role]
    m.setting_roles[] = true
    try
        i == 0 ? (menu.i_selected[] = 0) : (menu.i_selected[] = i)
    finally
        m.setting_roles[] = false
    end
end

function apply_method_defaults!(m::MethodPopup, mname::AbstractString)
    chans = m.channels_obs[]
    isempty(chans) && return
    if mname == CONCENTRATION_OPTION
        set_role!(m, 0, :P); set_role!(m, 0, :D); set_role!(m, 0, :d)
        return
    end
    sug = suggest_channel_indices(mname, chans)
    set_role!(m, sug.P, :P)
    set_role!(m, sug.D, :D)
    set_role!(m, sug.d, :d)
end

function refresh_proxy_menu!(m::MethodPopup, ion_role::Symbol, role_obs::Observable)
    midx = m.selected_idx[]
    midx === nothing && return
    mname = m.methods[midx]
    mname == CONCENTRATION_OPTION && return
    ions = default_ions(mname)
    ion = getproperty(ions, ion_role)
    element = element_of(ion)
    opts = isotope_options(element)
    isempty(opts) && (opts = [ion])
    chans = m.channels_obs[]
    i = role_obs[]
    ch = (i == 0 || i > length(chans)) ? "" : chans[i]
    inferred = infer_proxy(ch, ion)
    sel_idx = something(findfirst(==(inferred), opts), 1)
    menu = m.proxy_menus[ion_role]
    m.setting_proxy[] = true
    try
        menu.options[] = opts
        menu.i_selected[] = sel_idx
    finally
        m.setting_proxy[] = false
    end
end

function open_with_defaults!(m::MethodPopup)
    chans = m.channels_obs[]
    isempty(chans) && return m
    midx = findfirst(==(m.method_choice[]), m.methods)
    if !isnothing(midx) && midx != m.selected_idx[]
        m.selected_idx[] = midx     # fires apply_method_defaults! via on(selected_idx)
    elseif !m.is_cmethod
        apply_method_defaults!(m, m.method_choice[])
    end
    if !m.is_cmethod && m.method_choice[] != CONCENTRATION_OPTION
        for (ch_obs, sym) in ((m.p_channel, :P),
                              (m.d_channel, :D),
                              (m.sister_channel, :d))
            ch = ch_obs[]
            isempty(ch) && continue
            i = findfirst(==(ch), chans)
            isnothing(i) || set_role!(m, i, sym)
        end
        for (proxy_obs, sym) in ((m.p_proxy, :P), (m.d_proxy, :D),
                                 (m.sister_proxy, :d))
            pr = proxy_obs[]
            isempty(pr) && continue
            opts = m.proxy_menus[sym].options[]
            pi = findfirst(==(pr), opts)
            isnothing(pi) || begin
                m.setting_proxy[] = true
                try
                    m.proxy_menus[sym].i_selected[] = pi
                finally
                    m.setting_proxy[] = false
                end
            end
        end
    end
    # Seed the internal-standard picker for Cmethod from `bp.internal_menu`
    # so re-opening the popup shows the current choice.
    if m.is_cmethod && !isnothing(m.internal_menu)
        cur = m.bp.internal_menu.selection[]
        if cur isa AbstractString && !isempty(m.internal_menu.options[])
            i = findfirst(==(cur), m.internal_menu.options[])
            isnothing(i) || (m.internal_menu.i_selected[] = i)
        end
    end
    open!(m.modal)
    return m
end

"""
Method-selection popup: decay-system buttons on the left; the right pane
holds EITHER the P/D/d role grid (Gmethod) OR the internal-standard
picker (Cmethod), depending on `for_cmethod`. The popup is rebuilt from
scratch every time it opens so switching between Gmethod ↔ Cmethod
doesn't leak stale widgets — Modal-hosted Menus don't hide reliably.

Apply commits through `commit_method!(bp, …)`; clicking a method button
whose type differs from the popup's build type closes and reopens the
popup fresh (handled by the caller in `ensure_method_popup!`).
"""
function build_method_popup!(fig::Figure, bp; for_cmethod::Bool)
    modal = Modal(fig; title="Method",
                  min_size=for_cmethod ? (500, 220) : (540, 260))
    methods = [method_names(); CONCENTRATION_OPTION]

    initial_choice = for_cmethod ? CONCENTRATION_OPTION : bp.method_choice[]
    selected_idx = Observable(findfirst(==(initial_choice), methods))
    left_pane = modal.layout[1, 1] = GridLayout()
    method_buttons = Makie.Button[]
    for (i, m) in enumerate(methods)
        bcolor = lift(s -> i == s ? RGBf(0.78, 0.85, 1.0) : RGBf(0.96, 0.96, 0.96),
                      selected_idx)
        push!(method_buttons,
            Button(left_pane[i, 1]; label=m, width=90, height=28,
                                    buttoncolor=bcolor))
    end

    right_pane = modal.layout[1, 2] = GridLayout()

    role_P = Observable(0)
    role_D = Observable(0)
    role_d = Observable(0)
    role_labels = Dict{Symbol,Makie.Label}()
    role_menus  = Dict{Symbol,Makie.Menu}()
    proxy_menus = Dict{Symbol,Makie.Menu}()
    proxy_labels = Dict{Symbol,Makie.Label}()
    internal_menu_pop = nothing

    if for_cmethod
        conc_grid = right_pane[1, 1] = GridLayout()
        Label(conc_grid[1, 1], "Internal standard:";
            halign=:right, fontsize=12, font=:bold, tellwidth=true)
        internal_menu_pop = Menu(conc_grid[1, 2];
            options=collect(bp.channels_obs[]), default=nothing, width=200)
        Label(conc_grid[2, 1:2],
            "The isotope you'll use to normalise counts to concentrations. " *
            "One measurement typically has a well-known concentration in the RM " *
            "(e.g. Al27 in NIST612 = 11167 ppm).";
            halign=:left, justification=:left, fontsize=9,
            color=RGBf(0.35, 0.35, 0.35), word_wrap=true, tellwidth=false)
        colgap!(conc_grid, 10); rowgap!(conc_grid, 8)
        colsize!(conc_grid, 2, Fixed(200))
    else
        # One row per P/D/d role: channel picker + proxy-isotope override.
        role_grid = right_pane[1, 1] = GridLayout()
        for (row, role_obs, ion_role) in ((1, role_P, :P), (2, role_D, :D), (3, role_d, :d))
            role_labels[ion_role] = Label(role_grid[row, 1],
                lift(selected_idx) do midx
                    midx === nothing && return "$(ion_role): —"
                    mname = methods[midx]
                    mname == CONCENTRATION_OPTION && return ""
                    ion = getproperty(default_ions(mname), ion_role)
                    return "$(ion_role)  =  $ion   ←"
                end;
                halign=:right, fontsize=12, font=:bold, tellwidth=true)
            role_menus[ion_role] = Menu(role_grid[row, 2];
                options=collect(bp.channels_obs[]), default=nothing,
                width=200, searchable=true)
            proxy_labels[ion_role] = Label(role_grid[row, 3], "proxy:";
                halign=:right, fontsize=10, tellwidth=true,
                color=RGBf(0.4, 0.4, 0.4))
            proxy_menus[ion_role] = Menu(role_grid[row, 4]; options=String["—"],
                default=nothing, width=100, fontsize=10)
        end
        colgap!(role_grid, 10); rowgap!(role_grid, 8)
        colsize!(role_grid, 2, Fixed(200))
        colsize!(role_grid, 4, Fixed(100))

        Label(right_pane[2, 1],
            "Proxy = the isotope actually measured for each role. " *
            "Auto-inferred from channel names — override when the CSV " *
            "header lacks the mass number (e.g. \"ch1\", \"175\").";
            halign=:left, justification=:left, fontsize=9,
            color=RGBf(0.35, 0.35, 0.35), word_wrap=true, tellwidth=false)
        rowsize!(right_pane, 2, Fixed(42))

        # Role-menu → role_P/D/d wiring. i_selected on the Menu is the index
        # into channels_obs, which matches role_*_[]'s semantics exactly.
        for (ion_role, role_obs) in ((:P, role_P), (:D, role_D), (:d, role_d))
            on(role_menus[ion_role].i_selected) do i
                role_obs[] = isnothing(i) ? 0 : i
            end
        end
    end

    footer = modal.layout[2, 1:2] = GridLayout()
    apply_btn  = Button(footer[1, 1]; label="Apply",  width=80)
    cancel_btn = Button(footer[1, 2]; label="Cancel", width=80)
    Label(footer[1, 3], ""; tellwidth=false)
    colgap!(footer, 8)
    rowsize!(modal.layout, 2, Fixed(36))
    colsize!(modal.layout, 1, Fixed(110))

    popup = MethodPopup(modal, selected_idx, role_P, role_D, role_d,
        role_menus, method_buttons, proxy_menus, internal_menu_pop,
        apply_btn, cancel_btn,
        methods, bp.method_choice, bp.channels_obs,
        bp.p_channel, bp.d_channel, bp.sister_channel,
        bp.p_proxy, bp.d_proxy, bp.sister_proxy,
        Ref(false), Ref(false), bp, for_cmethod)

    # A method-button click that would switch types (Gmethod ↔ Cmethod)
    # closes the popup — the caller reopens a fresh popup of the right
    # type. Same-type clicks just update selected_idx.
    for (i, btn) in enumerate(method_buttons)
        on(btn.clicks) do _
            isopen(modal) || return
            picked_is_conc = methods[i] == CONCENTRATION_OPTION
            if picked_is_conc != for_cmethod
                bp.method_choice[] = methods[i]  # so next open builds correct type
                close!(modal)
            else
                selected_idx[] = i
            end
        end
    end

    if !for_cmethod
        on(selected_idx) do i
            i === nothing && return
            apply_method_defaults!(popup, methods[i])
        end
        for (role_obs, sym) in ((role_P, :P), (role_D, :D), (role_d, :d))
            on(_ -> refresh_proxy_menu!(popup, sym, role_obs), role_obs)
        end
        on(selected_idx) do _
            for (role_obs, sym) in ((role_P, :P), (role_D, :D), (role_d, :d))
                refresh_proxy_menu!(popup, sym, role_obs)
            end
        end
        on(bp.channels_obs) do _
            midx = selected_idx[]
            midx === nothing || apply_method_defaults!(popup, methods[midx])
        end
    end

    on(apply_btn.clicks) do _
        isopen(modal) || return
        midx = something(selected_idx[], 0)
        midx == 0 && return
        mname = methods[midx]
        chans = bp.channels_obs[]
        if for_cmethod
            # Mirror the popup's internal-standard pick into
            # `bp.internal_menu`; `rebuild_method!` will read from there.
            sel = internal_menu_pop.selection[]
            if sel isa AbstractString && sel in bp.internal_menu.options[]
                bp.internal_menu.i_selected[] =
                    something(findfirst(==(sel), bp.internal_menu.options[]), 1)
            end
            commit_method!(bp, mname, "", "", "")
        else
            (role_P[] == 0 || role_D[] == 0 || role_d[] == 0) && return
            p_pr = something(proxy_menus[:P].selection[], "")
            d_pr = something(proxy_menus[:D].selection[], "")
            s_pr = something(proxy_menus[:d].selection[], "")
            commit_method!(bp, mname,
                chans[role_P[]], chans[role_D[]], chans[role_d[]];
                p_pr=String(p_pr), d_pr=String(d_pr), s_pr=String(s_pr))
        end
        close!(modal)
    end
    on(cancel_btn.clicks) do _
        isopen(modal) || return
        close!(modal)
    end

    return popup
end

"""
One "+ Add ratio plot" Apply. Bundles N numerators against one denominator
and renders as either one shared Axis (Combined mode) or N stacked X-linked
Axes (Split). Every field is populated at construction inside `add_def!`
and never reassigned.
"""
struct RatioSlot
    numerators::Observable{Vector{String}}
    denominator::Observable{String}
    slot_layout::GridLayout
    axes::Vector{Axis}
    plots::Vector{RatioPlot}
    close_btn::Makie.Button
    legends::Vector{Makie.Legend}
    ax::Axis
end

function build_bottom_panel!(right::GridLayout,
    sample_obs::Observable,
    state::Observable,
    method::Observable,
    method_choice::Observable,
    group_rm_assignments::Observable,
    group_roles::Observable,
    fig::Figure,
    count_rate_ax::Makie.Axis,
    ytransform::Observable,
    fit_obs::Observable)
    ctrls = right[4, 1:2] = GridLayout()
    internal_label = Label(ctrls[1, 1], "Internal standard"; halign=:right, tellwidth=true)
    internal_menu = Menu(ctrls[1, 2]; options=["(internal)"], width=150)
    Label(ctrls[1, 3], ""; tellwidth=false)
    colgap!(ctrls, 8)
    rowsize!(right, 4, Fixed(0))

    section = right[2, 1] = GridLayout()
    bar        = section[1, 1] = GridLayout()
    ratio_grid = section[2, 1] = GridLayout()
    rowsize!(section, 1, Fixed(36))

    add_btn   = Button(bar[1, 1]; label="+ Add ratio plot", width=160)
    mode_menu = Menu(bar[1, 2]; options=["Combined", "Split"],
                     default="Combined", width=110)
    Label(bar[1, 3], ""; tellwidth=false)
    colgap!(bar, 8)

    p_channel      = Observable("")
    d_channel      = Observable("")
    sister_channel = Observable("")
    p_proxy        = Observable("")
    d_proxy        = Observable("")
    sister_proxy   = Observable("")

    channels_obs = Observable(String[]; ignore_equal_values = true)
    on(sample_obs) do samp
        isnothing(samp) && return
        channels_obs[] = KJ.getChannels(samp)
    end

    bp = BottomPanel(fig, right, ctrls, section, ratio_grid, count_rate_ax,
        internal_label, internal_menu, add_btn, mode_menu,
        method_choice, p_channel, d_channel, sister_channel,
        p_proxy, d_proxy, sister_proxy,
        sample_obs, state, method, fit_obs, channels_obs,
        group_rm_assignments, group_roles, ytransform,
        RatioSlot[],
        Observable(0),
        Ref{Union{Nothing,AddRatioPopup}}(nothing),
        Ref(false), Ref(false), Ref(false))

    relayout_section!(bp)

    on(mode_menu.selection) do _
        bp.mode_initialized[] || return
        switch_mode!(bp)
    end
    bp.mode_initialized[] = true

    on(add_btn.clicks) do _
        isempty(bp.channels_obs[]) && return
        open_with_defaults!(ensure_popup!(bp))
    end

    onany((_...) -> rebuild_method!(bp),
        group_rm_assignments, group_roles,
        p_channel, d_channel, sister_channel,
        p_proxy, d_proxy, sister_proxy)

    on(method_choice) do sel
        sel === nothing && return
        bp.popup_committing[] && return
        # Old fit references the old method's anchors (e.g. Hogsbo for
        # Lu-Hf); leaving it around crashes `KJ.predict` under the new
        # method.
        bp.fit_obs[] = nothing
        samp = bp.sample_obs[]
        if sel != CONCENTRATION_OPTION && !isnothing(samp)
            chans = KJ.getChannels(samp)
            sug = suggest_channel_indices(sel, chans)
            bp.suppressing[] = true
            bp.p_channel[]      = chans[sug.P]
            bp.d_channel[]      = chans[sug.D]
            bp.sister_channel[] = chans[sug.d]
            bp.suppressing[] = false
        end
        rebuild_method!(bp)
    end

    on(internal_menu.selection) do _
        method_choice[] == CONCENTRATION_OPTION && rebuild_method!(bp)
    end

    return bp
end

"""
Bottom-panel state. Every field is data — layouts, widgets, observables,
and reentrancy guards. Behavior lives in free functions below that
dispatch on `BottomPanel`, so nothing captured-in-a-closure gets smuggled
back into the struct.

`conc_blocks` exposes the internal-standard label/menu pair for the
Cmethod row that `refresh_config_group!` collapses/uncollapses.
"""
struct BottomPanel <: BottomPanelBase
    fig::Figure
    right_layout::GridLayout
    ctrls::GridLayout
    section::GridLayout
    ratio_grid::GridLayout
    count_rate_ax::Makie.Axis
    internal_label::Makie.Label
    internal_menu::Makie.Menu
    add_btn::Makie.Button
    mode_menu::Makie.Menu
    method_choice::Observable{String}
    p_channel::Observable{String}
    d_channel::Observable{String}
    sister_channel::Observable{String}
    p_proxy::Observable{String}
    d_proxy::Observable{String}
    sister_proxy::Observable{String}
    sample_obs::Observable{Union{Nothing, KJ.Sample}}
    state_obs::Observable{Union{Nothing, Vector{KJ.Sample}}}
    method_obs::Observable{Union{Nothing, KJ.KJmethod}}
    fit_obs::Observable{Union{Nothing, KJ.Gfit, KJ.Cfit}}
    channels_obs::Observable{Vector{String}}
    group_rm_assignments::Observable{Dict{String,String}}
    group_roles::Observable{Dict{String,Symbol}}
    ytransform::Observable{Function}
    ratio_defs::Vector{RatioSlot}
    defs_version::Observable{Int}
    popup_ref::Base.RefValue{Union{Nothing,AddRatioPopup}}
    suppressing::Base.RefValue{Bool}
    popup_committing::Base.RefValue{Bool}
    mode_initialized::Base.RefValue{Bool}
end

conc_blocks(bp::BottomPanel) = (bp.internal_label, bp.internal_menu)

"Ratio-plot controls that only apply to Gmethods (+ Add ratio plot, Combined/Split)."
ratio_controls(bp::BottomPanel) = (bp.add_btn, bp.mode_menu)

is_combined(bp::BottomPanel) = bp.mode_menu.selection[] == "Combined"

function make_ratio_axis!(bp::BottomPanel, parent)
    ax = Axis(parent;
        ylabel = "ratio",
        yscale = bp.ytransform[],
        yautolimitmargin = (0.0, 0.05),
        yticklabelspace = 42.0,
        xlabelvisible = false,
        xticklabelsvisible = false,
        xticksvisible = false)
    Makie.deactivate_interaction!(ax, :rectanglezoom)
    on(bp.ytransform) do scale
        ax.yscale = scale
        reset_limits!(ax)
    end
    return ax
end

"Collapse the ratio section to just the +Add bar when empty,
otherwise size to fit the axes stack (capped)."
function relayout_section!(bp::BottomPanel)
    bar_h, plot_h, section_max = 36, 240, 520
    n_axes = isempty(bp.ratio_defs) ? 0 : sum(length(s.axes) for s in bp.ratio_defs)
    h = n_axes == 0 ? bar_h : min(bar_h + n_axes * plot_h, section_max)
    rowsize!(bp.right_layout, 2, Fixed(h))
end

function relink_xaxes!(bp::BottomPanel)
    isempty(bp.ratio_defs) && return
    all_axes = Axis[]
    for s in bp.ratio_defs, ax in s.axes
        push!(all_axes, ax)
    end
    Makie.linkxaxes!(bp.count_rate_ax, all_axes...)
end

function add_def!(bp::BottomPanel, ns::Vector{String}, dch::String)
    isempty(ns) && return
    nums = Observable(copy(ns))
    den  = Observable(dch)

    i = length(bp.ratio_defs) + 1
    slot_layout = bp.ratio_grid[i, 1] = GridLayout()

    axes = Axis[]
    plots = RatioPlot[]
    legends = Makie.Legend[]

    if is_combined(bp)
        ax = make_ratio_axis!(bp, slot_layout[1, 1])
        push!(axes, ax)
        palette = Makie.categorical_colors(:tab10, 10)
        for (j, n) in enumerate(ns)
            color = palette[mod1(j, length(palette))]
            p = ratioplot!(ax, bp.sample_obs;
                numerators = Observable([n]),
                denominator = den,
                line_color = color,
                fit = bp.fit_obs, method = bp.method_obs)
            push!(plots, p)
        end
        plot_handles, labels = Any[], String[]
        for p in plots, line in Makie.get_plots(p)
            hasproperty(line, :label) || continue
            lbl = line.label[]
            (lbl isa AbstractString && !isempty(lbl)) || continue
            push!(plot_handles, line); push!(labels, lbl)
        end
        if !isempty(plot_handles)
            push!(legends, axislegend(ax, plot_handles, labels;
                position = :lt, framevisible = false,
                labelsize = 8, padding = (4, 4, 2, 2)))
        end
    else
        for (j, n) in enumerate(ns)
            ax = make_ratio_axis!(bp, slot_layout[j, 1])
            push!(axes, ax)
            p = ratioplot!(ax, bp.sample_obs;
                numerators = Observable([n]),
                denominator = den,
                fit = bp.fit_obs, method = bp.method_obs)
            push!(plots, p)
            if n != dch
                push!(legends, axislegend(ax;
                    position = :lt, framevisible = false,
                    labelsize = 8, padding = (4, 4, 2, 2)))
            end
        end
        length(axes) >= 2 && Makie.linkxaxes!(axes...)
    end

    close_btn = Button(slot_layout[1, 1];
        label = "×", width = 20, height = 20, fontsize = 14,
        halign = :right, valign = :top,
        tellwidth = false, tellheight = false)

    def = RatioSlot(nums, den, slot_layout, axes, plots,
                    close_btn, legends, first(axes))
    push!(bp.ratio_defs, def)

    on(close_btn.clicks) do _
        remove_def!(bp, def)
    end

    for ax in axes
        autolimits!(ax)
        register_outlier_toggle!(ax, bp.sample_obs)
    end
    relink_xaxes!(bp)
    relayout_section!(bp)
    bp.defs_version[] = bp.defs_version[] + 1
    return def
end

function teardown_slot!(d)
    delete_all!(d.legends)
    delete!(d.close_btn)
    delete_all!(d.axes)
    Makie.GridLayoutBase.remove_from_gridlayout!(
        Makie.GridLayoutBase.gridcontent(d.slot_layout))
end

function teardown_defs!(bp::BottomPanel)
    for d in bp.ratio_defs; teardown_slot!(d); end
    empty!(bp.ratio_defs)
    trim!(bp.ratio_grid)
end

"Tear down every slot and re-add each `(numerators, denominator)` pair
in the current mode. Used by both `remove_def!` (survivors = all but
`def`) and `switch_mode!` (survivors = all)."
function rebuild_from!(bp::BottomPanel, survivors::AbstractVector)
    teardown_defs!(bp)
    for (ns, dch) in survivors
        add_def!(bp, ns, dch)
    end
    relayout_section!(bp)
end

function remove_def!(bp::BottomPanel, def)
    isnothing(findfirst(d -> d === def, bp.ratio_defs)) && return
    survivors = [(d.numerators[], d.denominator[])
                 for d in bp.ratio_defs if d !== def]
    rebuild_from!(bp, survivors)
    bp.defs_version[] = bp.defs_version[] + 1
end

"Snapshot every slot's (numerators, denominator), tear down, re-add
in the current mode."
function switch_mode!(bp::BottomPanel)
    survivors = [(d.numerators[], d.denominator[]) for d in bp.ratio_defs]
    rebuild_from!(bp, survivors)
end

function ensure_popup!(bp::BottomPanel)
    isnothing(bp.popup_ref[]) || return bp.popup_ref[]
    bp.popup_ref[] = build_add_ratio_popup!(bp.fig, bp.channels_obs, bp,
        bp.p_channel, bp.d_channel, bp.sister_channel)
    return bp.popup_ref[]
end

function rebuild_method!(bp::BottomPanel)
    bp.suppressing[] && return
    sel = bp.method_choice[]
    if sel == CONCENTRATION_OPTION
        run = bp.state_obs[]
        isnothing(run) && return
        ich = bp.internal_menu.selection[]
        internal = ich isa AbstractString ? (ich, nothing) : (nothing, nothing)
        bp.method_obs[] = KJ.Cmethod(run;
                                     internal=internal,
                                     groups=bp.group_rm_assignments[])
    else
        P_ch, D_ch, d_ch = bp.p_channel[], bp.d_channel[], bp.sister_channel[]
        (isempty(P_ch) || isempty(D_ch) || isempty(d_ch)) && return
        bp.method_obs[] = build_method(sel, P_ch, D_ch, d_ch;
                                p_proxy=bp.p_proxy[],
                                d_proxy=bp.d_proxy[],
                                s_proxy=bp.sister_proxy[],
                                groups=bp.group_rm_assignments[],
                                roles=bp.group_roles[])
    end
end

"Atomic method commit: write channels + proxies in one go and fire a
single `rebuild_method!`, bypassing the per-channel auto-resuggest that
`on(method_choice)` runs on unrelated method-name changes. Empty proxy
strings fall back to `KJ.channel2proxy` name inference."
function commit_method!(bp::BottomPanel, mname::AbstractString,
                        p::AbstractString, d::AbstractString, s::AbstractString;
                        p_pr::AbstractString="",
                        d_pr::AbstractString="",
                        s_pr::AbstractString="")
    bp.suppressing[] = true
    if mname != CONCENTRATION_OPTION
        bp.p_channel[]      = p
        bp.d_channel[]      = d
        bp.sister_channel[] = s
        bp.p_proxy[]        = p_pr
        bp.d_proxy[]        = d_pr
        bp.sister_proxy[]   = s_pr
    end
    bp.popup_committing[] = true
    bp.method_choice[] = mname
    bp.popup_committing[] = false
    bp.suppressing[] = false
    rebuild_method!(bp)
end

"Show the internal-standard row in Cmethod mode, collapse it otherwise."
function refresh_config_group!(panel)
    is_conc = panel.method_choice[] == CONCENTRATION_OPTION
    # The internal-standard picker moved into the Method popup, so the
    # main-dashboard row stays collapsed regardless of method.
    rowsize!(panel.right_layout, 4, Fixed(0))
    for b in conc_blocks(panel)
        set_block_visible!(b, false)
    end
    for b in ratio_controls(panel)
        set_block_visible!(b, !is_conc)
    end
    return
end

"Collapse the ratio stack for Cmethods; restore it for Gmethods."
function apply_mode_layout!(panel::BottomPanel, m)
    if m isa KJ.Cmethod
        rowsize!(panel.right_layout, 2, Fixed(0))
    else
        relayout_section!(panel)
    end
    return
end

function ensure_ratio_plot!(panel, sample_obs::Observable, samp::KJ.Sample)
    chans = KJ.getChannels(samp)
    # Seed channels from method defaults on first sample load.
    if isempty(panel.p_channel[]) || isempty(panel.d_channel[]) ||
       isempty(panel.sister_channel[])
        sel = panel.method_choice[]
        gname = sel == CONCENTRATION_OPTION ? "Lu-Hf" : sel
        sug = suggest_channel_indices(gname, chans)
        panel.p_channel[]      = chans[sug.P]
        panel.d_channel[]      = chans[sug.D]
        panel.sister_channel[] = chans[sug.d]
    end
    if panel.internal_menu.options[] == ["(internal)"]
        panel.internal_menu.options[] = chans
    end
    return
end

function build_biplot_panel!(right::GridLayout, sample_obs::Observable,
    p_channel::Observable, d_channel::Observable, sister_channel::Observable)
    # Row 5 is the panel strip; biplot sits in row 6.
    plots = right[6, 1:2] = GridLayout()
    xlabel_obs = lift((p, d) -> isempty(p) || isempty(d) ? "P / D" :
                                "$p / $d", p_channel, d_channel)
    ylabel_obs = lift((s, d) -> isempty(s) || isempty(d) ? "S / D" :
                                "$s / $d", sister_channel, d_channel)
    ax = Axis(plots[1, 1]; title="Isochron",
              xlabel=xlabel_obs, ylabel=ylabel_obs,
              xautolimitmargin=(0.0, 0.05),
              yautolimitmargin=(0.0, 0.05),
              yticklabelspace=42.0, xticklabelspace=18.0)
    Makie.deactivate_interaction!(ax, :rectanglezoom)
    # Spinner overlays the same cell — GridLayout allows co-tenancy, and
    # the Spinner's `visible=false` collapses its plot to nothing when idle.
    spinner = Makie.Spinner(plots[1, 1]; message = "Processing…",
        fontsize = 24)
    return (; ax, spinner,
        plot_ref            = Ref{Union{Nothing, Makie.AbstractPlot}}(nothing),
        concordia_line_ref  = Ref{Union{Nothing, Makie.AbstractPlot}}(nothing),
        concordia_notice_ref = Ref{Union{Nothing, Makie.AbstractPlot}}(nothing),
        right_layout = right,
        p_channel, d_channel, sister_channel)
end

"Drag target — one concrete subtype per grabbable handle. `drag_to!`,
`hover_x`, `hover_color` and `nearest_window_edge`'s edge iteration
dispatch on these instead of the caller checking a `.kind` symbol."
abstract type DragTarget end

"Blank or signal window edge — shared shape, differ only in which
window vector on `samp` they read/write."
abstract type WinEdgeDrag <: DragTarget end

struct BwinDrag <: WinEdgeDrag
    win_idx::Int
    side::Symbol   # :left or :right
end

struct SwinDrag <: WinEdgeDrag
    win_idx::Int
    side::Symbol
end

"t0 marker drag — captures the initial state so bwin/swin can shift by
the same delta the cursor moves."
struct T0Drag <: DragTarget
    anchor_row::Int
    bwin_anchor::Vector{Tuple{Int,Int}}
    swin_anchor::Vector{Tuple{Int,Int}}
end

# Window accessors on the sample — the whole reason Bwin/Swin need to
# be distinct types. Everything else is shared via `WinEdgeDrag`.
windows(samp, ::BwinDrag) = samp.bwin
windows(samp, ::SwinDrag) = samp.swin
set_windows!(samp, ::BwinDrag, w) = KJ.setBwin!(samp, w)
set_windows!(samp, ::SwinDrag, w) = KJ.setSwin!(samp, w)

hover_color(::BwinDrag) = RGBAf(0.2, 0.5, 1.0, 0.95)
hover_color(::SwinDrag) = RGBAf(1.0, 0.55, 0.1, 0.95)
hover_color(::T0Drag)   = RGBAf(0.4, 0.4, 0.4, 0.95)

function hover_x(samp, d::WinEdgeDrag)
    wins = windows(samp, d)
    idx = d.side === :left ? wins[d.win_idx][1] : wins[d.win_idx][2]
    return Float64(samp.dat[idx, 1])
end
hover_x(samp, ::T0Drag) = Float64(samp.t0)

"Nearest row in `samp.dat`'s time column to data x-coord `cx`.
Alloc-free linear scan — called per drag frame."
function nearest_row(samp, cx::Real)
    times = samp.dat[!, 1]
    x = Float64(cx)
    best_i, best_d = 1, abs(Float64(times[1]) - x)
    for i in 2:length(times)
        d = abs(Float64(times[i]) - x)
        if d < best_d
            best_i, best_d = i, d
        end
    end
    return best_i
end

"Find the closest grab handle to data x-coord `cx`, or `nothing` if none
is within `tol`."
function nearest_window_edge(samp, cx::Real, tol::Real)
    times = samp.dat[!, 1]
    best::Union{Nothing,DragTarget} = nothing
    best_d = tol
    for (T, wins) in ((BwinDrag, samp.bwin), (SwinDrag, samp.swin))
        for (i, w) in enumerate(wins)
            a, b = w[1], w[2]
            (a < 1 || b > length(times) || a > b) && continue
            d = abs(Float64(times[a]) - cx)
            if d <= best_d
                best, best_d = T(i, :left), d
            end
            d = abs(Float64(times[b]) - cx)
            if d <= best_d
                best, best_d = T(i, :right), d
            end
        end
    end
    d = abs(Float64(samp.t0) - cx)
    if d <= best_d
        best, best_d = T0Drag(nearest_row(samp, Float64(samp.t0)),
                              collect(samp.bwin), collect(samp.swin)), d
    end
    return best
end

"Update the dragged edge from cursor data-x. Returns `true` iff the row
actually changed — the caller uses that to skip a needless `notify`."
function drag_to!(samp, d::WinEdgeDrag, cx::Real)
    row = nearest_row(samp, cx)
    wins = windows(samp, d)
    old_a, old_b = wins[d.win_idx][1], wins[d.win_idx][2]
    new_a, new_b = d.side === :left ?
        (min(row, old_b - 1), old_b) :
        (old_a, max(row, old_a + 1))
    (new_a, new_b) == (old_a, old_b) && return false
    new_wins = collect(wins)
    new_wins[d.win_idx] = (new_a, new_b)
    set_windows!(samp, d, new_wins)
    return true
end

"Append a new `(row, row+1)` segment to `samp.bwin`/`samp.swin`.
Returns a `WinEdgeDrag` targeting the new segment's right edge so the
calling drag handler can grow it live from the cursor."
function append_window!(samp, kind::Symbol, cx::Real)
    n = nrow(samp.dat)
    row = clamp(nearest_row(samp, cx), 1, n - 1)
    if kind === :bwin
        new_wins = collect(samp.bwin)
        push!(new_wins, (row, row + 1))
        KJ.setBwin!(samp, new_wins)
        return BwinDrag(length(new_wins), :right)
    else
        new_wins = collect(samp.swin)
        push!(new_wins, (row, row + 1))
        KJ.setSwin!(samp, new_wins)
        return SwinDrag(length(new_wins), :right)
    end
end

function drag_to!(samp, d::T0Drag, cx::Real)
    row = nearest_row(samp, cx)
    row == nearest_row(samp, Float64(samp.t0)) && return false
    n = nrow(samp.dat)
    delta = row - d.anchor_row
    new_bwin = [(clamp(a, 1, n), clamp(b + delta, a + 1, n))
                for (a, b) in d.bwin_anchor]
    new_swin = [(clamp(a + delta, 1, n - 1), clamp(b, a + delta + 1, n))
                for (a, b) in d.swin_anchor]
    KJ.setBwin!(samp, new_bwin)
    KJ.setSwin!(samp, new_swin)
    KJ.sett0!(samp, Float64(samp.dat[row, 1]))
    return true
end

"""
    register_window_drag!(panel, sample_obs)

Drag the bwin/swin edges — and the t0 marker — on the count-rate axis.
Mutations go through `KJ.setBwin!`/`setSwin!`/`sett0!` and a
`notify(sample_obs)` fans the update to every `vspan!` / `vlines!`
driven by `samp.bwin`/`samp.swin`/`samp.t0`.

Ctrl-drag from empty space in the axis creates a new sub-window (kind
= bwin if left of t0, swin otherwise) and continues as a right-edge
drag on the new segment.
"""
function register_window_drag!(panel, sample_obs::Observable)
    ax = panel.ax
    active_target = Ref{Union{Nothing,DragTarget}}(nothing)

    edge_xs = lift(sample_obs) do samp
        isnothing(samp) && return Float64[]
        times = samp.dat[!, 1]
        n = length(times)
        out = Float64[]
        for w in (samp.bwin..., samp.swin...)
            (w[1] < 1 || w[2] > n) && continue
            push!(out, Float64(times[w[1]]), Float64(times[w[2]]))
        end
        return out
    end
    vlines!(ax, edge_xs; color = (:black, 0.4), linewidth = 1)

    hover_xs = Observable(Float64[])
    hover_color_obs = Observable(RGBAf(0, 0, 0, 0))
    vlines!(ax, hover_xs; color = hover_color_obs, linewidth = 4)

    function set_hover!(samp, target)
        if isnothing(target)
            isempty(hover_xs[]) || (hover_xs[] = Float64[])
            return
        end
        hover_color_obs[] = hover_color(target)
        hover_xs[]        = [hover_x(samp, target)]
    end

    Makie.register_interaction!(ax, :window_drag) do ev::MouseEvent, _
        samp = sample_obs[]
        isnothing(samp) && return Consume(false)
        tol = 0.01 * ax.finallimits[].widths[1]

        if ev.type === MouseEventTypes.over && isnothing(active_target[])
            set_hover!(samp, nearest_window_edge(samp, ev.data[1], tol))
            return Consume(false)
        elseif ev.type === MouseEventTypes.leftdragstart
            ctrl = Makie.ispressed(ax, Makie.Keyboard.left_control) ||
                   Makie.ispressed(ax, Makie.Keyboard.right_control)
            if ctrl
                kind = ev.data[1] < Float64(samp.t0) ? :bwin : :swin
                active_target[] = append_window!(samp, kind, ev.data[1])
                notify(sample_obs)
                set_hover!(samp, active_target[])
                return Consume(true)
            end
            target = nearest_window_edge(samp, ev.data[1], tol)
            isnothing(target) && return Consume(false)
            active_target[] = target
            set_hover!(samp, target)
            return Consume(true)
        elseif ev.type === MouseEventTypes.leftdrag
            target = active_target[]
            isnothing(target) && return Consume(false)
            if drag_to!(samp, target, ev.data[1])
                notify(sample_obs)
                set_hover!(samp, target)
            end
            return Consume(true)
        elseif ev.type === MouseEventTypes.leftdragstop
            isnothing(active_target[]) && return Consume(false)
            active_target[] = nothing
            set_hover!(samp, nearest_window_edge(samp, ev.data[1], tol))
            return Consume(true)
        end
        return Consume(false)
    end
    return
end

"""
    register_outlier_toggle!(panel, sample_obs, method, fit_obs)

Double-click a scatter point on the biplot to flip its `outlier` flag.
The recipes read `samp.dat.outlier` directly, so `notify(sample_obs)`
after the flip refreshes every panel.

Scatter index → `samp.dat` row: in processed mode (Gmethod + fit) the
scatter iterates over `swinData(samp)` so `k` maps via
`windows2selection(samp.swin)[k]`; in raw mode `k` is the row directly.
"""
function register_outlier_toggle!(panel, sample_obs::Observable,
                                  method::Observable, fit_obs::Observable)
    Makie.register_interaction!(panel.ax, :toggle_outlier) do ev::MouseEvent, _
        ev.type === MouseEventTypes.leftdoubleclick || return Consume(false)
        plot = panel.plot_ref[]
        (isnothing(plot) || isnothing(sample_obs[])) && return Consume(false)
        xs, ys = plot.xs[], plot.ys[]
        isempty(xs) && return Consume(false)

        lims = panel.ax.finallimits[]
        wx, wy = lims.widths
        cx, cy = ev.data[1], ev.data[2]
        best_k, best_d2 = 0, Inf
        for k in eachindex(xs)
            x, y = xs[k], ys[k]
            (isnan(x) || isnan(y)) && continue
            d2 = ((x - cx)/wx)^2 + ((y - cy)/wy)^2
            if d2 < best_d2
                best_k, best_d2 = k, d2
            end
        end
        best_k == 0 && return Consume(false)

        samp = sample_obs[]
        is_processed = !isnothing(fit_obs[]) && method[] isa KJ.Gmethod
        row = if is_processed
            sel, _, _ = KJ.windows2selection(samp.swin)
            best_k <= length(sel) ? sel[best_k] : 0
        else
            best_k
        end
        (row == 0 || row > nrow(samp.dat)) && return Consume(false)
        hasproperty(samp.dat, :outlier) ||
            (samp.dat.outlier = falses(nrow(samp.dat)))
        samp.dat.outlier[row] = !samp.dat.outlier[row]
        notify(sample_obs)
        return Consume(true)
    end
    return
end

"Double-click a raw-time axis (count-rate or ratio) to toggle the
nearest sample row's `outlier` flag. Time-axis version — recipes read
`samp.dat.outlier` so `notify(sample_obs)` refreshes every panel."
function register_outlier_toggle!(ax::Axis, sample_obs::Observable)
    Makie.register_interaction!(ax, :toggle_outlier_time) do ev::MouseEvent, _
        ev.type === MouseEventTypes.leftdoubleclick || return Consume(false)
        samp = sample_obs[]
        isnothing(samp) && return Consume(false)
        row = nearest_row(samp, ev.data[1])
        hasproperty(samp.dat, :outlier) ||
            (samp.dat.outlier = falses(nrow(samp.dat)))
        samp.dat.outlier[row] = !samp.dat.outlier[row]
        notify(sample_obs)
        return Consume(true)
    end
    return
end

"Build the isochron `biplot` (P/D vs S/D) on first sample load."
function ensure_biplot!(panel, sample_obs::Observable,
    method::Observable, fit_obs::Observable)
    isnothing(panel.plot_ref[]) || return
    panel.plot_ref[] = biplot!(panel.ax, sample_obs;
        x_numerator=panel.p_channel,
        y_numerator=panel.sister_channel,
        denominator=panel.d_channel,
        method=method, fit=fit_obs)
    return
end

"""
    apply_concordia_overlay!(panel, plot_type, method)

When `plot_type == "Concordia"` and `method` is the U-Pb `Gmethod`, draw the
Tera-Wasserburg concordia curve parametric in `t` on the biplot axes:

    x(t) = 1 / (exp(L8·t) − 1)               (²³⁸U / ²⁰⁶Pb)
    y(t) = U58 · (exp(L5·t) − 1) / (exp(L8·t) − 1)   (²⁰⁷Pb / ²⁰⁶Pb)

For any other method, draw a "requires U-Pb" notice instead. Always
clears the previous overlay first.
"""
function apply_concordia_overlay!(panel, plot_type::AbstractString,
                                  method)
    # Clear any prior overlay before redrawing. `delete!` is (ax, plot).
    if !isnothing(panel.concordia_line_ref[])
        delete!(panel.ax, panel.concordia_line_ref[])
        panel.concordia_line_ref[] = nothing
    end
    if !isnothing(panel.concordia_notice_ref[])
        delete!(panel.ax, panel.concordia_notice_ref[])
        panel.concordia_notice_ref[] = nothing
    end
    panel.ax.title[] = plot_type == "Concordia" ? "Concordia" : "Isochron"
    plot_type == "Concordia" || return
    # Concordia only makes sense for U-Pb (Tera-Wasserburg form here).
    is_upb = method isa KJ.Gmethod && method.name == "U-Pb"
    if !is_upb
        panel.concordia_notice_ref[] = text!(panel.ax,
            "Concordia requires the U-Pb method";
            position=Point2f(0.5, 0.5), space=:relative,
            align=(:center, :center), fontsize=12, color=:gray)
        return
    end
    L5, L8, U58 = KJ.UPb_helper()
    # Sample `t` so `x(t)` spans the visible range; cap `xmax > 0` to avoid
    # `log(1 + 1/0)`. `tmax = 4500 Ma` is older than Earth.
    xlims = panel.ax.finallimits[]
    xmax = max(xlims.widths[1], 1.0)
    tmin = log(1 + 1/xmax) / L8
    tmax = 4500.0
    ts = range(tmin, tmax; length=200)
    xs = Float32.(1 ./ (exp.(L8 .* ts) .- 1))
    ys = Float32.(U58 .* (exp.(L5 .* ts) .- 1) ./ (exp.(L8 .* ts) .- 1))
    panel.concordia_line_ref[] = lines!(panel.ax, xs, ys;
        color=:black, linewidth=1.5,
        label="Concordia")
    return
end

"""
Group-assignment business logic. Owns the sample-run observable, the
method/assignment observables the picker writes into, and the
`lcs_done_for_rm` gate for the one-shot longest-common-prefix
sibling-bulk-tag. The `GroupPicker` popup holds a reference to a
`GroupState` and calls `assign_group!(gs, rm, row)` on click.
"""
struct GroupState
    state_obs::Observable
    method_choice::Observable{String}
    group_rm_assignments::Observable
    lcs_done_for_rm::Set{String}
end

GroupState(state_obs, method_choice, group_rm_assignments) =
    GroupState(state_obs, method_choice, group_rm_assignments, Set{String}())

"""
Apply a picker choice: `(sample)` clears the row's group (and every
sibling in the same group); an RM name tags the row and, on the SECOND
assignment of that RM, bulk-tags every sibling whose sample name shares
the LCS prefix.
"""
function assign_group!(gs::GroupState, rm::AbstractString, row)
    (isnothing(row) || !(row isa Integer)) && return
    run = gs.state_obs[]
    (isnothing(run) || row == 0 || row > length(run)) && return
    target = run[row]
    old_group = target.group
    if rm == "(sample)"
        if old_group != "sample"
            for s in run
                s.group == old_group && (s.group = "sample")
            end
        else
            target.group = "sample"
        end
    else
        other = nothing
        for s in run
            s.group == rm && s !== target && (other = s; break)
        end
        if isnothing(other)
            target.group = rm
            delete!(gs.lcs_done_for_rm, rm)
        elseif rm in gs.lcs_done_for_rm
            target.group = rm
        else
            push!(gs.lcs_done_for_rm, rm)
            pref = group_prefix(target.sname, other.sname)
            target.group = rm
            isempty(pref) || for s in run
                startswith(s.sname, pref) && (s.group = rm)
            end
        end
    end
    if old_group != "sample" && !any(s -> s.group == old_group, run)
        delete!(gs.lcs_done_for_rm, old_group)
    end
    sync_assignments_from_groups!(gs.group_rm_assignments, run, gs.method_choice[])
    notify(gs.state_obs)
end

"""
Group-picker popup: one button per RM (plus a "(sample)" reset). The
`owner::GroupState` receives the pick via `assign_group!(owner, rm, ctx)`
where `ctx` is the target row index stored on `target_ctx` at open time.
"""
struct GroupPicker
    modal::Modal
    rm_buttons::Vector{Makie.Button}
    target_ctx::Base.RefValue{Union{Nothing,Int}}
    owner::GroupState
end

function build_group_picker_popup!(fig::Figure, owner::GroupState)
    # The sample being assigned goes in the title: the header doesn't
    # scroll, so it stays visible when a long RM list overflows the body.
    # Auto height, capped so long RM lists (U-Pb has 27) scroll instead of
    # running off the figure.
    modal = Modal(fig; min_size=(360, 80), max_size=(360, PICKER_MAX_HEIGHT),
                  title="Assign group")

    picker = GroupPicker(modal, Makie.Button[],
        Base.RefValue{Union{Nothing,Int}}(nothing), owner)
    rebuild!(picker)
    on(_ -> rebuild!(picker), owner.method_choice)
    return picker
end

function rebuild!(p::GroupPicker)
    opts = String["(sample)"]
    for rm in rm_options_for(p.owner.method_choice[])
        rm == RM_NONE || push!(opts, rm)
    end
    empty!(p.rm_buttons)
    replace_content!(p.modal) do sf
        for (i, opt) in enumerate(opts)
            btn = Button(sf.layout[i, 1]; label=opt,
                         width=RM_BUTTON_WIDTH, height=RM_BUTTON_HEIGHT)
            on(btn.clicks) do _
                isopen(p.modal) || return
                assign_group!(p.owner, opt, p.target_ctx[])
                close!(p.modal)
            end
            push!(p.rm_buttons, btn)
        end
        rowgap!(sf.layout, RM_BUTTON_GAP)
    end
    return
end

function open_with_defaults!(p::GroupPicker, sname::AbstractString,
                             current_group::AbstractString, ctx::Integer)
    p.modal.title = "$sname  →  (now: $current_group)"
    p.target_ctx[] = Int(ctx)
    open!(p.modal)
end

"""
Rebuild `group → RM` from `samp.group` (which IS the RM name when not
"sample"). Entries not in the current method's RM list are dropped.
"""
function sync_assignments_from_groups!(assignments::Observable,
    run::AbstractVector{<:KJ.Sample}, method_name::AbstractString)
    opts = Set(rm_options_for(method_name))
    new_assigns = Dict{String,String}()
    for s in run
        s.group == "sample" && continue
        s.group in opts && (new_assigns[s.group] = s.group)
    end
    new_assigns == assignments[] || (assignments[] = new_assigns)
end

"""
Fuzzy-match `group` to the best RM in `options`. Exact lowercased match
wins; otherwise the longest two-way prefix overlap of ≥ 3 characters
wins. Returns `RM_NONE` if nothing qualifies.
"""
function autopreselect_rm(group::AbstractString, options::AbstractVector)
    g = lowercase(group)
    best = RM_NONE
    best_len = 0
    for opt in options
        opt == RM_NONE && continue
        o = lowercase(opt)
        g == o && return opt
        if (startswith(g, o) || startswith(o, g)) && length(o) >= 3
            if length(o) > best_len
                best = opt
                best_len = length(o)
            end
        end
    end
    return best
end

"""
References popup: one row per detected group with an RM dropdown
(auto-preselected via `autopreselect_rm`) and a role dropdown. Mutations
apply directly to `assignments` / `roles`.
"""
struct ReferencesPopup
    modal::Modal
    container::GridLayout
    rm_menus::Vector{Makie.Menu}
    role_menus::Vector{Makie.Menu}
    labels::Vector{Makie.Label}
    state::Observable{Union{Nothing, Vector{KJ.Sample}}}
    method_choice::Observable{String}
    assignments::Observable{Dict{String,String}}
    roles::Observable{Dict{String,Symbol}}
end

function build_references_popup!(fig::Figure,
    state::Observable, method_choice::Observable,
    assignments::Observable, roles::Observable)
    modal = Modal(fig; title="References", min_size=(360, 200))
    container = modal.layout[1, 1] = GridLayout()
    popup = ReferencesPopup(modal, container,
        Makie.Menu[], Makie.Menu[], Makie.Label[],
        state, method_choice, assignments, roles)
    rebuild!(popup)
    onany((_...) -> rebuild!(popup), state, method_choice)
    return popup
end

function rebuild!(p::ReferencesPopup)
    delete_all!(p.rm_menus)
    delete_all!(p.role_menus)
    delete_all!(p.labels)
    run = p.state[]
    isnothing(run) && return
    groups = sort(unique(s.group for s in run))
    opts = rm_options_for(p.method_choice[])

    # Drop assignments not valid for the new method, then auto-preselect
    # any still-unassigned groups.
    current_assigns = copy(p.assignments[])
    changed = false
    for g in collect(keys(current_assigns))
        current_assigns[g] in opts || (delete!(current_assigns, g); changed = true)
    end
    for g in groups
        get(current_assigns, g, RM_NONE) == RM_NONE || continue
        suggested = autopreselect_rm(g, opts)
        suggested == RM_NONE || (current_assigns[g] = suggested; changed = true)
    end
    changed && (p.assignments[] = current_assigns)

    # `sample` catch-all is intentionally skipped — no RM/role to configure.
    configurable = filter(!=("sample"), groups)
    push!(p.labels, Label(p.container[1, 1], "Group";
        halign=:left, fontsize=10, font=:bold, tellwidth=true))
    push!(p.labels, Label(p.container[1, 2], "Reference material";
        halign=:left, fontsize=10, font=:bold, tellwidth=false))
    push!(p.labels, Label(p.container[1, 3], "Role";
        halign=:left, fontsize=10, font=:bold, tellwidth=false))
    for (i, g) in enumerate(configurable)
        r = i + 1
        push!(p.labels, Label(p.container[r, 1], g;
            halign=:left, fontsize=10, tellwidth=true))
        current = get(p.assignments[], g, RM_NONE)
        idx = something(findfirst(==(current), opts), 1)
        rm_menu = Menu(p.container[r, 2]; options=opts, default=idx, width=140,
                       searchable=true)
        role_default = get(ROLE_LABEL_OF, get(p.roles[], g, :standard),
                           ROLE_DEFAULT_LABEL)
        role_idx = something(findfirst(==(role_default), ROLE_LABELS), 1)
        role_menu = Menu(p.container[r, 3];
            options=ROLE_LABELS, default=role_idx, width=120)
        on(rm_menu.selection) do sel
            sel === nothing && return
            d = copy(p.assignments[])
            sel == RM_NONE ? delete!(d, g) : (d[g] = sel)
            p.assignments[] = d
        end
        on(role_menu.selection) do sel
            sel === nothing && return
            rs = copy(p.roles[])
            rs[g] = ROLE_SYMS[sel]
            p.roles[] = rs
        end
        push!(p.rm_menus, rm_menu)
        push!(p.role_menus, role_menu)
    end
    colgap!(p.container, 12); rowgap!(p.container, 4)
    return
end

open_with_defaults!(p::ReferencesPopup) = (rebuild!(p); open!(p.modal); p)

function navigate!(table, state::Observable, delta::Int)
    run = state[]
    (isnothing(run) || isempty(run)) && return
    cur = table.i_selected[]
    cur == 0 && (cur = 1)
    table.i_selected[] = mod1(cur + delta, length(run))
    # Programmatic move: clear cell selection so the row highlight follows.
    table.i_selected_cell[] = (0, 0)
    return
end

function pick_folder()
    path = Ref(Ptr{UInt8}())
    r = @ccall Makie.NativeFileDialog_jll.libnfd.NFD_PickFolder(
        C_NULL::Ptr{Cchar}, path::Ref{Ptr{UInt8}})::Cint
    r == 1 ? unsafe_string(path[]) : nothing
end

function infer_format(dir::AbstractString, current::AbstractString)
    isdir(dir) || return current
    files = try
        readdir(dir)
    catch e
        e isa Union{Base.IOError,SystemError} || rethrow()
        return current
    end
    any(endswith(".FIN"), files) && return "FIN2"
    # .csv can be either Agilent or ThermoFisher; keep the current pick.
    return current
end

function load_path!(state::Observable, path::AbstractString,
    format::AbstractString)
    if !isdir(path)
        @warn "not a directory" path
        return
    end
    run = try
        KJ.load(path; format=format)
    catch err
        @warn "load failed" exception = err
        return
    end
    state[] = run
    return
end

function load_folder!(state::Observable, format_menu::Makie.Menu,
                      pathbox_label::Makie.Label, picked::AbstractString,
                      default_format::AbstractString)
    fmt = infer_format(picked, something(format_menu.selection[], default_format))
    fmt == format_menu.selection[] || (format_menu.i_selected[] =
        something(findfirst(==(fmt), DATA_FORMATS), 1))
    pathbox_label.text[] = basename(rstrip(picked, '/'))
    load_path!(state, picked, String(fmt))
    return
end

"""
Longest common prefix of `a` and `b` with trailing digits stripped.
Powers the group picker's second-pick auto-expansion: `"BP - 01"` and
`"BP - 02"` → `"BP - "`, which then matches every `BP - NN`.
"""
function group_prefix(a::AbstractString, b::AbstractString)
    buf = IOBuffer()
    for (c1, c2) in zip(a, b)
        c1 == c2 || break
        write(buf, c1)
    end
    s = String(take!(buf))
    while !isempty(s) && isdigit(s[end])
        s = s[1:prevind(s, lastindex(s))]
    end
    return s
end

"Sentinel value in RM dropdowns for an unassigned group."
const RM_NONE = "(none)"

const RM_BUTTON_HEIGHT = 26
const RM_BUTTON_WIDTH = 200
const RM_BUTTON_GAP = 2
"Cap on the group picker's body; longer RM lists scroll."
const PICKER_MAX_HEIGHT = 560

"""
Reference materials known to KJ for the given method.
`CONCENTRATION_OPTION` uses the glass set; everything else maps to the
per-decay-system table in `KJ._KJ["refmat"]`. The first entry is always
`RM_NONE`.
"""
function rm_options_for(method_name::AbstractString)
    method_name == CONCENTRATION_OPTION &&
        return [RM_NONE; collect(KJ._KJ["glass"].names)]
    haskey(KJ._KJ["refmat"], method_name) || return [RM_NONE]
    return [RM_NONE; collect(KJ._KJ["refmat"][method_name].names)]
end

# Per-group role:
#   :standard → `method.standards` (fractionation),
#   :massbias → `method.bias.standards` via `KJ.Calibration!`,
#   :none     → RM-tagged but excluded from calibration.
const ROLE_LABELS = ["Standard", "Mass bias", "None"]
const ROLE_SYMS = Dict("Standard" => :standard,
                       "Mass bias" => :massbias,
                       "None"      => :none)
const ROLE_LABEL_OF = Dict(:standard => "Standard",
                           :massbias => "Mass bias",
                           :none     => "None")
const ROLE_DEFAULT_LABEL = "Standard"

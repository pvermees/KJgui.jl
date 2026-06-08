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
    fig = Figure(size=(1700, 1050))

    state = Observable{Union{Nothing,Vector{KJ.Sample}}}(nothing)
    ytransform = Observable{Function}(Makie.pseudolog10)
    method = Observable{Union{Nothing,KJ.KJmethod}}(nothing)
    sample_obs = Observable{Union{Nothing,KJ.Sample}}(nothing)
    # `KJ.process!` returns a Gfit (geochronology) or Cfit (concentration).
    # `nothing` until the user hits "Process data" with valid input.
    fit_obs = Observable{Any}(nothing)

    handles = build_dashboard!(fig, state, sample_obs,
        ytransform, method, fit_obs, format)

    isnothing(path) || load_path!(state, path, format)

    display(fig)
    return (; fig, state, sample_obs, ytransform, method,
        fit=fit_obs, handles...)
end

const STUB_BUTTONS = [
    "Tabulate samples",
    "Interferences", "Fractionation", "Mass bias",
    "Process data", "Export results", "Logs / templates",
    "Options", "Clear", "Exit",
]

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
    # Without Auto(false), the narrow button column dictates row height and
    # the dashboard collapses to a strip ~13 buttons tall.
    rowsize!(fig.layout, 1, Auto(false))

    method_choice = Observable("Lu-Hf")
    # Per-panel "show in layout" toggles. Each panel reads its own observable
    # and either occupies its row or collapses it via Fixed(0); biplot also
    # AND-s with `method isa Gmethod` since it makes no sense for Cmethods.
    biplot_visible = Observable(true)
    # Reference-material picks per group, e.g. Dict("NIST612p" => "NIST612").
    # Becomes `method.groups` on the next rebuild.
    group_rm_assignments = Observable(Dict{String,String}())
    # Role per group: :standard (fractionation), :massbias, or :none. Default
    # is :standard for backwards compat. Drives `method.standards` and the
    # `Calibration!` step.
    group_roles = Observable(Dict{String,Symbol}())

    pathbox = Textbox(left[1, 1]; placeholder="data folder…", width=160)
    load_btn = Button(left[2, 1]; label="Read data files", width=160)
    on(load_btn.clicks) do _
        s = pathbox.stored_string[]
        p = isnothing(s) ? "" : strip(String(s))
        isempty(p) || load_path!(state, p, default_format)
    end

    # Method selector — a single Button labelled "Method: <name>" that opens
    # a popup with a two-pane method/channel-role picker (matches the SG
    # mock-up). The Button is the only persistent affordance; the standalone
    # "Method" header label is gone since the Button itself carries the name.
    method_btn = Button(left[3, 1];
        label=lift(m -> "Method: $m", method_choice), width=160)
    # Popup is built lazily once the bot_panel exists (it owns channels_obs).
    method_popup_ref = Ref{Any}(nothing)

    # References Button — opens a popup with one row per detected group,
    # auto-preselected with the best-matching RM via fuzzy name match.
    refs_btn = Button(left[4, 1]; label="References", width=160)
    refs_popup_ref = Ref{Any}(nothing)

    # Panels section: one checkbox per optional plot. Add more rows here as
    # we grow (Concordia, count-rate variants, …); each just toggles its
    # *_visible observable and the layout collapses or restores the row.
    Label(left[5, 1], "Panels"; halign=:left, tellwidth=false)
    panels_row = left[6, 1] = GridLayout()
    biplot_cb = Checkbox(panels_row[1, 1]; checked=true)
    Label(panels_row[1, 2], "Biplot"; halign=:left, tellwidth=false)
    on(v -> (biplot_visible[] = v), biplot_cb.checked)

    process_btn = nothing
    for (i, lbl) in enumerate(STUB_BUTTONS)
        b = Button(left[6+i, 1]; label=lbl, width=160)
        if lbl == "Process data"
            process_btn = b
            on(b.clicks) do _
                run_process!(state, method, fit_obs; process_btn=process_btn)
            end
        else
            on(b.clicks) do _
                @info "not implemented yet" button = lbl
            end
        end
    end

    # The Key (channel list with ON / HL toggles) lives above the sample
    # table — frees up the right column 2 so the ratio + count-rate axes
    # can span the full plot width and stay visually aligned for axis
    # sharing. 2-column layout halves the row count, so a ~180px slot
    # is enough for the ~17-channel Lu-Hf default.
    key_slot = mid[1, 1] = GridLayout()
    rowsize!(mid, 1, Fixed(180))
    # The Table tellwidth-reports its full 460px autosize, but mid's Auto
    # column collapses to the Key's narrower 212px autosize — so the table
    # ends up squashed and mid's right edge migrates left, exposing the
    # right column's protrusion zone (which then paints over the table
    # area). Pin mid's column to the table width so both stay snug.
    colsize!(mid, 1, Fixed(460))
    table = build_sample_table!(mid, state; row=2)

    title = Observable("")
    top_panel = build_count_rate_panel!(right, sample_obs, ytransform,
        title, table, state, key_slot)
    bot_panel = build_bottom_panel!(right, sample_obs, state,
        method, method_choice,
        group_rm_assignments, group_roles, fig, top_panel.ax)
    biplot_panel = build_biplot_panel!(right, sample_obs,
        bot_panel.p_channel, bot_panel.d_channel, bot_panel.sister_channel)

    # The Key now lives in column 2 of `mid`, so the right panel uses only
    # column 1 for plots. Column 2 collapses to nothing.
    colsize!(right, 2, Fixed(0))

    # Method Button now opens a popup with method + P/D/S menus, lazily
    # constructed on first click (needs channels_obs to exist).
    function ensure_method_popup!()
        isnothing(method_popup_ref[]) || return method_popup_ref[]
        method_popup_ref[] = build_method_popup!(fig,
            method_choice, bot_panel.channels_obs,
            bot_panel.p_channel, bot_panel.d_channel, bot_panel.sister_channel,
            bot_panel.commit_method!)
        return method_popup_ref[]
    end
    on(method_btn.clicks) do _
        isempty(bot_panel.channels_obs[]) && return
        ensure_method_popup!().open_with_defaults!()
    end

    # References Button: lazy popup with auto-preselected RMs per group.
    # Built lazily so the eager rebuild! inside the popup gets the right
    # `fig` parent and an already-loaded `state` to enumerate groups.
    function ensure_refs_popup!()
        isnothing(refs_popup_ref[]) || return refs_popup_ref[]
        refs_popup_ref[] = build_references_popup!(fig,
            state, method_choice, group_rm_assignments, group_roles)
        return refs_popup_ref[]
    end
    # Build eagerly so the auto-preselect fires the first time data loads
    # (and so tests can read `refs_panel.menus[]` without opening the popup).
    refs_panel = ensure_refs_popup!()
    on(refs_btn.clicks) do _
        refs_panel.open_with_defaults!()
    end

    effective_biplot_show(m) = biplot_visible[] && !(m isa KJ.Cmethod)

    on(method) do m
        apply_mode_layout!(bot_panel, m)
        refresh_config_group!(bot_panel)
        apply_biplot_visibility!(biplot_panel, effective_biplot_show(m))
    end
    on(_ -> apply_biplot_visibility!(biplot_panel, effective_biplot_show(method[])),
       biplot_visible)
    refresh_config_group!(bot_panel)
    apply_mode_layout!(bot_panel, method[])
    apply_biplot_visibility!(biplot_panel, effective_biplot_show(method[]))

    # Raw and processed modes have very different data scales, so any
    # fit change requires re-fitting the biplot's axis limits.
    on(_ -> isnothing(biplot_panel.plot_ref[]) || autolimits!(biplot_panel.ax),
       fit_obs)

    on(table.i_selected) do i
        run = state[]
        (isnothing(run) || isempty(run) || i == 0 || i > length(run)) && return
        samp = run[i]
        sample_obs[] = samp
        title[] = "$(i)/$(length(run))  $(samp.sname)  [$(samp.group)]  ($(samp.datetime))"
        # Channel seeding first — biplot reads p/d/sister directly off
        # bot_panel; method-change handler also re-seeds them.
        ensure_ratio_plot!(bot_panel, sample_obs, samp)
        ensure_count_rate_plot!(top_panel, sample_obs)
        ensure_biplot!(biplot_panel, sample_obs, method, fit_obs)
        autolimits!(top_panel.ax)
        for def in bot_panel.ratio_defs[]
            autolimits!(def.ax)
        end
        autolimits!(biplot_panel.ax)
    end

    return (; table, top_panel, bot_panel, biplot_panel, refs_panel,
              refs_btn, refs_popup_ref,
              method_choice, method_btn, method_popup_ref, biplot_visible,
              group_rm_assignments, group_roles, process_btn)
end

# Run KJ.process! on the current run + method. Reports the usual problems
# (no data, no method, no standards assigned) instead of crashing.
# Optionally takes a `process_btn` to flip the label to "..." while the
# (synchronous and not-yet-threaded) fit is grinding away — Optim runs
# can take a few seconds, and an indication that something is happening
# is worth more than a frozen "Process data" Button.
function run_process!(state::Observable, method::Observable, fit_obs::Observable;
                      process_btn::Union{Nothing,Makie.Button}=nothing)
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
    original_label = nothing
    if !isnothing(process_btn)
        original_label = process_btn.label[]
        process_btn.label[] = "Processing…"
        # Force the renderer to pick up the label change before the
        # synchronous KJ.process! starts blocking the main thread.
        yield()
    end
    try
        fit_obs[] = KJ.process!(run, m)
        @info "Process complete" fit=typeof(fit_obs[])
    catch err
        @warn "Process failed" exception=(err, catch_backtrace())
    finally
        isnothing(process_btn) ||
            (process_btn.label[] = something(original_label, "Process data"))
    end
end

function build_sample_table!(mid::GridLayout, state::Observable; row::Int=1)
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
        max_visible_rows=28,
        tellheight=false)

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
    table, state::Observable,
    key_slot::GridLayout)
    ctrls = right[1, 1:2] = GridLayout()
    prev_btn = Button(ctrls[1, 1]; label="◀")
    next_btn = Button(ctrls[1, 2]; label="▶")
    # pseudolog10 (not log10) because blank-window count rates are zero
    # and log10 cannot represent them.
    ymenu = Menu(ctrls[1, 3];
        options=zip(["log", "linear", "sqrt"],
            [Makie.pseudolog10, identity, sqrt]),
        default="log", width=110)
    Label(ctrls[1, 4], title; halign=:left, tellwidth=false)

    rowsize!(right, 1, Fixed(36))

    # yautolimitmargin lower bound is 0: with `yscale = sqrt`, Makie inverts
    # through `square`, and a negative expanded limit raises DomainError.
    # Overview/count-rate axis lives in row 3 — ratio plots stack ABOVE it
    # (row 2) and share its x-axis via linkxaxes!. Its bottom Time [s] label
    # serves as the shared time axis for the whole plot stack.
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

    return (; ax,
        plot_ref=Ref{Any}(nothing),
        key_ref=Ref{Any}(nothing),
        right_layout=right,
        key_slot=key_slot)
end

function ensure_count_rate_plot!(panel, sample_obs::Observable)
    isnothing(panel.plot_ref[]) || return
    sp = sampleplot!(panel.ax, sample_obs)
    panel.plot_ref[] = sp
    # Key now sits above the sample table (key_slot is mid[1, 1]); no more
    # P/D/S role columns since channel roles come from the method directly.
    panel.key_ref[] = build_key!(panel.key_slot, sp)
    return
end

# Interactive legend ("Key"): per channel a colour swatch, the channel name,
# color swatch + channel name + ON (line visibility) + HL (highlight). The
# method's parent / daughter / sister channels are derived from the method's
# `suggest_channel_indices`, so no per-channel role checkboxes here.
function build_key!(gl::GridLayout, sp)
    names = collect(sp.channel_names[])
    n = length(names)
    cols = line_colors(sp.line_colormap[], n)
    visible = trues(n)
    highlight = falses(n)
    sp.channel_visible[] = collect(visible)
    sp.channel_highlight[] = collect(highlight)

    # Two side-by-side blocks of channels — each block has its own
    # color / name / ON / HL columns. With ~17 channels that's ~9+8 rows
    # per block, so the Key reads horizontally instead of stretching
    # vertically. Each block uses 4 columns: swatch | name | ON | HL.
    half = cld(n, 2)
    Label(gl[1, 1:8], "Key"; halign=:left, fontsize=11, font=:bold,
        tellwidth=false)
    on_boxes = Makie.Checkbox[]
    hl_boxes = Makie.Checkbox[]
    # Allocate by index so push! lands in channel order regardless of block.
    on_boxes_by_i = Vector{Any}(undef, n)
    hl_boxes_by_i = Vector{Any}(undef, n)
    for (block, range) in enumerate((1:half, (half+1):n))
        coff = (block - 1) * 4   # column offset for this block
        Label(gl[2, coff+3], "ON"; fontsize=9)
        Label(gl[2, coff+4], "HL"; fontsize=9)
        for (row_in_block, i) in enumerate(range)
            r = row_in_block + 2  # rows 1 = title, 2 = ON/HL header
            chan = names[i]
            Box(gl[r, coff+1]; color=cols[i], strokevisible=false,
                width=12, height=12)
            Label(gl[r, coff+2], chan; halign=:left, fontsize=9)
            on_cb = Checkbox(gl[r, coff+3]; checked=true)
            hl_cb = Checkbox(gl[r, coff+4]; checked=false)
            on(on_cb.checked) do v
                visible[i] = v
                sp.channel_visible[] = collect(visible)
            end
            on(hl_cb.checked) do v
                highlight[i] = v
                sp.channel_highlight[] = collect(highlight)
            end
            on_boxes_by_i[i] = on_cb
            hl_boxes_by_i[i] = hl_cb
        end
    end
    for i in 1:n
        push!(on_boxes, on_boxes_by_i[i])
        push!(hl_boxes, hl_boxes_by_i[i])
    end
    rowgap!(gl, 2)
    colgap!(gl, 4)
    return (; layout=gl, on_boxes, hl_boxes)
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
    groups::AbstractDict=Dict{String,String}(),
    roles::AbstractDict=Dict{String,Symbol}())
    ions = default_ions(method_name)
    pair(ion, ch) = KJ.Pairing(ion=ion,
        proxy=something(KJ.channel2proxy(ch), ion),
        channel=ch)
    role_of(g) = get(roles, g, :standard)
    fractionation = Set{String}(g for g in keys(groups) if role_of(g) == :standard)
    mass_bias     = Set{String}(g for g in keys(groups) if role_of(g) == :massbias)
    method = KJ.Gmethod(name=method_name,
        groups=Dict{String,String}(groups),
        standards=fractionation,
        P=pair(ions.P, p_channel),
        D=pair(ions.D, d_channel),
        d=pair(ions.d, sister_channel))
    if !isempty(mass_bias)
        try
            KJ.Calibration!(method; standards=mass_bias)
        catch err
            @warn "Mass-bias calibration setup failed" exception=err
        end
    end
    return method
end

# Marker option in the method dropdown that switches the dashboard from
# geochronology (Gmethod, ratio plots) to concentration mode (Cmethod).
const CONCENTRATION_OPTION = "Concentration"

set_block_visible!(b, v) = (b.blockscene.visible[] = v; nothing)
# Axes have two scenes: blockscene (frame/ticks) and scene (the plotted data).
# Lines look invisible when their row collapses to 1px, but scatter children
# still draw — so for axes we hide both.
set_block_visible!(ax::Axis, v) =
    (ax.blockscene.visible[] = v; ax.scene.visible[] = v; nothing)

# Build the "Add ratio plot" popup. Two-column N/D channel picker over the
# current run's channels: N is multi-select, D is radio-like. Apply pushes
# `(numerators, denominator)` through `on_apply`. Defaults come from the
# method's current P/D/S — provided lazily through `get_defaults`.
function build_add_ratio_popup!(fig::Figure, channels_obs::Observable,
    on_apply::Function, get_defaults::Function)
    pop = Popup(fig; size=(340, 380), title="Add ratio plot")

    # One combined grid so the Channel / N / D columns line up — header row
    # and per-channel rows share column widths automatically.
    content = pop.layout[1, 1] = GridLayout()
    pop.track!(Label(content[1, 1], "Channel"; halign=:left, fontsize=11,
        font=:bold, tellwidth=false))
    pop.track!(Label(content[1, 2], "N"; fontsize=11, font=:bold))
    pop.track!(Label(content[1, 3], "D"; fontsize=11, font=:bold))
    colsize!(content, 2, Fixed(28))
    colsize!(content, 3, Fixed(28))
    colgap!(content, 8)

    footer = pop.layout[2, 1] = GridLayout()
    apply_btn  = pop.track!(Button(footer[1, 1]; label="Apply",  width=80))
    cancel_btn = pop.track!(Button(footer[1, 2]; label="Cancel", width=80))
    pop.track!(Label(footer[1, 3], ""; tellwidth=false))
    colgap!(footer, 8)
    rowsize!(pop.layout, 2, Fixed(36))

    n_boxes, d_boxes, row_labels = Any[], Any[], Any[]

    function rebuild_rows!()
        for b in n_boxes;   delete!(b); end
        for b in d_boxes;   delete!(b); end
        for l in row_labels; delete!(l); end
        empty!(n_boxes); empty!(d_boxes); empty!(row_labels)
        chans = channels_obs[]
        isempty(chans) && return
        default_ns, default_d = get_defaults()
        for (i, ch) in enumerate(chans)
            r = i + 1   # row 1 is the header
            lbl = pop.track!(Label(content[r, 1], ch;
                halign=:left, fontsize=10, tellwidth=false))
            ncb = pop.track!(Checkbox(content[r, 2]; checked=(ch in default_ns)))
            dcb = pop.track!(Checkbox(content[r, 3]; checked=(ch == default_d)))
            # D column behaves like a radio group.
            on(dcb.checked) do v
                v || return
                for (j, ob) in enumerate(d_boxes)
                    j != i && ob.checked[] && (ob.checked[] = false)
                end
            end
            push!(n_boxes, ncb); push!(d_boxes, dcb); push!(row_labels, lbl)
        end
        rowgap!(content, 2)
    end
    on(_ -> rebuild_rows!(), channels_obs)
    rebuild_rows!()

    on(apply_btn.clicks) do _
        chans = channels_obs[]
        ns, d = String[], ""
        for (i, ch) in enumerate(chans)
            i <= length(n_boxes) && n_boxes[i].checked[] && push!(ns, ch)
            i <= length(d_boxes) && d_boxes[i].checked[] && (d = ch)
        end
        (isempty(ns) || isempty(d)) && return  # ignore invalid selection
        on_apply(ns, d)
        pop.close!()
    end
    on(_ -> pop.close!(), cancel_btn.clicks)

    return (; popup=pop, apply_btn, cancel_btn, n_boxes, d_boxes,
            open_with_defaults! = () -> (rebuild_rows!(); pop.open!()))
end

# Method-selection popup matching SG's mock-up: method list on the LEFT
# (one row per available decay system, current selection highlighted),
# every measured channel on the RIGHT with a per-row "—/P/D/d" dropdown
# (mutually exclusive — picking P on one row clears P from any other).
# The bottom of the right pane shows the resulting Pairing summary:
# `P: 176Lu  ←  Lu175 → 175`, with proxy isotope (extracted via
# `channel2proxy`) flagged when it differs from the method's default ion.
# Apply commits via `commit_method!`.
function build_method_popup!(fig::Figure,
    method_choice::Observable,
    channels_obs::Observable,
    p_channel::Observable,
    d_channel::Observable,
    sister_channel::Observable,
    commit_method!::Function)
    pop = Popup(fig; size=(560, 760), title="Method")

    methods = [method_names(); CONCENTRATION_OPTION]
    ROLES   = ("—", "P", "D", "d")

    # LEFT pane: method list. Each row is a Button; the active one is
    # highlighted via buttoncolor. Clicking a row re-suggests defaults for
    # the new method.
    selected_idx = Observable(findfirst(==(method_choice[]), methods))
    left_pane = pop.layout[1, 1] = GridLayout()
    method_buttons = Makie.Button[]
    for (i, m) in enumerate(methods)
        bcolor = lift(s -> i == s ? RGBf(0.78, 0.85, 1.0) : RGBf(0.96, 0.96, 0.96),
                      selected_idx)
        btn = pop.track!(Button(left_pane[i, 1]; label=m, width=90, height=28,
                                buttoncolor=bcolor))
        on(btn.clicks) do _
            selected_idx[] = i
        end
        push!(method_buttons, btn)
    end

    # RIGHT pane: channel rows + summary. Channel rows are rebuilt whenever
    # `channels_obs` changes; the role dropdowns drive `role_idx[]` (per
    # role: index into the channel list, 0 = unassigned).
    right_pane = pop.layout[1, 2] = GridLayout()
    chan_grid  = right_pane[1, 1] = GridLayout()
    sum_grid   = right_pane[2, 1] = GridLayout()
    rowsize!(right_pane, 2, Fixed(72))

    role_P = Observable(0)
    role_D = Observable(0)
    role_d = Observable(0)

    # Each entry: (channel_label_block, role_menu_block).
    chan_rows = Any[]

    # Programmatic role assignments (from suggestion / open_with_defaults!)
    # would otherwise re-fire the menu handler and try to "clear duplicates"
    # in the middle of a batch update.
    setting_roles = Ref(false)

    function clear_role_from_others!(role::AbstractString, keep_i::Int)
        setting_roles[] = true
        try
            for (j, (_, menu)) in enumerate(chan_rows)
                if j != keep_i && something(menu.selection[], "") == role
                    menu.i_selected[] = 1  # "—"
                end
            end
        finally
            setting_roles[] = false
        end
    end

    function rebuild_chan_rows!()
        for (lbl, menu) in chan_rows
            try; delete!(lbl);  catch; end
            try; delete!(menu); catch; end
        end
        empty!(chan_rows)
        role_P[] = role_D[] = role_d[] = 0

        chans = channels_obs[]
        isempty(chans) && return

        for (i, ch) in enumerate(chans)
            lbl  = pop.track!(Label(chan_grid[i, 1], "$(i). $ch";
                                    halign=:left, fontsize=10, tellwidth=false))
            # Compact menu — default Menu is ~32px tall which makes the
            # 18-row list overflow the popup body; force a tight height +
            # smaller font + minimal padding.
            menu = pop.track!(Menu(chan_grid[i, 2]; options=collect(ROLES),
                                   default="—", width=56, height=22,
                                   fontsize=10, textpadding=(4, 4, 2, 2)))
            on(menu.selection) do role
                setting_roles[] && return
                if role == "P"
                    role_P[] = i; clear_role_from_others!("P", i)
                elseif role == "D"
                    role_D[] = i; clear_role_from_others!("D", i)
                elseif role == "d"
                    role_d[] = i; clear_role_from_others!("d", i)
                else
                    role_P[] == i && (role_P[] = 0)
                    role_D[] == i && (role_D[] = 0)
                    role_d[] == i && (role_d[] = 0)
                end
            end
            push!(chan_rows, (lbl, menu))
        end
        rowgap!(chan_grid, 2)
    end

    function set_role!(i::Int, role::AbstractString)
        (i == 0 || i > length(chan_rows)) && return
        ri = findfirst(==(role), ROLES)
        isnothing(ri) || (chan_rows[i][2].i_selected[] = ri)
    end

    function apply_method_defaults!(mname::AbstractString)
        chans = channels_obs[]
        isempty(chans) && return
        setting_roles[] = true
        try
            # Reset all menus to "—" first
            for (_, menu) in chan_rows
                menu.i_selected[] = 1
            end
            role_P[] = role_D[] = role_d[] = 0
        finally
            setting_roles[] = false
        end
        mname == CONCENTRATION_OPTION && return
        sug = suggest_channel_indices(mname, chans)
        # Now set the suggested roles (these fire the handler, which sets
        # role_P/D/d and clears duplicates — but since others are "—", it
        # just records the index).
        set_role!(sug.P, "P")
        set_role!(sug.D, "D")
        set_role!(sug.d, "d")
    end

    on(selected_idx) do i
        i === nothing && return
        mname = methods[i]
        method_choice[] != mname && nothing  # don't push yet — Apply commits
        apply_method_defaults!(mname)
    end

    # --- Ion summary (read-only, lifted from the role observables) -------
    function summary_text(role_obs::Observable, ion_role::Symbol)
        return lift(role_obs, channels_obs, selected_idx) do i, chans, midx
            midx === nothing && return "$(ion_role): —"
            mname = methods[midx]
            mname == CONCENTRATION_OPTION && return ""
            ions = default_ions(mname)
            ion = getproperty(ions, ion_role)
            (i == 0 || i > length(chans)) && return "$(ion_role)  =  $ion  (no channel assigned)"
            ch = chans[i]
            proxy = KJ.channel2proxy(ch)
            if isnothing(proxy) || proxy == ion
                return "$(ion_role)  =  $ion       ←  $ch"
            else
                return "$(ion_role)  =  $ion  (proxy $proxy)  ←  $ch"
            end
        end
    end
    pop.track!(Label(sum_grid[1, 1], summary_text(role_P, :P);
                     halign=:left, fontsize=10, font=:bold, tellwidth=false))
    pop.track!(Label(sum_grid[2, 1], summary_text(role_D, :D);
                     halign=:left, fontsize=10, font=:bold, tellwidth=false))
    pop.track!(Label(sum_grid[3, 1], summary_text(role_d, :d);
                     halign=:left, fontsize=10, font=:bold, tellwidth=false))

    # Footer
    footer = pop.layout[2, 1:2] = GridLayout()
    apply_btn  = pop.track!(Button(footer[1, 1]; label="Apply",  width=80))
    cancel_btn = pop.track!(Button(footer[1, 2]; label="Cancel", width=80))
    pop.track!(Label(footer[1, 3], ""; tellwidth=false))
    colgap!(footer, 8)
    rowsize!(pop.layout, 2, Fixed(36))
    colsize!(pop.layout, 1, Fixed(110))

    on(apply_btn.clicks) do _
        midx = something(selected_idx[], 0)
        midx == 0 && return
        mname = methods[midx]
        chans = channels_obs[]
        if mname == CONCENTRATION_OPTION
            commit_method!(mname, "", "", "")
        else
            (role_P[] == 0 || role_D[] == 0 || role_d[] == 0) && return
            commit_method!(mname, chans[role_P[]], chans[role_D[]], chans[role_d[]])
        end
        pop.close!()
    end
    on(_ -> pop.close!(), cancel_btn.clicks)

    # Channels available on data load → rebuild + seed roles for the current
    # method. Without this the popup opens with an empty channel list before
    # the first sample is selected.
    on(channels_obs) do _
        rebuild_chan_rows!()
        midx = selected_idx[]
        midx === nothing || apply_method_defaults!(methods[midx])
    end
    rebuild_chan_rows!()

    function open_with_defaults!()
        chans = channels_obs[]
        isempty(chans) && return
        # Sync selected_idx (this fires apply_method_defaults!).
        midx = findfirst(==(method_choice[]), methods)
        if !isnothing(midx) && midx != selected_idx[]
            selected_idx[] = midx
        else
            apply_method_defaults!(method_choice[])
        end
        # Override the suggestion with the live p/d/sister_channel if the
        # current method's existing picks are still valid in the channel list.
        if method_choice[] != CONCENTRATION_OPTION
            for (ch_obs, role) in ((p_channel, "P"),
                                   (d_channel, "D"),
                                   (sister_channel, "d"))
                ch = ch_obs[]
                isempty(ch) && continue
                i = findfirst(==(ch), chans)
                isnothing(i) || set_role!(i, role)
            end
        end
        pop.open!()
    end

    return (; popup=pop, selected_idx, role_P, role_D, role_d,
            chan_rows, method_buttons, apply_btn, cancel_btn,
            open_with_defaults!)
end

function build_bottom_panel!(right::GridLayout,
    sample_obs::Observable,
    state::Observable,
    method::Observable,
    method_choice::Observable,
    group_rm_assignments::Observable,
    group_roles::Observable,
    fig::Figure,
    count_rate_ax::Makie.Axis)
    ctrls = right[4, 1:2] = GridLayout()
    # In concentration mode this row holds the internal-standard picker; in
    # geochronology mode P/D/S are picked directly from the Key (top-right)
    # as radio columns, so the row is collapsed.
    internal_label = Label(ctrls[1, 1], "Internal standard"; halign=:right, tellwidth=true)
    internal_menu = Menu(ctrls[1, 2]; options=["(internal)"], width=150)
    Label(ctrls[1, 3], ""; tellwidth=false)
    colgap!(ctrls, 8)
    rowsize!(right, 4, Fixed(0))

    # Ratio stack lives in row 2 (above the count-rate overview at row 3).
    # Inner section: "+ Add" bar on top, ratio rows below. Each ratio Axis
    # hides its own x-axis — the count-rate's bottom Time [s] axis is the
    # shared one (linkxaxes! ties them together).
    section = right[2, 1] = GridLayout()
    bar        = section[1, 1] = GridLayout()
    ratio_grid = section[2, 1] = GridLayout()
    rowsize!(section, 1, Fixed(36))

    add_btn   = Button(bar[1, 1]; label="+ Add ratio plot", width=160)
    mode_menu = Menu(bar[1, 2]; options=["Split", "Combined"],
                     default="Split", width=110)
    Label(bar[1, 3], ""; tellwidth=false)
    colgap!(bar, 8)

    # Channel-role observables — seeded by `suggest_channel_indices` on
    # method change. The biplot reads these directly.
    p_channel      = Observable("")
    d_channel      = Observable("")
    sister_channel = Observable("")

    # Channels available in the current sample. Drives the popup's row count.
    channels_obs = Observable(String[])
    on(sample_obs) do samp
        isnothing(samp) && return
        channels_obs[] = KJ.getChannels(samp)
    end

    # Ratio definitions — each is a NamedTuple
    # (numerators::Observable{Vector{String}}, denominator::Observable{String},
    #  ax::Axis, plot, close_btn).
    ratio_defs = Ref{Vector{Any}}(Any[])
    # Bumped on every add/remove so external listeners (the unified Legend
    # above the table) can refresh.
    defs_version = Observable(0)

    function relink_xaxes!()
        defs = ratio_defs[]
        # Always link to the count-rate (overview) axis — even with zero
        # ratio plots there's nothing to do, but with ≥1 we link them all
        # so they share the count-rate's bottom Time [s] axis.
        isempty(defs) && return
        try
            Makie.linkxaxes!(count_rate_ax, [d.ax for d in defs]...)
        catch err
            @warn "linkxaxes failed" exception=err
        end
    end

    # The ratio stack lives in `right[2, 1]` (above the count-rate overview).
    # With 0 plots it collapses to just the "+ Add" bar (~36px). With ≥1
    # plots its height scales with N, capped so the overview keeps room.
    # In Cmethod mode `apply_mode_layout!` overrides this to Fixed(0).
    BAR_H       = 36
    PLOT_H_1    = 240   # height for a single ratio plot
    SECTION_MAX = 520   # ceiling for the whole stack
    function relayout_section!()
        n = length(ratio_defs[])
        h = n == 0 ? BAR_H : min(BAR_H + n * PLOT_H_1, SECTION_MAX)
        rowsize!(right, 2, Fixed(h))
    end

    function add_def!(ns::Vector{String}, dch::String)
        i = length(ratio_defs[]) + 1
        # Ratio Axis occupies the full grid cell so its left/right edges
        # line up with the count-rate overview below (axis sharing only
        # *looks* shared if the axes also line up visually).
        ax = Axis(ratio_grid[i, 1];
            ylabel = "ratio",
            yautolimitmargin=(0.0, 0.05),
            yticklabelspace=42.0,
            # Hidden x-axis: the count-rate overview below provides the
            # single shared Time [s] axis for the whole stack.
            xlabelvisible=false,
            xticklabelsvisible=false,
            xticksvisible=false)
        Makie.deactivate_interaction!(ax, :rectanglezoom)

        # × close button overlays the axis at top-right; legend moves to
        # top-left so they don't collide. Same pattern axislegend uses:
        # bbox tracks the axis viewport, halign/valign position the
        # Button inside it. No grid cell, so the Axis keeps full width
        # and lines up with the count-rate Axis below.
        close_btn = Button(ax.parent; label="×",
            width=20, height=20, fontsize=14,
            bbox = ax.scene.viewport,
            halign = :right, valign = :top,
            tellwidth = false, tellheight = false)
        # Each ratio row claims equal share of the section's leftover
        # height (axes are tellheight=false, so default Auto shrinks to 0).
        rowsize!(ratio_grid, i, Auto(false, 1.0))

        nums = Observable(copy(ns))
        den  = Observable(dch)
        plot_h = ratioplot!(ax, sample_obs;
            numerators=nums, denominator=den)
        leg = axislegend(ax; position=:lt, framevisible=false,
            labelsize=8, padding=(4, 4, 2, 2))

        def = (; numerators=nums, denominator=den, ax, close_btn,
                 plot=plot_h, legend=leg)
        push!(ratio_defs[], def)

        on(close_btn.clicks) do _
            remove_def!(def)
        end

        autolimits!(ax)
        relink_xaxes!()
        relayout_section!()
        defs_version[] = defs_version[] + 1
        return def
    end

    function remove_def!(def)
        idx = findfirst(d -> d === def, ratio_defs[])
        isnothing(idx) && return
        # Snapshot survivors before we delete blocks (they hold observables
        # that we need to copy).
        survivors = [(d.numerators[], d.denominator[]) for d in ratio_defs[] if d !== def]
        # Tear down all current defs (delete! frees layout cells + observers).
        # Legend must go too — otherwise the deleted axis's axislegend stays
        # floating in figure space (it lives in ax.parent, not the cell).
        for d in ratio_defs[]
            try; delete!(d.legend);    catch; end
            try; delete!(d.close_btn); catch; end
            try; delete!(d.ax);        catch; end
        end
        empty!(ratio_defs[])
        # trim! removes empty trailing rows so old rowsize!(..., Auto(false, 1))
        # bindings on orphaned rows don't keep claiming vertical space.
        trim!(ratio_grid)
        # Re-create the survivors so their ratio_grid rows are contiguous.
        for (ns, dch) in survivors
            add_def!(ns, dch)
        end
        relayout_section!()
        defs_version[] = defs_version[] + 1
    end

    # Popup is created lazily once channels are known.
    popup_ref = Ref{Any}(nothing)
    function ensure_popup!()
        isnothing(popup_ref[]) || return popup_ref[]
        get_defaults = () -> begin
            ns = Set{String}()
            isempty(p_channel[]) || push!(ns, p_channel[])
            isempty(sister_channel[]) || push!(ns, sister_channel[])
            return (ns, d_channel[])
        end
        popup_ref[] = build_add_ratio_popup!(fig, channels_obs,
            (ns, dch) -> add_def!(ns, dch),
            get_defaults)
        return popup_ref[]
    end

    on(add_btn.clicks) do _
        isempty(channels_obs[]) && return
        ensure_popup!().open_with_defaults!()
    end

    on(mode_menu.selection) do sel
        sel == "Combined" && @info "Combined view mode coming in a follow-up; \
            currently always Split"
    end

    # Apply the empty-state row size right now so the section collapses to
    # just the bar instead of claiming a full Auto() share of the right panel.
    relayout_section!()

    # Block channel-observable callbacks while we programmatically reseed
    # all three (on method change), so rebuild_method! fires once at the end.
    suppressing = Ref(false)
    # When the method popup commits, it sets p/d/s itself and we must skip
    # the auto-resuggest baked into the method_choice handler — otherwise
    # the popup's picks get overwritten with `suggest_channel_indices`.
    popup_committing = Ref(false)

    function rebuild_method!()
        suppressing[] && return
        sel = method_choice[]
        if sel == CONCENTRATION_OPTION
            run = state[]
            isnothing(run) && return
            ich = internal_menu.selection[]
            internal = ich isa AbstractString ? (ich, nothing) : (nothing, nothing)
            method[] = KJ.Cmethod(run; internal=internal)
        else
            P_ch, D_ch, d_ch = p_channel[], d_channel[], sister_channel[]
            (isempty(P_ch) || isempty(D_ch) || isempty(d_ch)) && return
            method[] = build_method(sel, P_ch, D_ch, d_ch;
                                    groups=group_rm_assignments[],
                                    roles=group_roles[])
        end
    end

    # Atomic commit from the method popup: sets channels + method without
    # the auto-resuggest stomping on the popup's picks, then fires a single
    # rebuild_method!.
    function commit_method!(mname::AbstractString,
                            p::AbstractString,
                            d::AbstractString,
                            s::AbstractString)
        suppressing[] = true
        if mname != CONCENTRATION_OPTION
            p_channel[]      = p
            d_channel[]      = d
            sister_channel[] = s
        end
        popup_committing[] = true
        method_choice[] = mname
        popup_committing[] = false
        suppressing[] = false
        rebuild_method!()
    end

    on(_ -> rebuild_method!(), group_rm_assignments)
    on(_ -> rebuild_method!(), group_roles)
    on(_ -> rebuild_method!(), p_channel)
    on(_ -> rebuild_method!(), d_channel)
    on(_ -> rebuild_method!(), sister_channel)

    on(method_choice) do sel
        sel === nothing && return
        # If the method popup is mid-commit, it already set p/d/s — don't
        # auto-resuggest. Just rebuild once at the end of the commit.
        popup_committing[] && return
        samp = sample_obs[]
        if sel != CONCENTRATION_OPTION && !isnothing(samp)
            chans = KJ.getChannels(samp)
            sug = suggest_channel_indices(sel, chans)
            suppressing[] = true
            p_channel[]      = chans[sug.P]
            d_channel[]      = chans[sug.D]
            sister_channel[] = chans[sug.d]
            suppressing[] = false
        end
        rebuild_method!()
    end

    on(internal_menu.selection) do _
        method_choice[] == CONCENTRATION_OPTION && rebuild_method!()
    end

    panel = (; right_layout=right, ctrls, section, ratio_grid, method_choice,
        internal_menu, add_btn, mode_menu,
        p_channel, d_channel, sister_channel,
        channels_obs, ratio_defs, defs_version,
        popup_ref,
        # Exposed for tests and scripted workflows that want to bypass the popup:
        add_def! = add_def!,
        remove_def! = remove_def!,
        ensure_popup! = ensure_popup!,
        relayout_section! = relayout_section!,
        commit_method! = commit_method!,
        conc_blocks=(internal_label, internal_menu))

    return panel
end

# Config row holds just the internal-standard picker now; show it in
# concentration mode, collapse it in geochronology mode (where P/D/S are
# picked from the Key directly).
function refresh_config_group!(panel)
    is_conc = panel.method_choice[] == CONCENTRATION_OPTION
    rowsize!(panel.right_layout, 4, is_conc ? Fixed(36) : Fixed(0))
    for b in panel.conc_blocks
        set_block_visible!(b, is_conc)
    end
    return
end

# A Cmethod (concentrations) has no parent/daughter ratios, so collapse the
# ratio stack row and let the count-rate plot take over. A Gmethod keeps it.
function apply_mode_layout!(panel, m)
    geochron = !(m isa KJ.Cmethod)
    if geochron
        panel.relayout_section!()
    else
        rowsize!(panel.right_layout, 2, Fixed(0))
    end
    return
end

function ensure_ratio_plot!(panel, sample_obs::Observable, samp::KJ.Sample)
    chans = KJ.getChannels(samp)
    # First-time channel seeding from the active method's defaults.
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
    plots = right[5, 1:2] = GridLayout()
    # x/ylabel follow the active P/D/sister channel names — empty strings
    # render as "/" until the first sample loads.
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
    return (; ax, plot_ref=Ref{Any}(nothing), right_layout=right,
              p_channel, d_channel, sister_channel)
end

# Biplot is the canonical isochron view (P/D vs S/D) — anchors directly on
# the method's P/D/S channel observables; it doesn't care what's in the
# user's ratio plot stack.
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

# The biplot is geochronology-only (P/D vs S/D needs Gmethod slots), so the
# caller is expected to AND its user-toggled visibility with `!isa Cmethod`.
function apply_biplot_visibility!(panel, show::Bool)
    rowsize!(panel.right_layout, 5, show ? Auto() : Fixed(0))
    set_block_visible!(panel.ax, show)
    return
end

# Fuzzy match a group name to the best RM. Compares lowercased prefixes
# in both directions so "NIST612p" matches "NIST612" and "hogsbo_pul"
# matches "Hogsbo". Falls back to RM_NONE when no prefix overlap >= 3
# characters exists.
function autopreselect_rm(group::AbstractString, options::AbstractVector)
    g = lowercase(group)
    best = RM_NONE
    best_len = 0
    for opt in options
        opt == RM_NONE && continue
        o = lowercase(opt)
        # Exact match wins immediately (handles short RM names like "BP"
        # that would fall below a prefix-length threshold).
        g == o && return opt
        # Otherwise require ≥ 3-char prefix overlap to avoid spurious
        # matches on single-letter coincidences. Prefer the longest
        # overlap so "NIST612" beats "NIST" when both exist.
        if (startswith(g, o) || startswith(o, g)) && length(o) >= 3
            if length(o) > best_len
                best = opt
                best_len = length(o)
            end
        end
    end
    return best
end

# References popup: one row per detected group, each with a group label,
# an RM dropdown (auto-preselected via `autopreselect_rm`), and a role
# dropdown. Changes apply immediately to `assignments` / `roles` (same
# behavior as the old inline panel); the popup is just the form layout.
function build_references_popup!(fig::Figure,
    state::Observable, method_choice::Observable,
    assignments::Observable, roles::Observable)
    pop = Popup(fig; size=(360, 360), title="References")

    container = pop.layout[1, 1] = GridLayout()
    rm_menus, role_menus, labels = Any[], Any[], Any[]

    function rebuild!()
        for b in rm_menus;   try; delete!(b); catch; end; end
        for b in role_menus; try; delete!(b); catch; end; end
        for b in labels;     try; delete!(b); catch; end; end
        empty!(rm_menus); empty!(role_menus); empty!(labels)
        run = state[]
        isnothing(run) && return
        groups = sort(unique(s.group for s in run))
        opts = rm_options_for(method_choice[])

        # Auto-preselect any group that doesn't already have an assignment
        # in `opts`. Push the augmented dict back into the observable so the
        # rest of the app (method.groups, biplot, etc.) sees the picks
        # immediately — even before the user opens the popup. Also drop
        # any assignment that isn't valid for the current method's RM list
        # (e.g., "Hogsbo" is a Lu-Hf RM and must not survive a switch to
        # U-Pb, which would otherwise crash KJ.process! with KeyError).
        current_assigns = copy(assignments[])
        changed = false
        for g in collect(keys(current_assigns))
            cur = current_assigns[g]
            if !(cur in opts)
                delete!(current_assigns, g)
                changed = true
            end
        end
        for g in groups
            cur = get(current_assigns, g, RM_NONE)
            cur == RM_NONE || continue
            suggested = autopreselect_rm(g, opts)
            if suggested != RM_NONE
                current_assigns[g] = suggested
                changed = true
            end
        end
        changed && (assignments[] = current_assigns)

        for (i, g) in enumerate(groups)
            rm_row   = 2 * (i - 1) + 1
            role_row = 2 * (i - 1) + 2
            lbl = pop.track!(Label(container[rm_row, 1], g;
                halign=:left, fontsize=10, tellwidth=true))
            current = get(assignments[], g, RM_NONE)
            idx = something(findfirst(==(current), opts), 1)
            # Menu kwarg `default` (an Int) initializes i_selected; passing
            # `i_selected=…` directly is overridden by initialize_block!'s
            # default=1, so menus end up at "(none)" instead of the preselect.
            rm_menu = pop.track!(Menu(container[rm_row, 2];
                options=opts, default=idx, width=140))
            role_default = get(ROLE_LABEL_OF, get(roles[], g, :standard),
                               ROLE_DEFAULT_LABEL)
            role_idx = something(findfirst(==(role_default), ROLE_LABELS), 1)
            role_menu = pop.track!(Menu(container[role_row, 2];
                options=ROLE_LABELS, default=role_idx, width=140))
            on(rm_menu.selection) do sel
                sel === nothing && return
                d = copy(assignments[])
                sel == RM_NONE ? delete!(d, g) : (d[g] = sel)
                assignments[] = d
            end
            on(role_menu.selection) do sel
                sel === nothing && return
                r = copy(roles[])
                r[g] = ROLE_SYMS[sel]
                roles[] = r
            end
            push!(rm_menus, rm_menu)
            push!(role_menus, role_menu)
            push!(labels, lbl)
        end
        colgap!(container, 6); rowgap!(container, 2)
    end

    on(_ -> rebuild!(), state)
    on(_ -> rebuild!(), method_choice)
    rebuild!()  # also runs auto-preselect immediately if data is already loaded

    open_with_defaults! = () -> (rebuild!(); pop.open!())

    return (; popup=pop, container,
              menus=Ref(rm_menus), role_menus=Ref(role_menus),
              labels=Ref(labels),
              open_with_defaults!)
end

function navigate!(table, state::Observable, delta::Int)
    run = state[]
    (isnothing(run) || isempty(run)) && return
    cur = table.i_selected[]
    cur == 0 && (cur = 1)
    table.i_selected[] = mod1(cur + delta, length(run))
    # Programmatic moves don't trigger Makie's click handler, which is what
    # normally re-syncs i_selected_cell. Clear it so the highlight follows.
    table.i_selected_cell[] = (0, 0)
    return
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
    auto_assign_groups!(run)
    state[] = run
    return
end

# Loaders often leave `samp.group = "sample"` for every row, which makes
# Reference-Material assignment impossible. As a heuristic we parse the
# common "<prefix> - <number>" naming convention used in lab logs and lift
# the prefix into `samp.group`, but only when nothing else gave us groups.
function auto_assign_groups!(run::Vector{KJ.Sample})
    all(s.group == "sample" for s in run) || return run
    for samp in run
        m = match(r"^(.+?)\s*-\s*\d+\s*$", samp.sname)
        samp.group = isnothing(m) ? samp.sname : strip(m.captures[1])
    end
    return run
end

# Reference materials KJ knows for the active method. CONCENTRATION_OPTION
# uses the glasses set; everything else is the per-decay-system table from
# `KJ._KJ["refmat"]`. "(none)" is the unassigned sentinel.
const RM_NONE = "(none)"
function rm_options_for(method_name::AbstractString)
    method_name == CONCENTRATION_OPTION &&
        return [RM_NONE; collect(KJ._KJ["glass"].names)]
    haskey(KJ._KJ["refmat"], method_name) || return [RM_NONE]
    return [RM_NONE; collect(KJ._KJ["refmat"][method_name].names)]
end

# How an RM-assigned group participates in the fit. `:standard` is the
# fractionation standard (goes into `method.standards`); `:massbias` goes
# into `method.bias.standards` via `KJ.Calibration!`; `:none` is RM-tagged
# but not used for calibration. KJ's docs treat these as distinct roles.
const ROLE_LABELS = ["Standard", "Mass bias", "None"]
const ROLE_SYMS = Dict("Standard" => :standard,
                       "Mass bias" => :massbias,
                       "None"      => :none)
const ROLE_LABEL_OF = Dict(:standard => "Standard",
                           :massbias => "Mass bias",
                           :none     => "None")
const ROLE_DEFAULT_LABEL = "Standard"

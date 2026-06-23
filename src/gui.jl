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

    pathbox = Textbox(left[1, 1]; placeholder="data folder…", width=160)
    format_menu = Menu(left[2, 1]; options=DATA_FORMATS,
                       default=default_format, width=160)
    load_btn = Button(left[3, 1]; label="Read data files", width=160)
    on(load_btn.clicks) do _
        s = pathbox.stored_string[]
        p = isnothing(s) ? "" : strip(String(s))
        fmt = something(format_menu.selection[], default_format)
        isempty(p) || load_path!(state, p, String(fmt))
    end

    method_btn = Button(left[4, 1];
        label=lift(m -> "Method: $m", method_choice), width=160)
    # Lazy: built once `bot_panel` exists (it owns `channels_obs`).
    method_popup_ref = Ref{Any}(nothing)

    refs_btn = Button(left[5, 1]; label="References", width=160)
    refs_popup_ref = Ref{Any}(nothing)

    process_btn = nothing
    for (i, lbl) in enumerate(STUB_BUTTONS)
        b = Button(left[5+i, 1]; label=lbl, width=160)
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

    # Key sits above the sample table.
    key_slot = mid[1, 1] = GridLayout()
    rowsize!(mid, 1, Fixed(180))
    # Pin `mid`'s column width: an Auto column collapses to the Key's
    # narrower autosize and lets the right column paint over the table.
    colsize!(mid, 1, Fixed(460))
    table = build_sample_table!(mid, state; row=2)

    title = Observable("")
    top_panel = build_count_rate_panel!(right, sample_obs, ytransform,
        title, table, state, key_slot)
    bot_panel = build_bottom_panel!(right, sample_obs, state,
        method, method_choice,
        group_rm_assignments, group_roles, fig, top_panel.ax,
        ytransform, fit_obs)
    biplot_panel = build_biplot_panel!(right, sample_obs,
        bot_panel.p_channel, bot_panel.d_channel, bot_panel.sister_channel)
    register_outlier_toggle!(biplot_panel, sample_obs, method, fit_obs)
    register_window_drag!(top_panel, sample_obs)

    # Panel strip above the biplot: `[plot type ▼] [on/off]`.
    panel_strip = right[5, 1:2] = GridLayout()
    plot_type_menu = Menu(panel_strip[1, 1];
        options=["Isochron", "Concordia"], default="Isochron", width=140)
    biplot_cb = Checkbox(panel_strip[1, 2]; checked=true)
    Label(panel_strip[1, 3], "on"; halign=:left, fontsize=10, tellwidth=false)
    Label(panel_strip[1, 4], ""; tellwidth=false)
    colgap!(panel_strip, 8)
    rowsize!(right, 5, Fixed(30))
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

    function ensure_method_popup!()
        isnothing(method_popup_ref[]) || return method_popup_ref[]
        method_popup_ref[] = build_method_popup!(fig,
            method_choice, bot_panel.channels_obs,
            bot_panel.p_channel, bot_panel.d_channel, bot_panel.sister_channel,
            bot_panel.p_proxy,   bot_panel.d_proxy,   bot_panel.sister_proxy,
            bot_panel.commit_method!)
        return method_popup_ref[]
    end
    on(method_btn.clicks) do _
        isempty(bot_panel.channels_obs[]) && return
        ensure_method_popup!().open_with_defaults!()
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
        refs_panel.open_with_defaults!()
    end

    # Group picker: assigning the SAME RM to a second sample auto-extends
    # to every sample sharing their longest common name prefix; later
    # picks of that RM just add the one cell (else manual resets after
    # the expansion would get undone). When the RM goes empty again the
    # one-time-expansion flag clears.
    lcs_done_for_rm = Set{String}()
    function on_group_pick(rm::AbstractString, row)
        (isnothing(row) || !(row isa Integer)) && return
        run = state[]
        (isnothing(run) || row == 0 || row > length(run)) && return
        target = run[row]
        old_group = target.group
        if rm == "(sample)"
            target.group = "sample"
        else
            other = nothing
            for s in run
                s.group == rm && s !== target && (other = s; break)
            end
            if isnothing(other)
                target.group = rm
                delete!(lcs_done_for_rm, rm)
            elseif rm in lcs_done_for_rm
                target.group = rm
            else
                push!(lcs_done_for_rm, rm)
                pref = group_prefix(target.sname, other.sname)
                target.group = rm
                isempty(pref) || for s in run
                    startswith(s.sname, pref) && (s.group = rm)
                end
            end
        end
        if old_group != "sample" && !any(s -> s.group == old_group, run)
            delete!(lcs_done_for_rm, old_group)
        end
        sync_assignments_from_groups!(group_rm_assignments, run, method_choice[])
        notify(state)
    end
    group_picker = build_group_picker_popup!(fig, method_choice, on_group_pick)
    # Column 4 = `:group` (see `build_sample_table!`'s `column_names`).
    table.on_cell_click[] = function (_t, row, col, _data)
        col == 4 || return
        run = state[]
        (isnothing(run) || row == 0 || row > length(run)) && return
        samp = run[row]
        group_picker.open_with_defaults!(samp.sname, samp.group, row)
    end

    effective_biplot_show(m) = biplot_visible[] && !(m isa KJ.Cmethod)
    # Cmethod has no biplot; collapse the strip with it.
    apply_strip_visibility!(m) = rowsize!(right, 5,
        m isa KJ.Cmethod ? Fixed(0) : Fixed(30))

    on(method) do m
        apply_mode_layout!(bot_panel, m)
        refresh_config_group!(bot_panel)
        apply_strip_visibility!(m)
        apply_biplot_visibility!(biplot_panel, effective_biplot_show(m))
    end
    on(_ -> apply_biplot_visibility!(biplot_panel, effective_biplot_show(method[])),
       biplot_visible)
    refresh_config_group!(bot_panel)
    apply_mode_layout!(bot_panel, method[])
    apply_strip_visibility!(method[])
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
        for slot in bot_panel.ratio_defs[], ax in slot.axes
            autolimits!(ax)
        end
        autolimits!(biplot_panel.ax)
    end

    return (; table, top_panel, bot_panel, biplot_panel, refs_panel,
              refs_btn, refs_popup_ref, group_picker,
              method_choice, method_btn, method_popup_ref, biplot_visible,
              group_rm_assignments, group_roles, process_btn,
              load_btn, pathbox, format_menu,
              panel_strip, plot_type_menu, biplot_cb)
end

"""
Run `KJ.process!` on the current run + method. `@warn`s on missing data /
method / RM groups instead of throwing. If a Button is passed its label
flashes to "Processing…" while the (synchronous) fit runs.
"""
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
        yield()  # Let the label repaint before `KJ.process!` blocks.
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
    panel.key_ref[] = build_key!(panel.key_slot, sp)
    return
end

"""
Interactive legend: per channel a colour swatch, the channel name, an ON
toggle (line visibility) and an HL toggle (highlight).
"""
function build_key!(gl::GridLayout, sp)
    names = collect(sp.channel_names[])
    n = length(names)
    cols = line_colors(sp.line_colormap[], n)
    visible = trues(n)
    highlight = falses(n)
    sp.channel_visible[] = collect(visible)
    sp.channel_highlight[] = collect(highlight)

    # Two side-by-side blocks of `swatch | name | ON | HL`.
    half = cld(n, 2)
    Label(gl[1, 1:8], "Key"; halign=:left, fontsize=11, font=:bold,
        tellwidth=false)
    on_boxes = Makie.Checkbox[]
    hl_boxes = Makie.Checkbox[]
    # Allocate by index so `push!`-by-block keeps channel order.
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

set_block_visible!(b, v) = (b.blockscene.visible[] = v; nothing)
# Axes have two scenes (blockscene + scene); hide both.
set_block_visible!(ax::Axis, v) =
    (ax.blockscene.visible[] = v; ax.scene.visible[] = v; nothing)

"""
"Add ratio plot" popup: two-column N/D picker. N is multi-select, D is
radio. Apply calls `on_apply(numerators, denominator)`; defaults come
lazily from `get_defaults()`.
"""
function build_add_ratio_popup!(fig::Figure, channels_obs::Observable,
    on_apply::Function, get_defaults::Function)
    pop = Popup(fig; size=(340, 380), title="Add ratio plot")

    content = pop.layout[1, 1] = GridLayout()
    Label(content[1, 1], "Channel"; halign=:left, fontsize=11,
        font=:bold, tellwidth=false)
    Label(content[1, 2], "N"; fontsize=11, font=:bold)
    Label(content[1, 3], "D"; fontsize=11, font=:bold)
    colsize!(content, 2, Fixed(28))
    colsize!(content, 3, Fixed(28))
    colgap!(content, 8)

    footer = pop.layout[2, 1] = GridLayout()
    apply_btn  = Button(footer[1, 1]; label="Apply",  width=80)
    cancel_btn = Button(footer[1, 2]; label="Cancel", width=80)
    Label(footer[1, 3], ""; tellwidth=false)
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
            lbl = Label(content[r, 1], ch;
                halign=:left, fontsize=10, tellwidth=false)
            ncb = Checkbox(content[r, 2]; checked=(ch in default_ns))
            dcb = Checkbox(content[r, 3]; checked=(ch == default_d))
            # D acts as a radio group.
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
        isopen(pop) || return
        chans = channels_obs[]
        ns, d = String[], ""
        for (i, ch) in enumerate(chans)
            i <= length(n_boxes) && n_boxes[i].checked[] && push!(ns, ch)
            i <= length(d_boxes) && d_boxes[i].checked[] && (d = ch)
        end
        (isempty(ns) || isempty(d)) && return  # ignore invalid selection
        on_apply(ns, d)
        close!(pop)
    end
    on(cancel_btn.clicks) do _
        isopen(pop) || return
        close!(pop)
    end

    return (; popup=pop, apply_btn, cancel_btn, n_boxes, d_boxes,
            open_with_defaults! = () -> (rebuild_rows!(); open!(pop)))
end

"""
Method-selection popup: decay-system buttons on the left, channels with
mutually-exclusive "—/P/D/d" role dropdowns on the right, P/D/d Pairing
summary plus proxy-isotope override menus below. Apply commits through
`commit_method!`.
"""
function build_method_popup!(fig::Figure,
    method_choice::Observable,
    channels_obs::Observable,
    p_channel::Observable,
    d_channel::Observable,
    sister_channel::Observable,
    p_proxy::Observable,
    d_proxy::Observable,
    sister_proxy::Observable,
    commit_method!::Function)
    pop = Popup(fig; size=(620, 760), title="Method")

    methods = [method_names(); CONCENTRATION_OPTION]
    ROLES   = ("—", "P", "D", "d")

    # LEFT pane: method-list buttons. Selected one is tinted via buttoncolor.
    selected_idx = Observable(findfirst(==(method_choice[]), methods))
    left_pane = pop.layout[1, 1] = GridLayout()
    method_buttons = Makie.Button[]
    for (i, m) in enumerate(methods)
        bcolor = lift(s -> i == s ? RGBf(0.78, 0.85, 1.0) : RGBf(0.96, 0.96, 0.96),
                      selected_idx)
        btn = Button(left_pane[i, 1]; label=m, width=90, height=28,
                                buttoncolor=bcolor)
        on(btn.clicks) do _
            isopen(pop) || return
            selected_idx[] = i
        end
        push!(method_buttons, btn)
    end

    # RIGHT pane: per-channel role dropdowns + role summary. `role_*` holds
    # the channel index for that role; 0 == unassigned.
    right_pane = pop.layout[1, 2] = GridLayout()
    chan_grid  = right_pane[1, 1] = GridLayout()
    sum_grid   = right_pane[2, 1] = GridLayout()
    rowsize!(right_pane, 2, Fixed(96))

    role_P = Observable(0)
    role_D = Observable(0)
    role_d = Observable(0)

    # Each entry: (channel_label_block, role_menu_block).
    chan_rows = Any[]

    # Reentrancy guard for batch role assignment (suggest / defaults).
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
            delete!(lbl)
            delete!(menu)
        end
        empty!(chan_rows)
        role_P[] = role_D[] = role_d[] = 0

        chans = channels_obs[]
        isempty(chans) && return

        for (i, ch) in enumerate(chans)
            lbl  = Label(chan_grid[i, 1], "$(i). $ch";
                                    halign=:left, fontsize=10, tellwidth=false)
            # Tight height/padding so an 18-channel list fits in the popup.
            menu = Menu(chan_grid[i, 2]; options=collect(ROLES),
                                   default="—", width=56, height=22,
                                   fontsize=10, textpadding=(4, 4, 2, 2))
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
            for (_, menu) in chan_rows
                menu.i_selected[] = 1     # "—"
            end
            role_P[] = role_D[] = role_d[] = 0
        finally
            setting_roles[] = false
        end
        mname == CONCENTRATION_OPTION && return
        sug = suggest_channel_indices(mname, chans)
        set_role!(sug.P, "P")
        set_role!(sug.D, "D")
        set_role!(sug.d, "d")
    end

    on(selected_idx) do i
        i === nothing && return
        apply_method_defaults!(methods[i])
    end

    # Per-role proxy override menu: lets the user override
    # `KJ.channel2proxy`'s name-based inference when the CSV header
    # drops the isotope (e.g. "ch1" or "175").
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

    function summary_text(role_obs::Observable, ion_role::Symbol)
        return lift(role_obs, channels_obs, selected_idx) do i, chans, midx
            midx === nothing && return "$(ion_role): —"
            mname = methods[midx]
            mname == CONCENTRATION_OPTION && return ""
            ions = default_ions(mname)
            ion = getproperty(ions, ion_role)
            (i == 0 || i > length(chans)) && return "$(ion_role)  =  $ion  (no channel assigned)"
            return "$(ion_role)  =  $ion   ←   $(chans[i])"
        end
    end

    proxy_menus = Dict{Symbol,Makie.Menu}()
    # Reentrancy guard for programmatic proxy-menu resets.
    setting_proxy = Ref(false)

    function build_summary_row!(row::Int, role_obs::Observable, ion_role::Symbol)
        Label(sum_grid[row, 1], summary_text(role_obs, ion_role);
                         halign=:left, fontsize=10, font=:bold, tellwidth=false)
        proxy_menu = Menu(sum_grid[row, 2]; options=String["—"],
                                     default=nothing, width=100, height=22,
                                     fontsize=10,
                                     textpadding=(4, 4, 2, 2))
        proxy_menus[ion_role] = proxy_menu
    end
    build_summary_row!(1, role_P, :P)
    build_summary_row!(2, role_D, :D)
    build_summary_row!(3, role_d, :d)
    colsize!(sum_grid, 1, Auto(true, 1.0))
    colsize!(sum_grid, 2, Fixed(110))

    # Refresh a proxy menu when its role's channel changes — repopulate the
    # element's isotope options and select the inferred proxy.
    function refresh_proxy_menu!(ion_role::Symbol, role_obs::Observable)
        midx = selected_idx[]
        midx === nothing && return
        mname = methods[midx]
        mname == CONCENTRATION_OPTION && return
        ions = default_ions(mname)
        ion = getproperty(ions, ion_role)
        element = element_of(ion)
        opts = isotope_options(element)
        isempty(opts) && (opts = [ion])
        chans = channels_obs[]
        i = role_obs[]
        ch = (i == 0 || i > length(chans)) ? "" : chans[i]
        inferred = infer_proxy(ch, ion)
        sel_idx = something(findfirst(==(inferred), opts), 1)
        menu = proxy_menus[ion_role]
        setting_proxy[] = true
        try
            menu.options[] = opts
            menu.i_selected[] = sel_idx
        finally
            setting_proxy[] = false
        end
    end
    for (role_obs, sym) in ((role_P, :P), (role_D, :D), (role_d, :d))
        on(_ -> refresh_proxy_menu!(sym, role_obs), role_obs)
    end
    on(_ -> for (role_obs, sym) in ((role_P, :P), (role_D, :D), (role_d, :d))
                refresh_proxy_menu!(sym, role_obs)
            end, selected_idx)

    # Footer
    footer = pop.layout[2, 1:2] = GridLayout()
    apply_btn  = Button(footer[1, 1]; label="Apply",  width=80)
    cancel_btn = Button(footer[1, 2]; label="Cancel", width=80)
    Label(footer[1, 3], ""; tellwidth=false)
    colgap!(footer, 8)
    rowsize!(pop.layout, 2, Fixed(36))
    colsize!(pop.layout, 1, Fixed(110))

    on(apply_btn.clicks) do _
        isopen(pop) || return
        midx = something(selected_idx[], 0)
        midx == 0 && return
        mname = methods[midx]
        chans = channels_obs[]
        if mname == CONCENTRATION_OPTION
            commit_method!(mname, "", "", "")
        else
            (role_P[] == 0 || role_D[] == 0 || role_d[] == 0) && return
            p_pr = something(proxy_menus[:P].selection[], "")
            d_pr = something(proxy_menus[:D].selection[], "")
            s_pr = something(proxy_menus[:d].selection[], "")
            commit_method!(mname,
                chans[role_P[]], chans[role_D[]], chans[role_d[]];
                p_pr=String(p_pr), d_pr=String(d_pr), s_pr=String(s_pr))
        end
        close!(pop)
    end
    on(cancel_btn.clicks) do _
        isopen(pop) || return
        close!(pop)
    end

    # Rebuild channel rows on data load (the popup may be opened first).
    on(channels_obs) do _
        rebuild_chan_rows!()
        midx = selected_idx[]
        midx === nothing || apply_method_defaults!(methods[midx])
    end
    rebuild_chan_rows!()

    function open_with_defaults!()
        chans = channels_obs[]
        isempty(chans) && return
        midx = findfirst(==(method_choice[]), methods)
        if !isnothing(midx) && midx != selected_idx[]
            selected_idx[] = midx       # fires apply_method_defaults!
        else
            apply_method_defaults!(method_choice[])
        end
        # Override the suggestion with the live channel observables when
        # they're still valid in the new channel list.
        if method_choice[] != CONCENTRATION_OPTION
            for (ch_obs, role) in ((p_channel, "P"),
                                   (d_channel, "D"),
                                   (sister_channel, "d"))
                ch = ch_obs[]
                isempty(ch) && continue
                i = findfirst(==(ch), chans)
                isnothing(i) || set_role!(i, role)
            end
            for (proxy_obs, sym) in ((p_proxy, :P), (d_proxy, :D),
                                     (sister_proxy, :d))
                pr = proxy_obs[]
                isempty(pr) && continue
                opts = proxy_menus[sym].options[]
                pi = findfirst(==(pr), opts)
                isnothing(pi) || begin
                    setting_proxy[] = true
                    try
                        proxy_menus[sym].i_selected[] = pi
                    finally
                        setting_proxy[] = false
                    end
                end
            end
        end
        open!(pop)
    end

    return (; popup=pop, selected_idx, role_P, role_D, role_d,
            chan_rows, method_buttons, proxy_menus,
            apply_btn, cancel_btn,
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
    count_rate_ax::Makie.Axis,
    ytransform::Observable,
    fit_obs::Observable)
    ctrls = right[4, 1:2] = GridLayout()
    # Cmethod uses this row for the internal-standard picker; Gmethod
    # picks P/D/S from the method popup, so the row collapses.
    internal_label = Label(ctrls[1, 1], "Internal standard"; halign=:right, tellwidth=true)
    internal_menu = Menu(ctrls[1, 2]; options=["(internal)"], width=150)
    Label(ctrls[1, 3], ""; tellwidth=false)
    colgap!(ctrls, 8)
    rowsize!(right, 4, Fixed(0))

    # Ratio stack: "+ Add" bar above, ratio Axes below; each Axis hides its
    # own x-ticks and shares the count-rate axis via `linkxaxes!`.
    section = right[2, 1] = GridLayout()
    bar        = section[1, 1] = GridLayout()
    ratio_grid = section[2, 1] = GridLayout()
    rowsize!(section, 1, Fixed(36))

    add_btn   = Button(bar[1, 1]; label="+ Add ratio plot", width=160)
    # Combined = one Axis with every ratio overlaid (canonical per-sample
    # view). Split = one Axis per ratio, side-by-side.
    mode_menu = Menu(bar[1, 2]; options=["Combined", "Split"],
                     default="Combined", width=110)
    Label(bar[1, 3], ""; tellwidth=false)
    colgap!(bar, 8)

    p_channel      = Observable("")
    d_channel      = Observable("")
    sister_channel = Observable("")
    # Per-role proxy override; `""` falls back to `KJ.channel2proxy`.
    p_proxy        = Observable("")
    d_proxy        = Observable("")
    sister_proxy   = Observable("")

    channels_obs = Observable(String[])
    on(sample_obs) do samp
        isnothing(samp) && return
        channels_obs[] = KJ.getChannels(samp)
    end

    # Each entry is a SLOT — one "+ Add ratio plot" Apply. A slot bundles
    # N numerators against one denominator and renders them as either a
    # single overlaid Axis (Combined) or N stacked Axes sharing X (Split).
    # The × close button lives on the slot's row in `ratio_grid`, not on
    # any individual Axis — clicking it removes the whole slot.
    #
    # NamedTuple fields:
    #   numerators::Observable{Vector{String}}
    #   denominator::Observable{String}
    #   slot_layout::GridLayout    — this slot's row in `ratio_grid`
    #   axes::Vector{Axis}         — 1 in Combined, N in Split
    #   plots::Vector              — one `ratioplot!` handle per numerator
    #   legend, close_btn
    ratio_defs = Ref{Vector{Any}}(Any[])
    defs_version = Observable(0)

    function relink_xaxes!()
        slots = ratio_defs[]
        isempty(slots) && return
        all_axes = Axis[]
        for s in slots, ax in s.axes
            push!(all_axes, ax)
        end
        try
            Makie.linkxaxes!(count_rate_ax, all_axes...)
        catch err
            @warn "linkxaxes failed" exception=err
        end
    end

    # Ratio-section height: collapses to the bar with no slots, otherwise
    # `BAR_H + total_axes * PLOT_H_1` capped at `SECTION_MAX`. In Split
    # mode each numerator gets its own row, so a 2-numerator slot is
    # twice as tall as a Combined slot.
    BAR_H       = 36
    PLOT_H_1    = 240
    SECTION_MAX = 520
    function relayout_section!()
        slots = ratio_defs[]
        n_axes = isempty(slots) ? 0 : sum(length(s.axes) for s in slots)
        h = n_axes == 0 ? BAR_H : min(BAR_H + n_axes * PLOT_H_1, SECTION_MAX)
        rowsize!(right, 2, Fixed(h))
    end

    is_combined() = mode_menu.selection[] == "Combined"

    function make_ratio_axis!(parent)
        ax = Axis(parent;
            ylabel = "ratio",
            yscale = ytransform[],
            yautolimitmargin = (0.0, 0.05),
            yticklabelspace = 42.0,
            xlabelvisible = false,
            xticklabelsvisible = false,
            xticksvisible = false)
        Makie.deactivate_interaction!(ax, :rectanglezoom)
        on(ytransform) do scale
            ax.yscale = scale
            reset_limits!(ax)
        end
        return ax
    end

    function add_def!(ns::Vector{String}, dch::String)
        isempty(ns) && return
        nums = Observable(copy(ns))
        den  = Observable(dch)

        i = length(ratio_defs[]) + 1
        slot_layout = ratio_grid[i, 1] = GridLayout()

        axes = Axis[]
        plots = Any[]
        legends = Any[]

        if is_combined()
            # One Axis with every numerator overlaid; one explicit color
            # per trace so they don't collide on colormap slot 1.
            ax = make_ratio_axis!(slot_layout[1, 1])
            push!(axes, ax)
            palette = Makie.categorical_colors(:tab10, 10)
            for (j, n) in enumerate(ns)
                color = palette[mod1(j, length(palette))]
                p = ratioplot!(ax, sample_obs;
                    numerators = Observable([n]),
                    denominator = Observable(dch),
                    line_color = color,
                    fit = fit_obs, method = method)
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
            # N axes stacked vertically inside the slot, sharing X.
            for (j, n) in enumerate(ns)
                ax = make_ratio_axis!(slot_layout[j, 1])
                push!(axes, ax)
                p = ratioplot!(ax, sample_obs;
                    numerators = Observable([n]),
                    denominator = Observable(dch),
                    fit = fit_obs, method = method)
                push!(plots, p)
                if n != dch
                    push!(legends, axislegend(ax;
                        position = :lt, framevisible = false,
                        labelsize = 8, padding = (4, 4, 2, 2)))
                end
            end
            length(axes) >= 2 && Makie.linkxaxes!(axes...)
        end

        # × button overlays the top-right corner of the slot — placed
        # via the slot's GridLayout, not anchored to any Axis viewport.
        close_btn = Button(slot_layout[1, 1];
            label = "×", width = 20, height = 20, fontsize = 14,
            halign = :right, valign = :top,
            tellwidth = false, tellheight = false)

        def = (; numerators = nums, denominator = den,
                 slot_layout, axes, plots, close_btn, legends,
                 ax = first(axes))
        push!(ratio_defs[], def)

        on(close_btn.clicks) do _
            remove_def!(def)
        end

        for ax in axes; autolimits!(ax); end
        relink_xaxes!()
        relayout_section!()
        defs_version[] = defs_version[] + 1
        return def
    end

    function teardown_slot!(d)
        for l in d.legends; delete!(l); end
        delete!(d.close_btn)
        for ax in d.axes; delete!(ax); end
        Makie.GridLayoutBase.remove_from_gridlayout!(
            Makie.GridLayoutBase.gridcontent(d.slot_layout))
    end

    function teardown_defs!()
        for d in ratio_defs[]; teardown_slot!(d); end
        empty!(ratio_defs[])
        trim!(ratio_grid)
    end

    function remove_def!(def)
        idx = findfirst(d -> d === def, ratio_defs[])
        isnothing(idx) && return
        survivors = [(d.numerators[], d.denominator[]) for d in ratio_defs[] if d !== def]
        teardown_defs!()
        for (ns, dch) in survivors
            add_def!(ns, dch)
        end
        relayout_section!()
        defs_version[] = defs_version[] + 1
    end

    # Mode toggle: snapshot every slot's `(numerators, denominator)`,
    # tear them down, re-add in the new mode. `mode_initialized` skips
    # the Menu's initial firing on construction.
    mode_initialized = Ref(false)
    function switch_mode!()
        survivors = [(d.numerators[], d.denominator[]) for d in ratio_defs[]]
        teardown_defs!()
        for (ns, dch) in survivors
            add_def!(ns, dch)
        end
        relayout_section!()
    end
    on(mode_menu.selection) do _
        mode_initialized[] || return
        switch_mode!()
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

    # Apply the empty-state row size right now so the section collapses to
    # just the bar instead of claiming a full Auto() share of the right panel.
    relayout_section!()
    # Now safe to react to mode-menu changes — initial firings from the
    # bot panel's construction won't pointlessly rebuild an empty section.
    mode_initialized[] = true

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
                                    p_proxy=p_proxy[],
                                    d_proxy=d_proxy[],
                                    s_proxy=sister_proxy[],
                                    groups=group_rm_assignments[],
                                    roles=group_roles[])
        end
    end

    # Atomic commit: write channels + proxies in one go and fire a single
    # `rebuild_method!`, bypassing the per-channel auto-resuggest. Empty
    # proxy strings fall back to `KJ.channel2proxy` name inference.
    function commit_method!(mname::AbstractString,
                            p::AbstractString,
                            d::AbstractString,
                            s::AbstractString;
                            p_pr::AbstractString="",
                            d_pr::AbstractString="",
                            s_pr::AbstractString="")
        suppressing[] = true
        if mname != CONCENTRATION_OPTION
            p_channel[]      = p
            d_channel[]      = d
            sister_channel[] = s
            p_proxy[]        = p_pr
            d_proxy[]        = d_pr
            sister_proxy[]   = s_pr
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
    on(_ -> rebuild_method!(), p_proxy)
    on(_ -> rebuild_method!(), d_proxy)
    on(_ -> rebuild_method!(), sister_proxy)

    on(method_choice) do sel
        sel === nothing && return
        # Skip auto-resuggest while `commit_method!` runs.
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
        p_proxy, d_proxy, sister_proxy,
        channels_obs, ratio_defs, defs_version,
        popup_ref,
        # Exposed for tests that bypass the popup:
        add_def! = add_def!,
        remove_def! = remove_def!,
        ensure_popup! = ensure_popup!,
        relayout_section! = relayout_section!,
        commit_method! = commit_method!,
        conc_blocks=(internal_label, internal_menu))

    return panel
end

"Show the internal-standard row in Cmethod mode, collapse it otherwise."
function refresh_config_group!(panel)
    is_conc = panel.method_choice[] == CONCENTRATION_OPTION
    rowsize!(panel.right_layout, 4, is_conc ? Fixed(36) : Fixed(0))
    for b in panel.conc_blocks
        set_block_visible!(b, is_conc)
    end
    return
end

"Collapse the ratio stack for Cmethods; restore it for Gmethods."
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
    return (; ax, plot_ref=Ref{Any}(nothing),
              concordia_line_ref=Ref{Any}(nothing),
              concordia_notice_ref=Ref{Any}(nothing),
              right_layout=right,
              p_channel, d_channel, sister_channel)
end

mutable struct WindowDragState
    kind::Symbol     # :bwin or :swin
    win_idx::Int     # index into samp.bwin/samp.swin
    side::Symbol     # :left or :right
    active::Bool
end

"Find the bwin/swin edge nearest to data x-coord `cx`, or `nothing`."
function nearest_window_edge(samp, cx::Real, tol::Real)
    times = samp.dat[!, 1]
    best = nothing
    best_d = tol
    for (kind, wins) in ((:bwin, samp.bwin), (:swin, samp.swin))
        for (i, w) in enumerate(wins)
            a, b = w[1], w[2]
            (a < 1 || b > length(times) || a > b) && continue
            for (side, idx) in ((:left, a), (:right, b))
                d = abs(times[idx] - cx)
                if d <= best_d
                    best = (kind, i, side)
                    best_d = d
                end
            end
        end
    end
    return best
end

"Nearest row in `samp.dat`'s time column to data x-coord `cx`."
function nearest_row(samp, cx::Real)
    times = samp.dat[!, 1]
    return argmin(abs.(Float64.(times) .- Float64(cx)))
end

"""
    register_window_drag!(panel, sample_obs)

Drag the bwin/swin edges on the count-rate axis to resize them. The
mutation goes through `KJ.setBwin!`/`setSwin!` so downstream consumers
(every `vspan!` driven by `samp.bwin`/`samp.swin`) refresh on the
follow-up `notify(sample_obs)`.

Visual cues:
- Permanent thin tick at every bwin/swin edge so the grab points are
  always visible.
- Hover within tolerance brightens the nearest edge to a thick coloured
  line (blue for bwin, orange for swin), signalling "grabbable".
- During a drag, the highlight follows the cursor live.
"""
function register_window_drag!(panel, sample_obs::Observable)
    drag = WindowDragState(:bwin, 0, :left, false)
    ax = panel.ax

    # Permanent thin edge ticks at every window boundary.
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

    # Hover/drag highlight — empty vector → not rendered.
    hover_xs   = Observable(Float64[])
    hover_kind = Observable(:bwin)   # :bwin → blue, :swin → orange
    hover_color = lift(hover_kind) do k
        k === :bwin ? RGBAf(0.2, 0.5, 1.0, 0.95) : RGBAf(1.0, 0.55, 0.1, 0.95)
    end
    vlines!(ax, hover_xs; color = hover_color, linewidth = 4)

    function set_hover!(samp, edge)
        if isnothing(edge)
            isempty(hover_xs[]) || (hover_xs[] = Float64[])
            return
        end
        kind, i, side = edge
        wins = kind === :bwin ? samp.bwin : samp.swin
        idx = side === :left ? wins[i][1] : wins[i][2]
        hover_kind[] = kind
        hover_xs[]   = [Float64(samp.dat[idx, 1])]
    end

    Makie.register_interaction!(ax, :window_drag) do ev::MouseEvent, _
        samp = sample_obs[]
        isnothing(samp) && return Consume(false)
        tol = 0.01 * ax.finallimits[].widths[1]

        if ev.type === MouseEventTypes.over && !drag.active
            set_hover!(samp, nearest_window_edge(samp, ev.data[1], tol))
            return Consume(false)
        elseif ev.type === MouseEventTypes.leftdragstart
            edge = nearest_window_edge(samp, ev.data[1], tol)
            isnothing(edge) && return Consume(false)
            drag.kind, drag.win_idx, drag.side = edge
            drag.active = true
            set_hover!(samp, edge)
            return Consume(true)
        elseif ev.type === MouseEventTypes.leftdrag
            drag.active || return Consume(false)
            row = nearest_row(samp, ev.data[1])
            wins = drag.kind === :bwin ? samp.bwin : samp.swin
            old_a, old_b = wins[drag.win_idx][1], wins[drag.win_idx][2]
            new_a, new_b = drag.side === :left ?
                (min(row, old_b - 1), old_b) :
                (old_a, max(row, old_a + 1))
            new_wins = collect(wins)
            new_wins[drag.win_idx] = (new_a, new_b)
            drag.kind === :bwin ? KJ.setBwin!(samp, new_wins) :
                                   KJ.setSwin!(samp, new_wins)
            notify(sample_obs)
            # Track the new edge position with the cursor.
            set_hover!(samp, (drag.kind, drag.win_idx, drag.side))
            return Consume(true)
        elseif ev.type === MouseEventTypes.leftdragstop
            drag.active || return Consume(false)
            drag.active = false
            # Re-pick the hover edge under the cursor (or clear).
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
The recipes (`SamplePlot`/`RatioPlot`/`BiPlot`) all consult
`samp.dat.outlier`, so a `notify(sample_obs)` after the flip refreshes
every panel.

Scatter index → `samp.dat` row mapping:
- processed mode (Gmethod + fit): the scatter is `KJ.atomic` output,
  which iterates over `swinData(samp)` — index `k` corresponds to
  `windows2selection(samp.swin)[k]`.
- raw mode: scatter covers every row in `samp.dat`, so `k` is the row.
"""
function register_outlier_toggle!(panel, sample_obs::Observable,
                                  method::Observable, fit_obs::Observable)
    Makie.register_interaction!(panel.ax, :toggle_outlier) do ev::MouseEvent, _
        ev.type === MouseEventTypes.leftdoubleclick || return Consume(false)
        plot = panel.plot_ref[]
        (isnothing(plot) || isnothing(sample_obs[])) && return Consume(false)
        xs, ys = plot.xs[], plot.ys[]
        isempty(xs) && return Consume(false)

        # Normalise distances by axis extent so x/y scale don't bias the
        # nearest-point pick.
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

"Show/hide the biplot row; the caller is responsible for Gmethod-only gating."
function apply_biplot_visibility!(panel, show::Bool)
    rowsize!(panel.right_layout, 6, show ? Auto() : Fixed(0))
    set_block_visible!(panel.ax, show)
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
Popup with one button per RM (plus a "(sample)" reset). `on_pick(rm, ctx)`
fires with the chosen label and the context handed to `open_with_defaults!`
(used to carry the clicked row index).
"""
function build_group_picker_popup!(fig::Figure,
    method_choice::Observable, on_pick::Function)
    # Body auto-sizes — the RM count varies with method (Lu-Hf ~17, U-Pb ~27).
    pop = Popup(fig; min_size=(280, 120), title="Assign group")

    sample_lbl = Label(pop.layout[1, 1], "Sample: —";
        halign=:left, fontsize=11, font=:bold, tellwidth=false)
    rowsize!(pop.layout, 1, Fixed(28))

    list_grid = pop.layout[2, 1] = GridLayout()
    rm_buttons = Makie.Button[]
    target_ctx = Ref{Any}(nothing)

    function rebuild_buttons!()
        for b in rm_buttons        delete!(b)
        end
        empty!(rm_buttons)
        opts = String["(sample)"]
        for rm in rm_options_for(method_choice[])
            rm == RM_NONE || push!(opts, rm)
        end
        for (i, opt) in enumerate(opts)
            btn = Button(list_grid[i, 1]; label=opt,
                width=220, height=26)
            on(btn.clicks) do _
                isopen(pop) || return
                on_pick(opt, target_ctx[])
                close!(pop)
            end
            push!(rm_buttons, btn)
        end
        rowgap!(list_grid, 2)
    end
    on(_ -> rebuild_buttons!(), method_choice)
    rebuild_buttons!()

    function open_with_defaults!(sname::AbstractString,
        current_group::AbstractString, ctx)
        sample_lbl.text[] = "Sample: $sname    (current: $current_group)"
        target_ctx[] = ctx
        open!(pop)
    end

    return (; popup=pop, sample_lbl, rm_buttons=Ref(rm_buttons),
              open_with_defaults!)
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
function build_references_popup!(fig::Figure,
    state::Observable, method_choice::Observable,
    assignments::Observable, roles::Observable)
    pop = Popup(fig; size=(360, 360), title="References")

    container = pop.layout[1, 1] = GridLayout()
    rm_menus, role_menus, labels = Any[], Any[], Any[]

    function rebuild!()
        for b in rm_menus;   delete!(b); end
        for b in role_menus; delete!(b); end
        for b in labels;     delete!(b); end
        empty!(rm_menus); empty!(role_menus); empty!(labels)
        run = state[]
        isnothing(run) && return
        groups = sort(unique(s.group for s in run))
        opts = rm_options_for(method_choice[])

        # Drop assignments not valid for the new method, then auto-preselect
        # any still-unassigned groups. Push the result back so downstream
        # observers see the picks before the popup is opened.
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
            lbl = Label(container[rm_row, 1], g;
                halign=:left, fontsize=10, tellwidth=true)
            current = get(assignments[], g, RM_NONE)
            idx = something(findfirst(==(current), opts), 1)
            # Pass via `default` — `i_selected=…` gets overridden by
            # `initialize_block!`'s default of 1.
            rm_menu = Menu(container[rm_row, 2];
                options=opts, default=idx, width=140)
            role_default = get(ROLE_LABEL_OF, get(roles[], g, :standard),
                               ROLE_DEFAULT_LABEL)
            role_idx = something(findfirst(==(role_default), ROLE_LABELS), 1)
            role_menu = Menu(container[role_row, 2];
                options=ROLE_LABELS, default=role_idx, width=140)
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
    rebuild!()

    open_with_defaults! = () -> (rebuild!(); open!(pop))

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
    # Programmatic move: clear cell selection so the row highlight follows.
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
    state[] = run
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

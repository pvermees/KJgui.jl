"""
    run_gui(; path=nothing, format="Agilent")

Build and display the KJgui dashboard. The Table's `i_selected` is the
canonical "active sample" observable; prev/next buttons and both plot
panels read from it.

The ratio panel doubles as the method config row: a decay-system dropdown
plus P / D / S channel pickers define a `KJ.Gmethod` and drive the two
side-by-side ratio plots (P/D and S/D, sharing D as denominator).
"""
function run_gui(; path::Union{Nothing,AbstractString}=nothing,
    format::AbstractString="Agilent")
    fig = Figure(size=(1700, 900))

    state = Observable{Union{Nothing,Vector{KJ.Sample}}}(nothing)
    ytransform = Observable{Function}(Makie.pseudolog10)
    method = Observable{Union{Nothing,KJ.Gmethod}}(nothing)
    numerators = Observable(String[])
    denominator = Observable("")
    sample_obs = Observable{Union{Nothing,KJ.Sample}}(nothing)

    handles = build_dashboard!(fig, state, sample_obs,
        ytransform, method, numerators, denominator,
        format)

    isnothing(path) || load_path!(state, path, format)

    display(fig)
    return (; fig, state, sample_obs, ytransform, method,
        numerators, denominator, handles...)
end

const STUB_BUTTONS = [
    "Tabulate samples", "View / adjust",
    "Interferences", "Fractionation", "Mass bias",
    "Process data", "Export results", "Logs / templates",
    "Options", "Clear", "Exit",
]

function build_dashboard!(fig::Figure,
    state::Observable,
    sample_obs::Observable,
    ytransform::Observable,
    method::Observable,
    numerators::Observable,
    denominator::Observable,
    default_format::AbstractString)
    left = fig[1, 1] = GridLayout()
    mid = fig[1, 2] = GridLayout()
    right = fig[1, 3] = GridLayout()

    colsize!(fig.layout, 1, Fixed(180))
    colsize!(fig.layout, 2, Fixed(460))
    # Without Auto(false), the narrow button column dictates row height and
    # the dashboard collapses to a strip ~13 buttons tall.
    rowsize!(fig.layout, 1, Auto(false))

    pathbox = Textbox(left[1, 1]; placeholder="data folder…", width=160)
    load_btn = Button(left[2, 1]; label="Read data files", width=160)
    on(load_btn.clicks) do _
        s = pathbox.stored_string[]
        p = isnothing(s) ? "" : strip(String(s))
        isempty(p) || load_path!(state, p, default_format)
    end
    for (i, lbl) in enumerate(STUB_BUTTONS)
        b = Button(left[2+i, 1]; label=lbl, width=160)
        on(b.clicks) do _
            @info "not implemented yet" button = lbl
        end
    end

    table = build_sample_table!(mid, state)

    title = Observable("")
    top_panel = build_count_rate_panel!(right, sample_obs, ytransform,
        title, table, state)
    bot_panel = build_ratio_panel!(right, sample_obs,
        method, numerators, denominator)

    colsize!(right, 2, Fixed(220))

    on(table.i_selected) do i
        run = state[]
        (isnothing(run) || isempty(run) || i == 0 || i > length(run)) && return
        samp = run[i]
        sample_obs[] = samp
        title[] = "$(i)/$(length(run))  $(samp.sname)  [$(samp.group)]  ($(samp.datetime))"
        ensure_count_rate_plot!(top_panel, sample_obs)
        ensure_ratio_plot!(bot_panel, sample_obs, numerators, denominator, samp)
        autolimits!(top_panel.ax)
        autolimits!(bot_panel.ax_pd)
        autolimits!(bot_panel.ax_sd)
    end

    return (; table, top_panel, bot_panel)
end

function build_sample_table!(mid::GridLayout, state::Observable)
    initial = Dict{Symbol,Any}(
        :idx => [0],
        :name => ["(no data)"],
        :date => [""],
        :group => [""],
    )
    table_data = Observable(initial)
    table = Table(mid[1, 1];
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
    table, state::Observable)
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
    ax = Axis(right[2, 1];
        xlabel="Time [s]", ylabel="counts",
        yscale=ytransform[],
        yautolimitmargin=(0.0, 0.05),
        yticklabelspace=56.0, xticklabelspace=18.0,
        tellwidth=false, tellheight=false)
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
        legend_ref=Ref{Any}(nothing),
        right_layout=right)
end

function ensure_count_rate_plot!(panel, sample_obs::Observable)
    isnothing(panel.plot_ref[]) || return
    panel.plot_ref[] = sampleplot!(panel.ax, sample_obs)
    panel.legend_ref[] = Legend(panel.right_layout[2, 2], panel.ax;
        tellheight=false, labelsize=10,
        framevisible=false)
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
    sister_channel::AbstractString)
    ions = default_ions(method_name)
    pair(ion, ch) = KJ.Pairing(ion=ion,
        proxy=something(KJ.channel2proxy(ch), ion),
        channel=ch)
    return KJ.Gmethod(name=method_name,
        P=pair(ions.P, p_channel),
        D=pair(ions.D, d_channel),
        d=pair(ions.d, sister_channel))
end

function build_ratio_panel!(right::GridLayout,
    sample_obs::Observable,
    method::Observable,
    numerators::Observable,
    denominator::Observable)
    ctrls = right[3, 1:2] = GridLayout()
    Label(ctrls[1, 1], "Method"; halign=:right, tellwidth=true)
    method_menu = Menu(ctrls[1, 2];
        options=method_names(), default="Lu-Hf", width=90)
    Label(ctrls[1, 3], "Parent (P)"; halign=:right, tellwidth=true)
    p_menu = Menu(ctrls[1, 4]; options=["(P)"], width=150)
    Label(ctrls[1, 5], "Daughter (D)"; halign=:right, tellwidth=true)
    d_menu = Menu(ctrls[1, 6]; options=["(D)"], width=150)
    Label(ctrls[1, 7], "Sister (S)"; halign=:right, tellwidth=true)
    sister_menu = Menu(ctrls[1, 8]; options=["(d)"], width=150)
    Label(ctrls[1, 9], ""; tellwidth=false)
    colgap!(ctrls, 8)

    rowsize!(right, 3, Fixed(36))

    plots = right[4, 1:2] = GridLayout()
    axkw = (; xlabel="Time [s]", ylabel="ratio",
        yautolimitmargin=(0.0, 0.05),
        yticklabelspace=42.0, xticklabelspace=18.0,
        tellwidth=false, tellheight=false)
    ax_pd = Axis(plots[1, 1]; title="P / D", axkw...)
    ax_sd = Axis(plots[1, 2]; title="S / D", axkw...)
    for ax in (ax_pd, ax_sd)
        Makie.deactivate_interaction!(ax, :rectanglezoom)
    end

    panel = (; ax_pd, ax_sd,
        plot_ref=Ref{Any}(nothing),
        method_menu, p_menu, d_menu, sister_menu)

    # Block per-menu callbacks while a method change seeds all three
    # selections; otherwise apply_method! fires three times in a row.
    suppressing = Ref(false)

    function apply_method!()
        suppressing[] && return
        any(m -> m.selection[] === nothing, (p_menu, d_menu, sister_menu)) && return
        # KJ naming: uppercase D is daughter, lowercase d is sister.
        P_ch = p_menu.selection[]::String
        D_ch = d_menu.selection[]::String
        d_ch = sister_menu.selection[]::String
        m_name = method_menu.selection[]::String
        method[] = build_method(m_name, P_ch, D_ch, d_ch)
        # Match KJ.averat: both numerators share D as denominator.
        numerators[] = [P_ch, d_ch]
        denominator[] = D_ch
        autolimits!(ax_pd)
        autolimits!(ax_sd)
    end

    on(method_menu.selection) do sel
        sel === nothing && return
        samp = sample_obs[]
        isnothing(samp) && return
        chans = KJ.getChannels(samp)
        sug = suggest_channel_indices(sel, chans)
        suppressing[] = true
        for (menu, idx) in zip((p_menu, d_menu, sister_menu), (sug.P, sug.D, sug.d))
            menu.i_selected[] = idx
        end
        suppressing[] = false
        apply_method!()
    end

    for menu in (p_menu, d_menu, sister_menu)
        on(_ -> apply_method!(), menu.selection)
    end

    return panel
end

function ensure_ratio_plot!(panel, sample_obs::Observable,
    numerators::Observable,
    denominator::Observable,
    samp::KJ.Sample)

    chans = KJ.getChannels(samp)

    if panel.p_menu.options[] == ["(P)"]
        sug = suggest_channel_indices(panel.method_menu.selection[], chans)
        for (menu, idx) in zip((panel.p_menu, panel.d_menu, panel.sister_menu),
                               (sug.P,        sug.D,        sug.d))
            menu.options[] = chans
            menu.i_selected[] = idx
        end
    end

    if isnothing(panel.plot_ref[])
        # numerators carries [P_channel, d_channel]; one element per panel.
        pd_num = map(n -> isempty(n) ? String[] : [n[1]], numerators)
        sd_num = map(n -> length(n) >= 2 ? [n[2]] : String[], numerators)
        panel.plot_ref[] = (
            ratioplot!(panel.ax_pd, sample_obs; numerators=pd_num, denominator=denominator),
            ratioplot!(panel.ax_sd, sample_obs; numerators=sd_num, denominator=denominator),
        )
    end
    return
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
    state[] = run
    return
end

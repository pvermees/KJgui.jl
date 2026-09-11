# UI for the isobaric interference corrections defined in interferences.jl.
# Split from that file because it refers to `BottomPanelBase`, which gui.jl
# defines, while gui.jl needs the spec types at parse time.


"""
Interferences popup: one section per P/D/d role, mirroring the targets KJ's
`addInterference` state offers, with the poly- and mono-isotopic corrections
of its `interferenceType` state.

Poly rows follow KJ's derivation: the user picks the channel and
`channel2proxy` says which isotope it measures, with an explicit proxy asked
for only when that fails. Every row reports the ratio KJ will actually
multiply by, checked against the constants KJ bundles separately, since a
disagreement otherwise just scales the correction silently.
"""
struct InterferencePopup
    modal::Modal
    bp::BottomPanelBase
    add_menus::Dict{Symbol,Makie.Menu}
    mono_buttons::Dict{Symbol,Makie.Button}
    # Widgets a rebuild creates for the configured rows. Blocks built inside
    # the modal's Subfigure are not reachable through `fig.content`, so the
    # per-row menus and remove buttons are indexed here by
    # `(role, position in that role's specs, field)`.
    row_menus::Dict{Tuple{Symbol,Int,Symbol},Makie.Menu}
    row_buttons::Dict{Tuple{Symbol,Int},Makie.Button}
    # Mono calibration-group boxes, keyed by `(role, position, group name)`.
    standard_boxes::Dict{Tuple{Symbol,Int,String},Makie.Checkbox}
end

"State the rows of one role's section are built from."
struct InterferenceContext
    popup::InterferencePopup
    role::Symbol
    target::String
    target_channel::String
    channels::Vector{String}
    groups::Vector{String}
end

const BAD_COLOR = RGBf(0.75, 0.10, 0.10)
const GOOD_COLOR = RGBf(0.20, 0.45, 0.20)
const MUTED_COLOR = RGBf(0.45, 0.45, 0.45)

"""
The role's pairing on the panel's current method, i.e. the target KJ's
`addInterference` state picks. `nothing` when no geochronology method is
loaded, since only a `Gmethod` has interferences.
"""
function role_pairing(bp::BottomPanelBase, role::Symbol)
    m = bp.method_obs[]
    m isa KJ.Gmethod || return nothing
    return role_pairing(m, role)
end

"Target isotope of a role, i.e. the nuclide whose mass can be interfered with."
function role_target(bp::BottomPanelBase, role::Symbol)
    pairing = role_pairing(bp, role)
    return isnothing(pairing) ? "" : pairing.proxy
end

"Channel the role's target is measured on, e.g. `\"Hf176 -> 258\"` for Lu-Hf D."
function role_channel(bp::BottomPanelBase, role::Symbol)
    pairing = role_pairing(bp, role)
    return isnothing(pairing) ? "" : pairing.channel
end

specs_for(bp::BottomPanelBase, role::Symbol) =
    get(bp.interferences[], role, AbstractInterferenceSpec[])

function set_specs!(bp::BottomPanelBase, role::Symbol, specs)
    d = copy(bp.interferences[])
    if isempty(specs)
        delete!(d, role)
    else
        d[role] = Vector{AbstractInterferenceSpec}(specs)
    end
    bp.interferences[] = d   # triggers rebuild_method!
    return
end

"""
Add the poly correction for `ion`, defaulting its proxy channel the way
[`default_proxy_channel`](@ref) does.
"""
function add_interference!(bp::BottomPanelBase, role::Symbol, ion::AbstractString)
    specs = copy(specs_for(bp, role))
    any(s -> s isa InterferenceSpec && s.ion == ion, specs) && return
    channel = default_proxy_channel(ion, role_channel(bp, role), bp.channels_obs[])
    push!(specs, InterferenceSpec(ion; channel = channel))
    set_specs!(bp, role, specs)
    return
end

"""
Add an unconfigured mono correction for the user to fill in, unless one is
already waiting — repeated clicks would otherwise stack blank rows.
"""
function add_mono_interference!(bp::BottomPanelBase, role::Symbol)
    specs = copy(specs_for(bp, role))
    any(s -> s isa MonoInterferenceSpec && isempty(s.channel), specs) && return
    push!(specs, MonoInterferenceSpec())
    set_specs!(bp, role, specs)
    return
end

function remove_interference!(bp::BottomPanelBase, role::Symbol, idx::Integer)
    specs = copy(specs_for(bp, role))
    checkbounds(Bool, specs, idx) || return
    deleteat!(specs, idx)
    set_specs!(bp, role, specs)
    return
end

function replace_interference!(bp::BottomPanelBase, role::Symbol, idx::Integer,
                               spec::AbstractInterferenceSpec)
    specs = copy(specs_for(bp, role))
    checkbounds(Bool, specs, idx) || return
    specs[idx] = spec
    set_specs!(bp, role, specs)
    return
end

"""
Ratio KJ will apply for `spec`, and whether it survives the cross-check
against the bundled reference constants.
"""
function ratio_label(spec::InterferenceSpec)
    isempty(spec.proxy) && return ("proxy unknown", :unknown)
    status, applied, reference = ratio_check(spec.ion, spec.proxy)
    status === :invalid && return ("no ratio for $(spec.ion)/$(spec.proxy)", :bad)
    ratio = "$(spec.ion)/$(spec.proxy) = $(round(applied, sigdigits = 5))"
    status === :ok && return (ratio * "  ✓", :good)
    status === :unchecked && return (ratio * "  (unverified)", :unknown)
    # Report the over/under-correction the right way round: `applied/reference`
    # below 1 means the correction is too *small* by its reciprocal.
    over = applied > reference
    scale = round(over ? applied / reference : reference / applied, sigdigits = 3)
    return (ratio * "  ✗ reference $(round(reference, sigdigits = 5)), " *
            "correction $(scale)× too $(over ? "large" : "small")", :bad)
end

status_color(kind::Symbol) =
    kind === :bad ? BAD_COLOR : kind === :good ? GOOD_COLOR : MUTED_COLOR

function build_interference_popup!(fig::Figure, bp::BottomPanelBase)
    # No backdrop dismissal: this panel is dense with dropdowns, and a click
    # that lands just outside one would otherwise discard the configuration
    # in progress. Closing is explicit, via the × in the header.
    modal = Modal(fig; min_size = (700, 200), max_size = (760, 660),
                  dismiss_on_backdrop_click = false,
                  title = "Interference corrections")
    popup = InterferencePopup(modal, bp, Dict{Symbol,Makie.Menu}(),
                              Dict{Symbol,Makie.Button}(),
                              Dict{Tuple{Symbol,Int,Symbol},Makie.Menu}(),
                              Dict{Tuple{Symbol,Int},Makie.Button}(),
                              Dict{Tuple{Symbol,Int,String},Makie.Checkbox}())
    rebuild!(popup)
    # The available targets, channels and groups all move when the method or
    # the loaded run changes. Rebuilding deletes and recreates every row, so
    # only do it while the panel is on screen — `open_with_defaults!` rebuilds
    # from current state on the way in, which covers whatever changed while it
    # was closed (loading a run, switching method).
    onany(bp.interferences, bp.channels_obs, bp.method_obs,
          bp.group_rm_assignments) do _...
        isopen(modal) && rebuild!(popup)
        return
    end
    return popup
end

"Diagnostic line under a row, if the configuration has a problem."
function problem_row!(sf, ctx::InterferenceContext, spec::AbstractInterferenceSpec,
                      row::Int)
    problem = interference_problem(spec, ctx.target_channel, ctx.channels)
    isnothing(problem) && return row
    row += 1
    # `halign` places the wrapped block; `justification` aligns the lines
    # inside it. Without the latter a wrapped message centres, which both
    # orphans the last line and makes this row start at a different x than
    # the unwrapped ratio line above it.
    Label(sf.layout[row, 2:5], problem; halign = :left, justification = :left,
          fontsize = 9, color = BAD_COLOR, word_wrap = true, tellwidth = false)
    return row
end

"""
Rows for one poly correction: the proxy channel, the isotope KJ derives from
it, and the resulting ratio.
"""
function spec_rows!(sf, ctx::InterferenceContext, idx::Int, spec::InterferenceSpec,
                    row::Int)
    bp = ctx.popup.bp
    row += 1
    Label(sf.layout[row, 1], "− $(spec.ion) via"; halign = :right, fontsize = 11,
          tellwidth = true)

    options = proxy_channel_options(spec.ion, ctx.channels)
    cmenu = Menu(sf.layout[row, 2:4]; options = options,
                 default = spec.channel in options ? spec.channel : nothing,
                 fontsize = 10, searchable = true, prompt = "choose a channel…")
    ctx.popup.row_menus[(ctx.role, idx, :channel)] = cmenu
    on(cmenu.selection) do sel
        sel isa AbstractString || return
        sel == spec.channel && return
        # Re-derive the proxy, as KJ does on every channel choice.
        replace_interference!(bp, ctx.role, idx,
                              InterferenceSpec(spec.ion; channel = sel))
    end

    del = Button(sf.layout[row, 5]; label = "remove", width = 70, height = 24,
                 fontsize = 10)
    ctx.popup.row_buttons[(ctx.role, idx)] = del
    on(_ -> remove_interference!(bp, ctx.role, idx), del.clicks)

    if isempty(spec.channel)
        # Nothing measured yet, so nothing to derive a proxy from or report a
        # ratio for. `problem_row!` below says a channel is still needed.
    elseif isempty(spec.proxy)
        # KJ's `setInterferenceProxy` fallback: it could not map the channel to
        # an isotope, so the user says which one it measures.
        row += 1
        Label(sf.layout[row, 1], "measures"; halign = :right, fontsize = 10,
              tellwidth = true)
        options = proxy_candidates(spec.ion)
        pmenu = Menu(sf.layout[row, 2:4]; options = options, default = nothing,
                     fontsize = 10, prompt = "which isotope?")
        ctx.popup.row_menus[(ctx.role, idx, :proxy)] = pmenu
        on(pmenu.selection) do sel
            sel isa AbstractString || return
            replace_interference!(bp, ctx.role, idx,
                                  InterferenceSpec(spec.ion, sel, spec.channel))
        end
    else
        row += 1
        text, kind = ratio_label(spec)
        Label(sf.layout[row, 2:5], "measures $(spec.proxy):  " * text;
              halign = :left, fontsize = 9, color = status_color(kind),
              tellwidth = false)
    end

    return problem_row!(sf, ctx, spec, row)
end

"""
Rows for one mono correction: the interfering channel X and the Y / YO pair
its production rate is inferred from, plus the groups to calibrate on.
"""
function spec_rows!(sf, ctx::InterferenceContext, idx::Int,
                    spec::MonoInterferenceSpec, row::Int; groups_per_row = 4)
    bp = ctx.popup.bp
    row += 1
    Label(sf.layout[row, 1], "− mono"; halign = :right, fontsize = 11,
          tellwidth = true)

    fields = ((:channel, spec.channel, "X (interfering)"),
              (:metal, spec.metal, "Y (metal)"),
              (:oxide, spec.oxide, "YO (oxide)"))
    for (col, (field, current, prompt)) in enumerate(fields)
        menu = Menu(sf.layout[row, col + 1]; options = ctx.channels,
                    default = current in ctx.channels ? current : nothing,
                    fontsize = 9, searchable = true, prompt = prompt, width = 165)
        ctx.popup.row_menus[(ctx.role, idx, field)] = menu
        on(menu.selection) do sel
            sel isa AbstractString || return
            sel == current && return
            updated = MonoInterferenceSpec(
                channel = field === :channel ? sel : spec.channel,
                metal = field === :metal ? sel : spec.metal,
                oxide = field === :oxide ? sel : spec.oxide,
                standards = spec.standards)
            replace_interference!(bp, ctx.role, idx, updated)
        end
    end

    del = Button(sf.layout[row, 5]; label = "remove", width = 70, height = 24,
                 fontsize = 10)
    ctx.popup.row_buttons[(ctx.role, idx)] = del
    on(_ -> remove_interference!(bp, ctx.role, idx), del.clicks)

    row += 1
    Label(sf.layout[row, 2:5], "correction is X × YO / Y, calibrated on:";
          halign = :left, fontsize = 9, color = MUTED_COLOR, tellwidth = false)

    row += 1
    if isempty(ctx.groups)
        Label(sf.layout[row, 2:5], "assign sample groups first";
              halign = :left, fontsize = 9, color = MUTED_COLOR, tellwidth = false)
    else
        picker = GridLayout(sf.layout[row, 2:5]; halign = :left)
        for (i, group) in enumerate(ctx.groups)
            # Wrap instead of growing one row past the modal's width.
            r, col = fldmod1(i, groups_per_row)
            cb = Checkbox(picker[r, 2col - 1]; checked = group in spec.standards)
            ctx.popup.standard_boxes[(ctx.role, idx, group)] = cb
            Label(picker[r, 2col], group; fontsize = 9, halign = :left)
            on(cb.checked) do checked
                standards = checked ? union(spec.standards, [group]) :
                                      setdiff(spec.standards, [group])
                Set(standards) == Set(spec.standards) && return
                replace_interference!(bp, ctx.role, idx,
                                      MonoInterferenceSpec(channel = spec.channel,
                                                           metal = spec.metal,
                                                           oxide = spec.oxide,
                                                           standards = standards))
            end
        end
        colgap!(picker, 4)
    end

    return problem_row!(sf, ctx, spec, row)
end

"The add controls closing a role's section: a poly ion menu and a mono button."
function add_controls!(sf, ctx::InterferenceContext, row::Int)
    bp = ctx.popup.bp
    known = interference_candidates(ctx.target)
    configured = Set(s.ion for s in specs_for(bp, ctx.role) if s isa InterferenceSpec)
    available = filter(!in(configured), known)

    row += 1
    Label(sf.layout[row, 1], "add:"; halign = :right, fontsize = 10, tellwidth = true)
    if isempty(available)
        mass = nuclide_mass(ctx.target)
        note = !isempty(known) ? "all known interferences configured" :
            isnothing(mass) ? "nothing interferes with $(ctx.target)" :
            "nothing interferes at mass $mass"
        Label(sf.layout[row, 2:3], note; halign = :left, fontsize = 9,
              color = MUTED_COLOR, tellwidth = false)
    else
        amenu = Menu(sf.layout[row, 2:3]; options = available, default = nothing,
                     fontsize = 10, prompt = "interfering isotope…")
        ctx.popup.add_menus[ctx.role] = amenu
        on(amenu.selection) do sel
            sel isa AbstractString || return
            add_interference!(bp, ctx.role, sel)
        end
    end

    # Mono corrections are never listed by `TUIgetInterferences`: the
    # interfering species is an oxide, not an isotope at the target mass.
    mono = Button(sf.layout[row, 4]; label = "+ mono", width = 80, height = 24,
                  fontsize = 10)
    ctx.popup.mono_buttons[ctx.role] = mono
    on(_ -> add_mono_interference!(bp, ctx.role), mono.clicks)
    return row
end

function rebuild!(p::InterferencePopup)
    bp = p.bp
    empty!(p.add_menus)
    empty!(p.mono_buttons)
    empty!(p.row_menus)
    empty!(p.row_buttons)
    empty!(p.standard_boxes)
    channels = collect(bp.channels_obs[])
    groups = sort!(collect(keys(bp.group_rm_assignments[])))
    replace_content!(p.modal) do sf
        row = 0
        for role in INTERFERENCE_ROLES
            target = role_target(bp, role)
            isempty(target) && continue
            target_channel = role_channel(bp, role)
            ctx = InterferenceContext(p, role, target, target_channel, channels, groups)
            row += 1
            Label(sf.layout[row, 1:5], "$role — $target measured on $target_channel";
                  halign = :left, fontsize = 12, font = :bold, tellwidth = false)
            for (idx, spec) in enumerate(specs_for(bp, role))
                row = spec_rows!(sf, ctx, idx, spec, row)
            end
            row = add_controls!(sf, ctx, row)
        end
        if row == 0
            Label(sf.layout[1, 1], "Load data and pick a method first.";
                  halign = :left, fontsize = 11, tellwidth = false)
        end
        colgap!(sf.layout, 8)
        rowgap!(sf.layout, 4)
    end
    return
end

open_with_defaults!(p::InterferencePopup) = (rebuild!(p); open!(p.modal); p)

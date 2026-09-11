# Re-record the dashboard demo at /sim/Programmieren/GeoChrono/demo.mp4.
#
# =============================================================================
# RULES for this script — future edits must follow them:
#
#   1. **Everything visible in the video must be driven by mouse or keyboard
#      events** (`MouseTo`, `LeftDown/Up/Click`, `KeyDown/Up/Press`).
#      NEVER call `KJgui.*!`, `KJ.*!`, `notify(...)`, `xlims!`, `autolimits!`,
#      `table.i_selected[] = ...`, or any observable-setter directly inside
#      the `events = [...]` list. If a feature needs a script-side mutation
#      to trigger, it's the wrong feature to demo — reach for the mouse/key
#      instead.
#
#   2. `Lazy(_ -> MouseTo(...))` is fine — it's a mouse action whose target
#      is computed at runtime. `Lazy` with side-effect body that mutates
#      state is NOT fine.
#
#   3. Off-camera setup (before `interaction_record` is called) may bootstrap
#      popup refs — see the pre-instantiation block below. Nothing there
#      appears in the video.
#
#   4. When a step uses a modifier key (Ctrl, Shift, …) the on-screen badge
#      wired up below will render the held-key name so the viewer sees why
#      an interaction behaves differently. Don't disable the badge.
# =============================================================================
#
# Drives the GUI through FakeInteraction (from Makie/docs/). Coverage —
# every review item from the A/B/Cat/C rounds is on-screen here:
#
#   [ 1] Initial view — table navigation (A4: no "Tabulate samples")
#   [ 2] Method popup — U-Pb → Lu-Hf; hover so the proxy help text
#        below the role dropdowns is legible (C9)
#   [ 3] Group assign — tag hogsbo_pul-01 as "Hogsbo" (grouping UX)
#   [ 3b] Remove-from-group — re-click the same cell, hit "(sample)"
#        in the picker to clear, then re-tag Hogsbo (B7)
#   [ 4] LCS group fill-in — tag hogsbo_pul-02, sibling propagation
#   [ 4b] Tag NIST612p as the NIST612 group — Process needs a mass-bias
#        standard as well as a fractionation one.
#   [ 5] References popup — set NIST612p's role to "Mass bias" (a
#        glass-backed group defaults to "None" so it cannot silently join
#        the fractionation fit)
#   [ 6] Add ratio plot — popup → Apply (default P+S vs D)
#   [ 7] Combined ↔ Split mode toggle
#   [ 8] Window drag — resize the signal window by dragging its edge
#   [ 8b] t0 drag — grab the gray t0 marker and shift it (B5)
#   [ 8c] Multi-part window — append a second bwin segment (C10)
#   [ 8d] Channels popup — toggle a hidden channel back ON (A1 redesign
#        of the channel key)
#   [ 8e] Time-axis outlier — double-click on the count-rate plot,
#        red ✗ appears on the trace (A2 + C11)
#   [ 8f] Interference corrections — mirrors KJ's TUI flow. Add the Lu176
#        interference on D (channel picked, proxy derived); the applied
#        ratio is flagged red against KJ's own reference constants. Swap to
#        the on-mass channel to trigger the mass-shift warning, swap back,
#        then add and remove a mono-isotopic correction with its X / Y / YO
#        channels and calibration group.
#   [ 9] Process — KJ.process! runs; the biplot section only becomes
#        visible now that fit_obs is populated (A3)
#   [ 9b] Biplot outlier — double-click a biplot point (A2 on biplot)
#   [10] Zoom + next sample — final scrub through the run
#   [C1] Concentration workflow — Method popup switches to Cmethod,
#        the P/D/d rows collapse and an internal-standard picker takes
#        their place inside the popup. Pick Al27→27, Apply.
#   [C2] Tag NIST612p rows as the NIST612 RM group (picker rebuilds
#        to the glass table on method switch).
#   [C3] Process → Cfit; spinner animates during the fit.
#   [C4] Switch back to Lu-Hf + re-Process so the closing shot is a
#        fresh Gfit isochron.

using Revise, KJgui, GLMakie, Makie
import KJ

isdefined(Main, :FakeInteraction) ||
    include(joinpath(@__DIR__, "..", "..", "Makie", "docs", "fake_interaction.jl"))
using .FakeInteraction: Wait, WaitUntil, MouseTo, LeftClick, LeftDown, LeftUp,
                        Lazy, KeyDown, KeyUp

# Hidden GLMakie screen — `interaction_record` needs the screen open to
# grab the framebuffer, but visible=true lets GLFW poll the real mouse
# and clobber the synthetic positions set by FakeInteraction.
GLMakie.activate!(; visible = false, framerate = 30)

result = KJgui.run_gui(path = joinpath(@__DIR__, "..", "test", "Lu-Hf"))
resize!(result.fig, 1920, 1080)
screen = display(result.fig)
sleep(0.6)
# Detach GLMakie's `MousePositionUpdater` so it stops polling the real
# cursor and clobbering synthetic positions set by FakeInteraction.
Makie.disconnect!(screen, Makie.mouse_position)
result.fig.scene.events.hasfocus[] = false

# Off-camera setup (runs before `interaction_record` starts, so it's NOT
# in the video): eagerly instantiate the lazily-built popups so their
# `layoutobservables.computedbbox` is populated. Without this,
# `block_center(popup.close_btn)` at events-construction time would deref
# a `nothing` popup ref. Everything visible in the recording is driven
# strictly by mouse/keyboard events below.
notify(result.method_btn.clicks); sleep(0.2)
close!(result.method_popup_ref[].modal)
KJgui.ensure_popup!(result.bot_panel)
close!(result.bot_panel.popup_ref[].modal)
notify(result.channels_btn.clicks); sleep(0.2)
close!(result.channels_popup_ref[].modal)
notify(result.refs_btn.clicks); sleep(0.2)
close!(result.refs_panel.modal)
notify(result.interference_btn.clicks); sleep(0.2)
close!(result.interference_popup_ref[].modal)
sleep(0.2)

# Off-camera JIT warm-up. The first `KJ.process!` of each method type
# compiles a large chunk of KJ, which the recording would otherwise spend
# ~a minute of spinner on per Process step. Run both once on a throwaway
# copy of the run so the demo's own state is untouched.
let warm = deepcopy(result.state[])
    for s in warm
        startswith(s.sname, "hogsbo_pul") && (s.group = "hogsbo_pul")
        startswith(s.sname, "NIST612p") && (s.group = "NIST612")
    end
    gm = KJ.Gmethod(name = "Lu-Hf",
                    groups = Dict("hogsbo_pul" => "Hogsbo", "NIST612" => "NIST612"),
                    P = KJ.Pairing(ion = "Lu176", proxy = "Lu175",
                                   channel = "Lu175 -> 175"),
                    D = KJ.Pairing(ion = "Hf176", channel = "Hf176 -> 258"),
                    d = KJ.Pairing(ion = "Hf177", proxy = "Hf178",
                                   channel = "Hf178 -> 260"),
                    standards = Set(["hogsbo_pul"]))
    KJ.Calibration!(gm; standards = Set(["NIST612"]))
    KJ.process!(warm, gm)
    cm = KJ.Cmethod(warm; internal = ("Al27 -> 27", nothing),
                    groups = Dict("NIST612" => "NIST612"))
    KJ.process!(warm, cm)
end
sleep(0.2)

fig    = result.fig
table  = result.table
bp     = result.bot_panel
top    = result.top_panel
biplot = result.biplot_panel

# Held-key badge: renders the name of any currently-held modifier(s) as a
# bold overlay near the top of the figure. Wired to Makie's keyboard event
# stream — no polling — so the badge appears the instant a `KeyDown` event
# fires and disappears on `KeyUp`.
const KEY_LABELS = Dict(
    Makie.Keyboard.left_control  => "Ctrl",
    Makie.Keyboard.right_control => "Ctrl",
    Makie.Keyboard.left_shift    => "Shift",
    Makie.Keyboard.right_shift   => "Shift",
    Makie.Keyboard.left_alt      => "Alt",
    Makie.Keyboard.right_alt     => "Alt",
)
key_badge_text = Observable(" ")
on(Makie.events(fig).keyboardbutton) do _
    state = Makie.events(fig).keyboardstate
    names = unique(String[KEY_LABELS[k] for k in state if haskey(KEY_LABELS, k)])
    key_badge_text[] = isempty(names) ? " " : join(names, " + ")
end
Makie.text!(fig.scene, key_badge_text;
    position = Point2f(960, 1030),
    space    = :pixel,
    align    = (:center, :top),
    fontsize = 42,
    font     = :bold,
    color    = RGBAf(0.85, 0.15, 0.15, 1.0),
    strokecolor = :white,
    strokewidth = 3,
    overdraw = true)

btns       = [c for c in fig.content if c isa Makie.Button]
next_btn   = first(b for b in btns if b.label[] == "▶")
prev_btn   = first(b for b in btns if b.label[] == "◀")

method_pop = result.method_popup_ref[]
addr_pop   = bp.popup_ref[]
picker     = result.group_picker

block_center(block) = FakeInteraction.relative_pos(block, (0.5, 0.5))

# Column 4 (`group`) cell centre. Column widths are [40, 140, 180, 100], so
# the `group` column centre sits at x_offset = 40+140+180 + 50 = 410 inside
# the table's bbox. Row N's centre is `(N - 0.5) * rh` below the header.
function group_cell_pos(table, row::Int)
    bb  = table.layoutobservables.computedbbox[]
    hdr = table.header_height[]
    rh  = table.row_height[]
    x   = bb.origin[1] + 410.0
    top = bb.origin[2] + bb.widths[2] - hdr
    return Point2f(x, top - (row - 0.5) * rh)
end

# Name-column cell centre — clicking here selects the row without opening
# the group picker (only column 4 fires `on_cell_click`).
function name_cell_pos(table, row::Int)
    bb  = table.layoutobservables.computedbbox[]
    hdr = table.header_height[]
    rh  = table.row_height[]
    x   = bb.origin[1] + 110.0          # centre of the `name` column
    top = bb.origin[2] + bb.widths[2] - hdr
    return Point2f(x, top - (row - 0.5) * rh)
end

# Menu dropdown geometry (mirrors Makie's :auto branch in menu.jl).
function option_strip_height(menu)
    fs  = menu.fontsize[]
    pad = menu.textpadding[]
    return Float32(fs + pad[3] + pad[4])
end
function menu_option_pos(menu, idx::Integer)
    bb = menu.layoutobservables.computedbbox[]
    h  = option_strip_height(menu)
    n  = length(collect(menu.options[]))
    x  = bb.origin[1] + bb.widths[1] / 2
    # Mirror Makie's own direction heuristic (menu.jl:66-79). The viewport
    # is `blockscene.viewport` — for a top-level menu that's the whole
    # figure, for a Modal-hosted menu it's the Modal's content region.
    # Compare bbox to viewport POSITION (not size) so both cases work.
    vp = menu.blockscene.viewport[]
    below = bb.origin[2] - vp.origin[2]
    above = (vp.origin[2] + vp.widths[2]) - (bb.origin[2] + bb.widths[2])
    list_h = n * h
    down = below >= list_h || below > above
    # An upward list keeps reading order, so option 1 is at the TOP of the
    # stack — farthest from the cell — and option `idx` sits
    # `n - idx + 0.5` strips above the menu, not `idx - 0.5`.
    y = down ? bb.origin[2] - (idx - 0.5) * h :
               (bb.origin[2] + bb.widths[2]) + (n - idx + 0.5) * h
    return Point2f(x, y)
end
function menu_select_events(menu, target_label; pre_wait = 0.25, post_wait = 0.4)
    opts = collect(menu.options[])
    label_of(o) = o isa Pair ? string(first(o)) :
                  o isa Tuple ? string(first(o)) : string(o)
    idx = findfirst(o -> label_of(o) == target_label, opts)
    isnothing(idx) && error("Menu has no option labelled $(target_label)")
    return [
        MouseTo(block_center(menu)), LeftClick(), Wait(pre_wait),
        MouseTo(menu_option_pos(menu, idx)), LeftClick(), Wait(post_wait),
    ]
end

iface_pop() = result.interference_popup_ref[]

# Centre of a Modal's close ×. `body_rect` is internal, but the content
# Subfigure's bbox is inset from it by `contentpadding` on three sides and
# additionally by `header_height` at the top, so the header band and the ×
# within it are recoverable from the outside.
function modal_close_pos(m::Makie.Modal)
    sf  = m.subfigure.layoutobservables.computedbbox[]
    pad = Float32(m.contentpadding[])
    hh  = Float32(m.header_height[])
    right = sf.origin[1] + sf.widths[1] + pad
    top   = sf.origin[2] + sf.widths[2] + pad + hh
    return Point2f(right - hh / 2, top - hh / 2)
end

# Menu whose options only exist once a popup has been rebuilt, so both the
# menu and the option index have to be resolved at event time.
function lazy_menu_option(menu_f, label)
    return FakeInteraction.Lazy(_ -> begin
        menu = menu_f()
        opts = collect(menu.options[])
        idx = findfirst(o -> string(o) == label, opts)
        isnothing(idx) && error("Menu has no option labelled $(label)")
        MouseTo(menu_option_pos(menu, idx))
    end)
end

# Type a query into a searchable Menu and take the first match. This is how
# the channel menus are meant to be used — a run has more channels than the
# dropdown shows at once.
function search_menu_events(menu_f, query; settle = 1.0)
    return [
        FakeInteraction.Lazy(_ -> MouseTo(block_center(menu_f()))),
        LeftClick(), Wait(0.45),
        FakeInteraction.TypeText(query), Wait(0.5),
        FakeInteraction.KeyPress(Makie.Keyboard.enter), Wait(settle),
    ]
end

current_pop() = result.method_popup_ref[]
method_button(name) = first(b for b in current_pop().method_buttons
                                if b.label[] == name)
apply_btn() = current_pop().apply_btn
internal_menu() = current_pop().internal_menu
rm_button(name)     = first(b for b in picker.rm_buttons
                                if b.label[] == name)

# The References panel lays out one row per group (excluding the "sample"
# catch-all), sorted, so `role_menus[i]` belongs to `groups[i]`.
function role_menu_for(prefix::AbstractString)
    groups = filter(!=("sample"), sort(unique(s.group for s in result.state[])))
    i = findfirst(g -> startswith(g, prefix), groups)
    isnothing(i) && error("no group starting with $(prefix)")
    return result.refs_panel.role_menus[i]
end

# Map axis data-x → figure-pixel-x via the axis's CURRENT finallimits + the
# scene's pixel viewport. Avoids `Makie.project` which can hang or give bad
# y-coords on log-scaled axes during a record loop.
function ax_x_to_pixel(ax, dx::Real)
    lims = ax.finallimits[]
    vp   = ax.scene.viewport[]
    frac = (Float64(dx) - lims.origin[1]) / lims.widths[1]
    return Float32(vp.origin[1] + frac * vp.widths[1])
end

# Pixel y in the middle of the axis's viewport — used for vertical-edge drag.
function ax_y_mid(ax)
    vp = ax.scene.viewport[]
    return Float32(vp.origin[2] + vp.widths[2] / 2)
end

# Run a side-effect now, then wait `s` so the renderer can flush.
do_after(s::Real; f) = FakeInteraction.Lazy(_ -> (f(); Wait(s)))

# Map axis data-(x,y) → figure-pixel via linear interpolation off
# `finallimits` + the scene's pixel viewport. Mirrors `ax_x_to_pixel` for
# the 2-D case; needed for biplot (data-coord) targeting.
function ax_data_pos(ax, dx::Real, dy::Real)
    lims = ax.finallimits[]
    vp   = ax.scene.viewport[]
    fx = (Float64(dx) - lims.origin[1]) / lims.widths[1]
    fy = (Float64(dy) - lims.origin[2]) / lims.widths[2]
    return Point2f(vp.origin[1] + fx * vp.widths[1],
                   vp.origin[2] + fy * vp.widths[2])
end



# Targets for the LCS-expansion step.
pul_rows = findall(s -> startswith(s.sname, "hogsbo_pul - "), result.state[])

events = [
    Wait(0.8),

    # [1] Initial view: poke a few table rows to show navigation
    MouseTo(name_cell_pos(table, 3)), LeftClick(), Wait(0.5),
    MouseTo(name_cell_pos(table, 7)), LeftClick(), Wait(0.5),

    # [2] Method popup: switch U-Pb → Lu-Hf. Extra hover-Wait lets viewers
    # read the proxy-explainer help text below the role dropdowns (C9).
    MouseTo(block_center(result.method_btn)), LeftClick(), Wait(0.8),
    MouseTo(block_center(method_button("U-Pb"))),  LeftClick(), Wait(1.4),
    MouseTo(block_center(method_button("Lu-Hf"))), LeftClick(), Wait(1.4),
    MouseTo(block_center(apply_btn())),   LeftClick(), Wait(0.8),

    # [3] Group selection: tag first hogsbo_pul sample as "Hogsbo"
    MouseTo(group_cell_pos(table, pul_rows[1])), LeftClick(), Wait(0.8),
    Lazy(_ -> MouseTo(block_center(rm_button("Hogsbo")))),
    LeftClick(), Wait(0.8),

    # [3b] Remove-from-group (B7): re-click the same cell, choose
    # "(sample)" from the picker to clear the assignment, then re-tag
    # Hogsbo so the LCS fill-in step below still has a seed row.
    MouseTo(group_cell_pos(table, pul_rows[1])), LeftClick(), Wait(0.6),
    Lazy(_ -> MouseTo(block_center(rm_button("(sample)")))),
    LeftClick(), Wait(0.8),
    MouseTo(group_cell_pos(table, pul_rows[1])), LeftClick(), Wait(0.5),
    Lazy(_ -> MouseTo(block_center(rm_button("Hogsbo")))),
    LeftClick(), Wait(0.8),

    # [4] Group fill-in: tagging a sibling fires the LCS prefix expansion
    MouseTo(group_cell_pos(table, pul_rows[2])), LeftClick(), Wait(0.6),
    Lazy(_ -> MouseTo(block_center(rm_button("Hogsbo")))),
    LeftClick(), Wait(1.0),

    # [4b] Tag the NIST612p analyses too. Processing needs a mass-bias
    # standard as well as a fractionation one; without it `Calibration!`
    # never runs and the isochron intercepts blow up far outside the data.
    FakeInteraction.Lazy(_ -> begin
        nist = findall(s -> startswith(s.sname, "NIST612p"), result.state[])
        MouseTo(group_cell_pos(table, nist[1]))
    end),
    LeftClick(), Wait(0.7),
    FakeInteraction.Lazy(_ -> MouseTo(block_center(rm_button("NIST612")))),
    LeftClick(), Wait(0.7),
    FakeInteraction.Lazy(_ -> begin
        nist = findall(s -> startswith(s.sname, "NIST612p"), result.state[])
        MouseTo(group_cell_pos(table, nist[2]))
    end),
    LeftClick(), Wait(0.6),
    FakeInteraction.Lazy(_ -> MouseTo(block_center(rm_button("NIST612")))),
    LeftClick(), Wait(1.0),

    # [5] References popup (B6): both groups now show up as rows with an RM
    # dropdown and a role. A glass-backed group defaults to "None" so it
    # cannot silently join the fractionation fit — set NIST612p to
    # "Mass bias", which is the role KJ's own Lu-Hf method gives it.
    MouseTo(block_center(result.refs_btn)), LeftClick(), Wait(1.4),
    FakeInteraction.Lazy(_ -> MouseTo(block_center(role_menu_for("NIST612")))),
    LeftClick(), Wait(0.5),
    lazy_menu_option(() -> role_menu_for("NIST612"), "Mass bias"),
    LeftClick(), Wait(1.2),
    # Backdrop click dismisses the modal (dismiss_on_backdrop_click=true).
    MouseTo(Point2f(80, 80)), LeftClick(), Wait(0.6),

    # [6] Add ratio plot (default P + S vs D)
    MouseTo(name_cell_pos(table, 1)), LeftClick(), Wait(0.5),
    MouseTo(block_center(bp.add_btn)), LeftClick(), Wait(0.7),
    MouseTo(block_center(addr_pop.apply_btn)), LeftClick(), Wait(0.9),

    # [7] Combined ↔ Split mode toggle
    menu_select_events(bp.mode_menu, "Split")...,
    Wait(0.6),
    menu_select_events(bp.mode_menu, "Combined")...,
    Wait(0.5),

    # [8] Window drag: drag swin's right edge inward
    FakeInteraction.Lazy(_ -> begin
        samp = result.sample_obs[]
        t = Float64(samp.dat[samp.swin[1][2], 1])    # current right-edge time
        MouseTo(Point2f(ax_x_to_pixel(top.ax, t), ax_y_mid(top.ax)))
    end),
    Wait(0.4),                              # hover so the orange highlight appears
    LeftDown(), Wait(0.05),
    FakeInteraction.Lazy(_ -> begin
        samp = result.sample_obs[]
        t = Float64(samp.dat[samp.swin[1][2], 1]) - 12.0
        MouseTo(Point2f(ax_x_to_pixel(top.ax, t), ax_y_mid(top.ax)))
    end),
    Wait(0.05), LeftUp(), Wait(0.8),

    # [8b] t0 drag (B5): grab the gray t0 marker and shift it by a few
    # rows. The drag interaction remaps bwin/swin around the new t0.
    FakeInteraction.Lazy(_ -> begin
        samp = result.sample_obs[]
        t = Float64(samp.t0)
        MouseTo(Point2f(ax_x_to_pixel(top.ax, t), ax_y_mid(top.ax)))
    end),
    Wait(0.4),                                  # hover to show t0 highlight
    LeftDown(), Wait(0.05),
    FakeInteraction.Lazy(_ -> begin
        samp = result.sample_obs[]
        t = Float64(samp.t0) + 2.0              # shift right by ~2 s
        MouseTo(Point2f(ax_x_to_pixel(top.ax, t), ax_y_mid(top.ax)))
    end),
    Wait(0.05), LeftUp(), Wait(0.6),

    # [8c] Multi-part window (C10): hold Ctrl and drag on the count-rate
    # axis in empty space — the `:window_drag` handler sees
    # `Makie.ispressed(ax, Keyboard.left_control)` at leftdragstart and
    # calls `append_window!` before continuing as a right-edge drag on
    # the new segment. Fully driven through the interaction system so
    # the cursor visibly does the work.
    FakeInteraction.Lazy(_ -> begin
        samp = result.sample_obs[]
        b_end_row = samp.bwin[1][2]
        t0_row    = KJgui.nearest_row(samp, Float64(samp.t0))
        anchor_row = clamp(b_end_row + 3, 1, t0_row - 4)
        anchor_t   = Float64(samp.dat[anchor_row, 1])
        MouseTo(Point2f(ax_x_to_pixel(top.ax, anchor_t), ax_y_mid(top.ax)))
    end),
    Wait(0.3),
    KeyDown(Makie.Keyboard.left_control), Wait(0.05),
    LeftDown(), Wait(0.05),
    FakeInteraction.Lazy(_ -> begin
        samp = result.sample_obs[]
        t0_row = KJgui.nearest_row(samp, Float64(samp.t0))
        grow_t = Float64(samp.dat[clamp(t0_row - 2, 1, size(samp.dat, 1)), 1])
        MouseTo(Point2f(ax_x_to_pixel(top.ax, grow_t), ax_y_mid(top.ax)))
    end),
    Wait(0.05), LeftUp(), Wait(0.05),
    KeyUp(Makie.Keyboard.left_control),
    Wait(1.0),                                          # linger so the new blue span is legible

    # [8d] Channels popup: open, toggle a hidden channel ON to make its
    # trace appear on the count-rate plot, close (demos the C-key/redesign
    # and A1 redesign of the channel-key panel).
    MouseTo(block_center(result.channels_btn)), LeftClick(), Wait(0.8),
    FakeInteraction.Lazy(_ -> begin
        cp = result.channels_popup_ref[]
        # Pick the first OFF checkbox in the ON column and click it.
        on_cbs = [w for w in cp.widgets if w isa Makie.Checkbox][1:2:end]
        target = something(findfirst(cb -> !cb.checked[], on_cbs), 1)
        MouseTo(block_center(on_cbs[target]))
    end),
    LeftClick(), Wait(0.8),
    MouseTo(Point2f(80, 80)),
    LeftClick(), Wait(0.6),

    # [8e] Time-axis outlier: double-click on the count-rate plot. Places
    # a red ✗ marker on the raw traces (A2 + C11 — mirrors biplot behavior).
    FakeInteraction.Lazy(_ -> begin
        samp = result.sample_obs[]
        target_t = Float64(samp.dat[samp.swin[1][1] + 5, 1])
        vp = top.ax.scene.viewport[]
        py = Float32(vp.origin[2] + 0.6 * vp.widths[2])
        MouseTo(Point2f(ax_x_to_pixel(top.ax, target_t), py))
    end),
    Wait(0.2), LeftClick(), Wait(0.05), LeftClick(), Wait(0.9),

    # [8f] Interference corrections. The panel mirrors KJ's TUI flow: one
    # section per P/D/d target, and for a poly-isotopic correction the user
    # picks the CHANNEL the proxy is measured on while KJ derives the isotope
    # from it (`channel2proxy`).
    MouseTo(block_center(result.interference_btn)), LeftClick(), Wait(1.4),

    # Only mass 176 has interferers in this run, so only D offers a menu.
    # Adding Lu176 defaults its proxy channel to `Lu175 -> 257`, matching the
    # target's reaction-cell mass shift. The row then reports the ratio KJ
    # will actually multiply by — in red, because `settings/iratio.csv` holds
    # a copy of the Re185 abundance on the Lu175 row, making the correction
    # 62.7x too large.
    FakeInteraction.Lazy(_ -> MouseTo(block_center(iface_pop().add_menus[:D]))),
    LeftClick(), Wait(0.6),
    lazy_menu_option(() -> iface_pop().add_menus[:D], "Lu176"),
    LeftClick(), Wait(2.4),

    # Pick the on-mass channel instead by typing into the searchable menu.
    # Its mass shift no longer matches the target's, and the panel says so
    # rather than silently over-subtracting by orders of magnitude.
    search_menu_events(() -> iface_pop().row_menus[(:D, 1, :channel)],
                       "175 -> 175"; settle = 2.4)...,

    # Back to the mass-shift-matched channel; that warning clears.
    search_menu_events(() -> iface_pop().row_menus[(:D, 1, :channel)],
                       "257"; settle = 1.8)...,

    # A mono-isotopic correction on P: the interfering oxide is measured on
    # channel X and corrected as X x YO / Y, calibrated on a sample group.
    FakeInteraction.Lazy(_ -> MouseTo(block_center(iface_pop().mono_buttons[:P]))),
    LeftClick(), Wait(1.2),
    search_menu_events(() -> iface_pop().row_menus[(:P, 1, :channel)], "Yb172")...,
    search_menu_events(() -> iface_pop().row_menus[(:P, 1, :metal)], "175 -> 175")...,
    search_menu_events(() -> iface_pop().row_menus[(:P, 1, :oxide)], "257")...,
    # Tick the hogsbo group as the standard KJ fits the oxide rate on.
    FakeInteraction.Lazy(_ -> begin
        boxes = iface_pop().standard_boxes
        key = first(k for k in keys(boxes) if startswith(k[3], "hogsbo"))
        MouseTo(block_center(boxes[key]))
    end),
    LeftClick(), Wait(2.0),

    # Drop the mono row again — the Lu176 correction is the one that belongs
    # in this Lu-Hf run, and it stays applied through Process below.
    FakeInteraction.Lazy(_ -> MouseTo(block_center(iface_pop().row_buttons[(:P, 1)]))),
    LeftClick(), Wait(1.4),

    # Close via the header × — this panel deliberately does not dismiss on a
    # backdrop click, so a near-miss can't discard the configuration.
    FakeInteraction.Lazy(_ -> MouseTo(modal_close_pos(iface_pop().modal))),
    LeftClick(), Wait(0.9),

    # [9] Process — KJ.process! produces a fit. Because the biplot row
    # is gated on `!isnothing(fit_obs[])`, this is the moment the
    # isochron biplot row snaps into view (A3).
    MouseTo(block_center(result.process_btn)), LeftClick(),
    WaitUntil(() -> !isnothing(result.fit[])), Wait(1.2),

    # Click a standard-sample row in the table so the fit overlay has
    # data on the ratio plot. Table's `on(table.i_selected)` handler
    # already autolimits every axis on sample change — no script-side
    # `autolimits!` needed.
    FakeInteraction.Lazy(_ -> begin
        idx = findfirst(s -> s.group != "sample", result.state[])
        MouseTo(name_cell_pos(table, something(idx, 1)))
    end),
    LeftClick(), Wait(1.2),

    # [9b] Biplot outlier: now that the biplot is visible (post-A3),
    # double-click a scatter point to flag it as an outlier — the red ✗
    # is the shared marker style used across raw plots and biplot (A2).
    FakeInteraction.Lazy(_ -> begin
        xs = biplot.plot_ref[].xs[]; ys = biplot.plot_ref[].ys[]
        good = filter(i -> !isnan(xs[i]) && !isnan(ys[i]), eachindex(xs))
        k = good[length(good) ÷ 2]      # middle scatter point
        MouseTo(ax_data_pos(biplot.ax, Float64(xs[k]), Float64(ys[k])))
    end),
    Wait(0.2), LeftClick(), Wait(0.05), LeftClick(), Wait(0.9),

    # [10] Scrub through the run using ▶/◀ so viewers see multiple
    # samples and the auto-swap of fit + biplot per sample.
    MouseTo(block_center(next_btn)), LeftClick(), Wait(0.7),
    LeftClick(), Wait(0.7),
    MouseTo(block_center(prev_btn)), LeftClick(), Wait(0.7),
    LeftClick(), Wait(1.0),

    # [C1] Concentration workflow. Open Method popup → click Concentration.
    # The popup auto-rebuilds as Cmethod in place (P/D/d role rows are
    # replaced by the internal-standard picker). Pick Al27→27, Apply.
    MouseTo(block_center(result.method_btn)), LeftClick(), Wait(0.8),
    FakeInteraction.Lazy(_ -> MouseTo(block_center(method_button("Concentration")))),
    LeftClick(), Wait(1.2),
    FakeInteraction.Lazy(_ -> MouseTo(block_center(internal_menu()))),
    LeftClick(), Wait(0.8),
    FakeInteraction.Lazy(_ -> MouseTo(menu_option_pos(internal_menu(),
        findfirst(==("Al27 -> 27"), collect(internal_menu().options[]))))),
    LeftClick(), Wait(0.8),
    FakeInteraction.Lazy(_ -> MouseTo(block_center(apply_btn()))),
    LeftClick(), Wait(1.2),

    # [C2] Tag a NIST612p sample as the NIST612 concentration standard.
    # The group picker's RM list rebuilt on the method switch and now
    # offers glass names (NIST610/612/614/BHVO-2G/BCR-2g).
    FakeInteraction.Lazy(_ -> begin
        idx = findfirst(s -> startswith(s.sname, "NIST612p"), result.state[])
        MouseTo(group_cell_pos(table, something(idx, 1)))
    end),
    LeftClick(), Wait(0.7),
    FakeInteraction.Lazy(_ -> MouseTo(block_center(rm_button("NIST612")))),
    LeftClick(), Wait(0.8),

    # Sibling propagation: tag a second NIST612p row → LCS fill-in.
    FakeInteraction.Lazy(_ -> begin
        nist = findall(s -> startswith(s.sname, "NIST612p"), result.state[])
        MouseTo(group_cell_pos(table, nist[2]))
    end),
    LeftClick(), Wait(0.6),
    FakeInteraction.Lazy(_ -> MouseTo(block_center(rm_button("NIST612")))),
    LeftClick(), Wait(1.0),

    # [C3] Process → Cfit. Spinner animates during the fit, sidebar
    # button flips to "Processing…" and back.
    MouseTo(block_center(result.process_btn)), LeftClick(),
    WaitUntil(() -> result.fit[] isa KJ.Cfit), Wait(1.2),

    # [C4] Back to Lu-Hf and re-Process so the video ends on a fresh
    # Gfit isochron (the Cfit from [C3] doesn't render on the isochron
    # biplot). Clicking Lu-Hf in the Cmethod popup auto-swaps it back
    # to a Gmethod popup; Apply commits the P/D/d defaults + closes.
    MouseTo(block_center(result.method_btn)), LeftClick(), Wait(0.7),
    FakeInteraction.Lazy(_ -> MouseTo(block_center(method_button("Lu-Hf")))),
    LeftClick(), Wait(1.2),
    FakeInteraction.Lazy(_ -> MouseTo(block_center(apply_btn()))),
    LeftClick(), Wait(0.8),

    # [C2] re-tagged the NIST612p rows in concentration mode, where a group
    # is named for the glass rather than the sample prefix. That renamed the
    # group and dropped the role set in [5], so set it again before the
    # closing fit.
    MouseTo(block_center(result.refs_btn)), LeftClick(), Wait(1.2),
    FakeInteraction.Lazy(_ -> MouseTo(block_center(role_menu_for("NIST612")))),
    LeftClick(), Wait(0.5),
    lazy_menu_option(() -> role_menu_for("NIST612"), "Mass bias"),
    LeftClick(), Wait(1.0),
    MouseTo(Point2f(80, 80)), LeftClick(), Wait(0.6),

    MouseTo(block_center(result.process_btn)),     LeftClick(),
    WaitUntil(() -> !isnothing(result.fit[])), Wait(1.2),

    # Land on a standard row for the closing shot so the isochron
    # + dashed fit lines on the ratio plot are both visible.
    FakeInteraction.Lazy(_ -> begin
        idx = findfirst(s -> startswith(s.sname, "hogsbo_pul"), result.state[])
        MouseTo(name_cell_pos(table, something(idx, 1)))
    end),
    LeftClick(), Wait(1.5),
]

video_path = get(ENV, "KJGUI_DEMO_PATH",
                 joinpath(@__DIR__, "..", "..", "..", "demo.mp4"))
FakeInteraction.interaction_record(fig, video_path, events;
                                   fps = 30, px_per_unit = 1)
println("Saved: ", video_path)

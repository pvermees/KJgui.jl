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
#   [ 5] References popup — open, close (B6 layout cleanup)
#   [ 6] Add ratio plot — popup → Apply (default P+S vs D)
#   [ 7] Combined ↔ Split mode toggle
#   [ 8] Window drag — resize the signal window by dragging its edge
#   [ 8b] t0 drag — grab the gray t0 marker and shift it (B5)
#   [ 8c] Multi-part window — append a second bwin segment (C10)
#   [ 8d] Channels popup — toggle a hidden channel back ON (A1 redesign
#        of the channel key)
#   [ 8e] Time-axis outlier — double-click on the count-rate plot,
#        red ✗ appears on the trace (A2 + C11)
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

isdefined(Main, :FakeInteraction) ||
    include(joinpath(@__DIR__, "..", "..", "Makie", "docs", "fake_interaction.jl"))
using .FakeInteraction: Wait, MouseTo, LeftClick, LeftDown, LeftUp, Lazy,
                        KeyDown, KeyUp

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
function menu_dropdown_direction(menu)
    bb = menu.layoutobservables.computedbbox[]
    viewport_h = menu.blockscene.viewport[].widths[2]
    list_h = length(collect(menu.options[])) * option_strip_height(menu)
    below = bb.origin[2]
    above = viewport_h - (bb.origin[2] + bb.widths[2])
    return (below >= list_h || below > above) ? :down : :up
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
    y = down ? bb.origin[2] - (idx - 0.5) * h :
               (bb.origin[2] + bb.widths[2]) + (idx - 0.5) * h
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

current_pop() = result.method_popup_ref[]
method_button(name) = first(b for b in current_pop().method_buttons
                                if b.label[] == name)
apply_btn() = current_pop().apply_btn
internal_menu() = current_pop().internal_menu
rm_button(name)     = first(b for b in picker.rm_buttons
                                if b.label[] == name)

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

    # [5] References popup (B6): the group we just seeded now shows up
    # as a row with an RM dropdown. Open, linger so the cleaned-up
    # layout is visible, then close.
    MouseTo(block_center(result.refs_btn)), LeftClick(), Wait(1.2),
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

    # [9] Process — KJ.process! produces a fit. Because the biplot row
    # is gated on `!isnothing(fit_obs[])`, this is the moment the
    # isochron biplot row snaps into view (A3).
    MouseTo(block_center(result.process_btn)), LeftClick(), Wait(3.0),

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
    MouseTo(block_center(result.process_btn)), LeftClick(), Wait(3.0),

    # [C4] Back to Lu-Hf and re-Process so the video ends on a fresh
    # Gfit isochron (the Cfit from [C3] doesn't render on the isochron
    # biplot). Clicking Lu-Hf in the Cmethod popup auto-swaps it back
    # to a Gmethod popup; Apply commits the P/D/d defaults + closes.
    MouseTo(block_center(result.method_btn)), LeftClick(), Wait(0.7),
    FakeInteraction.Lazy(_ -> MouseTo(block_center(method_button("Lu-Hf")))),
    LeftClick(), Wait(1.2),
    FakeInteraction.Lazy(_ -> MouseTo(block_center(apply_btn()))),
    LeftClick(), Wait(0.8),
    MouseTo(block_center(result.process_btn)),     LeftClick(), Wait(3.0),

    # Land on a standard row for the closing shot so the isochron
    # + dashed fit lines on the ratio plot are both visible.
    FakeInteraction.Lazy(_ -> begin
        idx = findfirst(s -> startswith(s.sname, "hogsbo_pul"), result.state[])
        MouseTo(name_cell_pos(table, something(idx, 1)))
    end),
    LeftClick(), Wait(1.5),
]

video_path = joinpath(@__DIR__, "..", "..", "..", "demo.mp4")
FakeInteraction.interaction_record(fig, video_path, events;
                                   fps = 30, px_per_unit = 1)
println("Saved: ", video_path)

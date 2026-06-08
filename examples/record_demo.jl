# Re-record the dashboard demo at /sim/Programmieren/GeoChrono/demo.mp4.
#
# Uses the FakeInteraction module from the Makie docs to drive the GUI with
# a synthetic mouse. Walks through the new popup-based UX:
#
#   * Table-row navigation
#   * Y-scale menu (inline)
#   * Method popup (method list on the left, channel role menus on the right,
#     ion summary at the bottom)
#   * References popup (auto-preselected RMs from group names)
#   * "+ Add ratio plot" popup (N/D checkboxes per channel)
#   * Linked-axis zoom across the ratio stack + count-rate overview
#   * Process (button shows "Processing…" while KJ.process! runs)

using Revise, KJgui, GLMakie, Makie

include(joinpath(@__DIR__, "..", "..", "Makie", "docs", "fake_interaction.jl"))
using .FakeInteraction

result = KJgui.run_gui(path=joinpath(@__DIR__, "..", "test", "Lu-Hf"))
resize!(result.fig, 1920, 1080)
sleep(0.4)  # let the first draw settle so bboxes are valid

# Eagerly instantiate every popup so its widgets exist (with valid bboxes)
# before we ask FakeInteraction to click them. We immediately close each one;
# the demo will re-open them with synthetic clicks.
notify(result.method_btn.clicks); sleep(0.2)
result.method_popup_ref[].popup.close!()
notify(result.refs_btn.clicks); sleep(0.2)
result.refs_popup_ref[].popup.close!()
result.bot_panel.ensure_popup!()           # add-ratio-plot popup
result.bot_panel.popup_ref[].popup.close!()
sleep(0.2)

btns       = [c for c in result.fig.content if c isa Makie.Button]
menus      = [c for c in result.fig.content if c isa Makie.Menu]
prev_btn   = first(b for b in btns if b.label[] == "◀")
next_btn   = first(b for b in btns if b.label[] == "▶")
add_btn    = result.bot_panel.add_btn      # "+ Add ratio plot"
process_b  = result.process_btn

method_pop = result.method_popup_ref[]
refs_pop   = result.refs_popup_ref[]
addr_pop   = result.bot_panel.popup_ref[]

function row_pos(table, row::Int)
    bb  = table.layoutobservables.computedbbox[]
    hdr = table.header_height[]
    rh  = table.row_height[]
    x   = bb.origin[1] + bb.widths[1] * 0.5
    top = bb.origin[2] + bb.widths[2] - hdr
    return Point2f(x, top - (row - 0.5) * rh)
end

center(block) = FakeInteraction.relative_pos(block, (0.5, 0.5))

# fontsize + vertical padding — Makie builds each option row as
# textheight + textpadding[3] + textpadding[4].
function option_strip_height(menu)
    fs  = menu.fontsize[]
    pad = menu.textpadding[]
    return Float32(fs + pad[3] + pad[4])
end

# Mirror Makie's `:auto` branch in menu.jl: open downward unless there's
# more usable space above.
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
    y  = if menu_dropdown_direction(menu) === :down
        bb.origin[2] - (idx - 0.5) * h
    else
        (bb.origin[2] + bb.widths[2]) + n * h - (idx - 0.5) * h
    end
    return Point2f(x, y)
end

function menu_select_events(menu, target_label; pre_wait=0.25, post_wait=0.35)
    opts = collect(menu.options[])
    label_of(o) = o isa Pair  ? string(first(o)) :
                  o isa Tuple ? string(first(o)) :
                  string(o)
    idx = findfirst(o -> label_of(o) == target_label, opts)
    isnothing(idx) && error("Menu has no option labelled $(target_label)")
    return [
        MouseTo(center(menu)),
        LeftClick(),
        Wait(pre_wait),
        MouseTo(menu_option_pos(menu, idx)),
        LeftClick(),
        Wait(post_wait),
    ]
end

# Pick out a method-list button by its label.
method_button(name) = first(b for b in method_pop.method_buttons if b.label[] == name)

# Find the N or D checkbox for a given channel in the add-ratio popup. The
# popup's tracked rows correspond to channels_obs[] in order.
function nbox(channel::AbstractString)
    chans = result.bot_panel.channels_obs[]
    i = findfirst(==(channel), chans)
    isnothing(i) && error("Channel $channel not in $chans")
    return addr_pop.n_boxes[i]
end
function dbox(channel::AbstractString)
    chans = result.bot_panel.channels_obs[]
    i = findfirst(==(channel), chans)
    isnothing(i) && error("Channel $channel not in $chans")
    return addr_pop.d_boxes[i]
end

# Run an arbitrary side-effect mid-script, then wait `seconds` so the
# renderer has time to draw the change before the next event fires. Lazy
# is replaced by whatever event we return — Wait() is what we want.
do_after(seconds; f) = FakeInteraction.Lazy(_ -> (f(); Wait(seconds)))

events = [
    Wait(0.5),

    # ── Table-row clicks ─────────────────────────────────────────────────
    MouseTo(row_pos(result.table, 3)),  LeftClick(), Wait(0.6),
    MouseTo(row_pos(result.table, 7)),  LeftClick(), Wait(0.6),
    MouseTo(row_pos(result.table, 14)), LeftClick(), Wait(0.6),

    # ── Prev / Next ──────────────────────────────────────────────────────
    MouseTo(center(next_btn)),
    LeftClick(), Wait(0.25),
    LeftClick(), Wait(0.25),
    LeftClick(), Wait(0.5),
    MouseTo(center(prev_btn)),
    LeftClick(), Wait(0.25),
    LeftClick(), Wait(0.6),

    # ── Y-scale menu (inline, 3 options) ────────────────────────────────
    menu_select_events(menus[1], "linear")...,
    menu_select_events(menus[1], "sqrt")...,
    menu_select_events(menus[1], "log")...,

    # ── Method popup ─────────────────────────────────────────────────────
    MouseTo(center(result.method_btn)), LeftClick(), Wait(0.6),
    MouseTo(center(method_button("U-Pb"))), LeftClick(), Wait(0.7),
    MouseTo(center(method_button("Lu-Hf"))), LeftClick(), Wait(0.7),
    MouseTo(center(method_pop.apply_btn)), LeftClick(), Wait(0.6),

    # ── References popup ────────────────────────────────────────────────
    MouseTo(center(result.refs_btn)), LeftClick(), Wait(0.9),
    MouseTo(center(refs_pop.popup.close_btn)), LeftClick(), Wait(0.5),

    # ── + Add ratio plot popup ──────────────────────────────────────────
    MouseTo(center(add_btn)), LeftClick(), Wait(0.6),
    MouseTo(center(addr_pop.apply_btn)), LeftClick(), Wait(0.7),

    # Second ratio plot to show the linked x-axis.
    MouseTo(center(add_btn)), LeftClick(), Wait(0.5),
    MouseTo(center(nbox("Lu175 -> 175"))), LeftClick(), Wait(0.15),
    MouseTo(center(nbox("Hf178 -> 260"))), LeftClick(), Wait(0.15),
    MouseTo(center(addr_pop.apply_btn)),    LeftClick(), Wait(0.8),

    # ── Linked-axis zoom ────────────────────────────────────────────────
    do_after(0.9; f=() -> Makie.xlims!(result.top_panel.ax, 28, 50)),
    do_after(0.9; f=() -> Makie.xlims!(result.top_panel.ax, 0, 65)),

    # ── Process ─────────────────────────────────────────────────────────
    MouseTo(center(process_b)), LeftClick(), Wait(2.5),

    # ── Final flourish ──────────────────────────────────────────────────
    MouseTo(row_pos(result.table, 25)), LeftClick(), Wait(0.6),
    MouseTo(row_pos(result.table, 1)),  LeftClick(), Wait(1.2),
]

video_path = joinpath(@__DIR__, "..", "..", "..", "demo.mp4")
FakeInteraction.interaction_record(result.fig, video_path, events;
                                   fps=30, px_per_unit=1)
println("Saved: ", video_path)

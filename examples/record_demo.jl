# Re-record the dashboard demo at /sim/Programmieren/GeoChrono/demo.mp4.
#
# Drives the GUI through FakeInteraction (from Makie/docs/). Mirrors the
# 10-step coverage in `walkthrough_routing.jl`:
#
#   1. Initial view
#   2. Method selection — switch U-Pb → back to Lu-Hf via the popup
#   3. Group selection — click a table cell, pick "Hogsbo" from the picker
#   4. Group fill-in — tag a sibling sample → LCS prefix expansion
#   5. Add ratio plot — popup → Apply (default P+S vs D)
#   6. Combined ↔ Split mode toggle
#   7. Window drag — resize the signal window by dragging its edge
#   8. Outlier toggle — double-click a biplot point (red ✗ appears)
#   9. Process — KJ.process! runs, fit overlay appears
#  10. Zoom + next sample

using Revise, KJgui, GLMakie, Makie

isdefined(Main, :FakeInteraction) ||
    include(joinpath(@__DIR__, "..", "..", "Makie", "docs", "fake_interaction.jl"))
using .FakeInteraction: Wait, MouseTo, LeftClick, LeftDown, LeftUp, Lazy

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

# Eagerly instantiate popups so their bboxes are valid before FakeInteraction
# tries to compute pixel positions for the clicks.
notify(result.method_btn.clicks); sleep(0.2)
close!(result.method_popup_ref[].popup)
result.bot_panel.ensure_popup!()
close!(result.bot_panel.popup_ref[].popup)
sleep(0.2)

fig    = result.fig
table  = result.table
bp     = result.bot_panel
top    = result.top_panel
biplot = result.biplot_panel

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
    y  = if menu_dropdown_direction(menu) === :down
        bb.origin[2] - (idx - 0.5) * h
    else
        (bb.origin[2] + bb.widths[2]) + n * h - (idx - 0.5) * h
    end
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

method_button(name) = first(b for b in method_pop.method_buttons
                                if b.label[] == name)
rm_button(name)     = first(b for b in picker.rm_buttons[]
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

# Diagnostic: log each Hogsbo click + picker visibility change.
let h = first(b for b in picker.rm_buttons[] if b.label[] == "Hogsbo")
    on(h.clicks) do n
        println("    [Hogsbo.clicks = $n]  popup open = $(isopen(picker.popup))  ",
                "mp = $(result.fig.scene.events.mouseposition[])")
    end
    on(picker.popup.scene.parent.visible) do v
        println("    [picker overlay.visible = $v]  ",
                "title = $(picker.sample_lbl.text[])")
    end
end


events = [
    Wait(0.8),

    # [1] Initial view: poke a few table rows to show navigation
    MouseTo(name_cell_pos(table, 3)), LeftClick(), Wait(0.5),
    MouseTo(name_cell_pos(table, 7)), LeftClick(), Wait(0.5),

    # [2] Method popup: switch U-Pb → Lu-Hf
    MouseTo(block_center(result.method_btn)), LeftClick(), Wait(0.8),
    MouseTo(block_center(method_button("U-Pb"))),  LeftClick(), Wait(0.6),
    MouseTo(block_center(method_button("Lu-Hf"))), LeftClick(), Wait(0.6),
    MouseTo(block_center(method_pop.apply_btn)),   LeftClick(), Wait(0.8),

    # [3] Group selection: tag first hogsbo_pul sample as "Hogsbo"
    MouseTo(group_cell_pos(table, pul_rows[1])), LeftClick(), Wait(0.8),
    Lazy(_ -> MouseTo(block_center(rm_button("Hogsbo")))),
    LeftClick(), Wait(0.8),

    # [4] Group fill-in: tagging a sibling fires the LCS prefix expansion
    MouseTo(group_cell_pos(table, pul_rows[2])), LeftClick(), Wait(0.6),
    Lazy(_ -> MouseTo(block_center(rm_button("Hogsbo")))),
    LeftClick(), Wait(1.0),

    # [5] Add ratio plot (default P + S vs D)
    MouseTo(name_cell_pos(table, 1)), LeftClick(), Wait(0.5),
    MouseTo(block_center(bp.add_btn)), LeftClick(), Wait(0.7),
    MouseTo(block_center(addr_pop.apply_btn)), LeftClick(), Wait(0.9),

    # [6] Combined ↔ Split mode toggle
    menu_select_events(bp.mode_menu, "Split")...,
    Wait(0.6),
    menu_select_events(bp.mode_menu, "Combined")...,
    Wait(0.5),

    # [7] Window drag: drag swin's right edge inward
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

    # [8] Outlier toggle: double-click a biplot scatter point. Two
    # rapid LeftClicks let Makie's state machine generate a real
    # `leftdoubleclick` MouseEvent, which the :toggle_outlier
    # interaction picks up.
    FakeInteraction.Lazy(_ -> begin
        xs = biplot.plot_ref[].xs[]; ys = biplot.plot_ref[].ys[]
        good = filter(i -> !isnan(xs[i]) && !isnan(ys[i]), eachindex(xs))
        k = good[length(good) ÷ 2]      # middle scatter point
        MouseTo(ax_data_pos(biplot.ax, Float64(xs[k]), Float64(ys[k])))
    end),
    Wait(0.2), LeftClick(), Wait(0.05), LeftClick(), Wait(0.9),

    # [9] Process — KJ.process! produces a fit
    MouseTo(block_center(result.process_btn)), LeftClick(), Wait(3.0),
    # Land on a standard sample so the fit overlay has data on the ratio plot.
    do_after(0.4; f = () -> begin
        idx = findfirst(s -> s.group != "sample", result.state[])
        isnothing(idx) || (result.table.i_selected[] = idx)
    end),
    do_after(0.8; f = () -> Makie.autolimits!(biplot.ax)),

    # [10] Zoom + next sample
    do_after(1.0; f = () -> Makie.xlims!(top.ax, 28, 50)),
    do_after(1.0; f = () -> Makie.xlims!(top.ax, 0, 70)),
    MouseTo(block_center(next_btn)), LeftClick(), Wait(0.5),
    LeftClick(), Wait(0.5),
    MouseTo(block_center(prev_btn)), LeftClick(), Wait(0.5),
    LeftClick(), Wait(1.0),
]

video_path = joinpath(@__DIR__, "..", "..", "..", "demo.mp4")
FakeInteraction.interaction_record(fig, video_path, events;
                                   fps = 30, px_per_unit = 1)
println("Saved: ", video_path)

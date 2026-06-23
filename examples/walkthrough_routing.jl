# Comprehensive end-to-end walkthrough: drives the dashboard through
# synthetic mouse/keyboard events, exercising every interactive feature
# and snapshotting each step into `/tmp/walkthrough/`.
#
# Run from the project root:
#     julia --project examples/walkthrough_routing.jl

using Revise, KJgui, GLMakie, Makie
using KJ: Gfit

GLMakie.activate!(visible = false)
GLMakie.closeall()

const FRAMES_DIR = "/tmp/walkthrough"
isdir(FRAMES_DIR) || mkdir(FRAMES_DIR)
foreach(rm, filter(p -> endswith(p, ".png"),
                   readdir(FRAMES_DIR; join = true)))

const PATH = joinpath(@__DIR__, "..", "test", "Lu-Hf")

# === Event helpers — every state change goes through these so the real
# event-routing/state-machine pipeline runs end to end ===================

function move!(fig, x::Real, y::Real)
    fig.scene.events.mouseposition[] = (Float64(x), Float64(y))
    yield()
end

function click_at!(fig, x::Real, y::Real; settle = 0.06)
    move!(fig, x, y)
    fig.scene.events.mousebutton[] = Makie.MouseButtonEvent(Mouse.left, Mouse.press)
    fig.scene.events.mousebutton[] = Makie.MouseButtonEvent(Mouse.left, Mouse.release)
    sleep(settle)
end

function block_center(block)
    bb = block.layoutobservables.computedbbox[]
    (bb.origin[1] + bb.widths[1] / 2, bb.origin[2] + bb.widths[2] / 2)
end

function click_block!(fig, block; settle = 0.06)
    x, y = block_center(block)
    click_at!(fig, x, y; settle)
end

option_strip_height(menu) =
    Float32(menu.fontsize[] + menu.textpadding[][3] + menu.textpadding[][4])

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
    h = option_strip_height(menu)
    n = length(collect(menu.options[]))
    x = bb.origin[1] + bb.widths[1] / 2
    y = if menu_dropdown_direction(menu) === :down
        bb.origin[2] - (idx - 0.5) * h
    else
        (bb.origin[2] + bb.widths[2]) + n * h - (idx - 0.5) * h
    end
    return (x, y)
end

option_label(o) = o isa Union{Pair, Tuple} ? string(first(o)) : string(o)

function menu_select!(fig, menu, label::AbstractString)
    opts = collect(menu.options[])
    idx = findfirst(o -> option_label(o) == label, opts)
    isnothing(idx) && error("Menu has no option labelled $(label)")
    click_block!(fig, menu)
    sleep(0.18)
    ox, oy = menu_option_pos(menu, idx)
    click_at!(fig, ox, oy; settle = 0.25)
end

function snap!(name::AbstractString, fig::Figure)
    path = joinpath(FRAMES_DIR, name * ".png")
    # `update = false` — Makie's default `update_state_before_display!`
    # path calls `reset_limits!` on every Axis, which would undo any
    # interactive zoom/pan the walkthrough just exercised. Skip it.
    Makie.events(fig).tick[] = Makie.Tick(Makie.OneTimeRenderTick, 0, 0.0, 0.0)
    Makie.save(path, Makie.colorbuffer(fig; update = false))
    println("  → $(basename(path))")
    return path
end

# Inject a MouseEvent straight into an Axis's mouseeventhandle — used for
# operations whose detection needs the state machine (doubleclick / drag)
# rather than raw press/release pairs.
function ax_mouse_event!(ax, type, data_x, data_y; settle = 0.05)
    ev = Makie.MouseEvent(type, 0.0, Point2d(data_x, data_y),
                          Point2f(0, 0), 0.0, Point2d(0, 0), Point2f(0, 0))
    ax.mouseeventhandle.obs[] = ev
    sleep(settle)
end

function ax_scroll!(ax, dx, dy; settle = 0.1)
    ax.scrollevents[] = Makie.ScrollEvent(Float64(dx), Float64(dy))
    sleep(settle)
end


println("Building dashboard…")
result = KJgui.run_gui(path = PATH)
resize!(result.fig, 1700, 1050); sleep(0.4)

fig   = result.fig
table = result.table
bp    = result.bot_panel
top   = result.top_panel
biplot = result.biplot_panel

# One-time autolimits pass so the first snap shows the right viewport.
Makie.update_state_before_display!(fig); sleep(0.2)
snap!("00_initial", fig)


# ===========================================================================
println("\n[1] Method selection — open Method popup and switch to U-Pb then back")
# ===========================================================================

click_block!(fig, result.method_btn; settle = 0.3)
@assert isopen(result.method_popup_ref[].popup)
snap!("01_method_popup_open", fig)

mpopup = result.method_popup_ref[]
# Each method has a Button labelled by its name in the popup's left pane.
method_btn_for(name) = first(b for b in mpopup.method_buttons if b.label[] == name)

click_block!(fig, method_btn_for("U-Pb"); settle = 0.3)
click_block!(fig, mpopup.apply_btn; settle = 0.4)
@assert result.method[].name == "U-Pb"
println("  method → $(result.method[].name)")
snap!("02_method_upb", fig)

# Switch back to Lu-Hf — used by the rest of the walkthrough.
click_block!(fig, result.method_btn; settle = 0.3)
click_block!(fig, method_btn_for("Lu-Hf"); settle = 0.3)
click_block!(fig, mpopup.apply_btn; settle = 0.4)
@assert result.method[].name == "Lu-Hf"
snap!("03_method_luhf", fig)


# ===========================================================================
println("\n[2] Group selection — tag sample 1 as 'Hogsbo' via the group cell")
# ===========================================================================

# The group picker opens via `table.on_cell_click` on column 4. The table
# block's column-4 hit region depends on the block's pixel viewport; rather
# than recompute that we drive the same observable the table itself sets
# on a real click.
# Pick the first two `hogsbo_pul-N` samples — they share the prefix
# `hogsbo_pul - ` so step [3]'s LCS expansion will tag every sibling.
pul_rows = findall(s -> startswith(s.sname, "hogsbo_pul - "), result.state[])
@assert length(pul_rows) >= 2

table.on_cell_click[](table, pul_rows[1], 4, nothing); sleep(0.3)
@assert isopen(result.group_picker.popup)
snap!("04_group_picker_open", fig)

rm_buttons() = result.group_picker.rm_buttons[]
hogsbo_btn() = first(b for b in rm_buttons() if b.label[] == "Hogsbo")
click_block!(fig, hogsbo_btn(); settle = 0.4)
@assert result.state[][pul_rows[1]].group == "Hogsbo"
println("  state[$(pul_rows[1])].group = $(result.state[][pul_rows[1]].group)")
n_hogsbo_after_first = count(s -> s.group == "Hogsbo", result.state[])
@assert n_hogsbo_after_first == 1 "first pick = only the one sample"
snap!("05_first_sample_tagged", fig)


# ===========================================================================
println("\n[3] Group fill-in — tagging a second `hogsbo_pul-*` sample auto-")
println("    extends 'Hogsbo' to every sample sharing the longest common prefix")
# ===========================================================================

table.on_cell_click[](table, pul_rows[2], 4, nothing); sleep(0.3)
click_block!(fig, hogsbo_btn(); settle = 0.4)
n_hogsbo = count(s -> s.group == "Hogsbo", result.state[])
println("  $n_hogsbo samples are now tagged 'Hogsbo' " *
        "(every `hogsbo_pul-N` got the prefix expansion).")
@assert n_hogsbo == length(pul_rows) "LCS expansion should auto-tag every hogsbo_pul sibling"
snap!("06_lcs_expansion", fig)


# ===========================================================================
println("\n[4] Add ratio plot — Apply [P, S] vs D from defaults → one slot")
# ===========================================================================

table.i_selected[] = 1; sleep(0.2)
p_ch, d_ch, s_ch = bp.p_channel[], bp.d_channel[], bp.sister_channel[]

# Eagerly build the popup so its bboxes are valid before we click them.
bp.ensure_popup!(); sleep(0.1); close!(bp.popup_ref[].popup); sleep(0.1)
addr_pop = bp.popup_ref[]

click_block!(fig, bp.add_btn; settle = 0.3)
@assert isopen(addr_pop.popup)
snap!("07_add_popup_open", fig)
click_block!(fig, addr_pop.apply_btn; settle = 0.5)
@assert length(bp.ratio_defs[]) == 1
slot1 = first(bp.ratio_defs[])
@assert sort(slot1.numerators[]) == sort([p_ch, s_ch])
@assert length(slot1.axes) == 1     # Combined → one shared axis
@assert length(slot1.plots) == 2    # ...with both ratio traces
println("  slot: $(slot1.numerators[]) / $(slot1.denominator[])  axes=$(length(slot1.axes))")
snap!("08_combined_default", fig)


# ===========================================================================
println("\n[5] Combined ↔ Split mode toggle")
# ===========================================================================

menu_select!(fig, bp.mode_menu, "Split")
sleep(0.3)
slot1 = first(bp.ratio_defs[])
@assert length(slot1.axes) == 2 "Split → 2 stacked axes inside the same slot"
ax1, ax2 = slot1.axes
@assert ax1.scene.viewport[].origin[1] == ax2.scene.viewport[].origin[1]
@assert ax1.scene.viewport[].origin[2] != ax2.scene.viewport[].origin[2]
snap!("09_split", fig)

menu_select!(fig, bp.mode_menu, "Combined")
sleep(0.3)
@assert length(first(bp.ratio_defs[]).axes) == 1
snap!("10_back_to_combined", fig)


# ===========================================================================
println("\n[6] Window drag — resize swin/bwin by dragging edges on top axis")
# ===========================================================================

samp = result.sample_obs[]
times = samp.dat[!, 1]
old_swin = samp.swin[1]
s_right_t = times[old_swin[2]]
ax_mouse_event!(top.ax, Makie.MouseEventTypes.leftdragstart, s_right_t, 0)
ax_mouse_event!(top.ax, Makie.MouseEventTypes.leftdrag, s_right_t - 12.0, 0)
ax_mouse_event!(top.ax, Makie.MouseEventTypes.leftdragstop, s_right_t - 12.0, 0)
@assert samp.swin[1][2] < old_swin[2]
println("  swin resized: $(old_swin) → $(samp.swin[1])")
snap!("11_swin_resized", fig)


# ===========================================================================
println("\n[7] Outlier toggle — double-click a biplot scatter point")
# ===========================================================================

# Pick a non-zero scatter point and double-click it; recipe re-renders the
# ratio panel with NaN at that row and the biplot adds a red ✗ marker.
xs = biplot.plot_ref[].xs[]
ys = biplot.plot_ref[].ys[]
k = findfirst(i -> !isnan(xs[i]) && !isnan(ys[i]) &&
                    (xs[i] != 0 || ys[i] != 0), eachindex(xs))
ax_mouse_event!(biplot.ax,
                Makie.MouseEventTypes.leftdoubleclick, xs[k], ys[k])
@assert any(samp.dat.outlier) "double-click must have flipped one outlier on"
println("  outliers flagged: $(sum(samp.dat.outlier))")
snap!("12_outlier_flagged", fig)


# ===========================================================================
println("\n[8] Process — runs KJ.process! and overlays the fit")
# ===========================================================================

# Need an RM reference; group_picker already mapped 'Hogsbo' → Hogsbo RM.
result.group_rm_assignments[] = Dict("Hogsbo" => "Hogsbo")
click_block!(fig, result.process_btn; settle = 2.0)
@assert result.fit[] isa Gfit
println("  fit produced: $(typeof(result.fit[]))")

# Land on a standard so the fitted-prediction overlay has data.
std_idx = findfirst(s -> s.group != "sample", result.state[])
result.table.i_selected[] = std_idx; sleep(0.4)

function has_black_overlay(plot_h)
    for c in plot_h.plots
        c isa Makie.Lines || continue
        hasproperty(c, :color) || continue
        col = c.color[]
        is_black = col === :black ||
                   col === Makie.RGBA{Makie.N0f8}(0, 0, 0, 1) ||
                   col === Makie.RGBAf(0, 0, 0, 1)
        is_black || continue
        pts = c[1][]
        pts isa AbstractVector && !isempty(pts) && return true
    end
    return false
end
@assert any(has_black_overlay(p) for s in bp.ratio_defs[] for p in s.plots)
snap!("13_processed_fit_overlay", fig)


# ===========================================================================
println("\n[9] Zoom — scroll on the count-rate axis (modifier-free zoom)")
# ===========================================================================

# The default ScrollZoom needs no modifier key (axis.zoombutton[] is the
# truthy "always on" sentinel). A positive y scroll zooms in.
pre_lims = top.ax.finallimits[]
# Move the mouse over the axis so the ScrollEvent gets routed there.
center = let vp = top.ax.scene.viewport[]
    (vp.origin[1] + vp.widths[1] / 2, vp.origin[2] + vp.widths[2] / 2)
end
move!(fig, center...)
for _ in 1:6; ax_scroll!(top.ax, 0, 3); end
sleep(0.4)
post_lims = top.ax.finallimits[]
println("  x-extent: $(pre_lims.widths[1]) → $(post_lims.widths[1])")
@assert post_lims.widths[1] < pre_lims.widths[1] / 2 "scroll-up should zoom IN substantially"
snap!("14_zoomed", fig)

# Reset for the next step.
Makie.reset_limits!(top.ax); sleep(0.2)


# ===========================================================================
println("\n[10] Next sample — ▶ button advances `table.i_selected`")
# ===========================================================================

btns = [c for c in fig.content if c isa Makie.Button]
next_btn = first(b for b in btns if b.label[] == "▶")
prev_btn = first(b for b in btns if b.label[] == "◀")
i_before = table.i_selected[]
click_block!(fig, next_btn; settle = 0.2)
@assert table.i_selected[] == i_before + 1
println("  i_selected: $i_before → $(table.i_selected[])")
snap!("15_after_next", fig)

# Step back so we end on a clean state.
click_block!(fig, prev_btn; settle = 0.2)
@assert table.i_selected[] == i_before
snap!("16_after_prev", fig)


println("\n✓ All synthetic-event assertions passed")
println("Frames in $FRAMES_DIR")

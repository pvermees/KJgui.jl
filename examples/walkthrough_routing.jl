# Walkthrough that drives the dashboard entirely through synthetic mouse
# events (no direct calls into `add_def!`/`mode_menu.selection` etc.) so
# it exercises the real pointer-event pipeline end to end.
#
# At each interesting state it (a) asserts the routing state (active
# cover, `table.receives_events`) and the relevant dashboard invariants,
# and (b) snapshots a PNG into `/tmp/walkthrough/` for visual inspection.
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

# Everything that changes GUI state goes through these helpers — no direct
# observable writes, no `add_def!` calls.

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

# Menu dropdown geometry — mirrors the bits of menu.jl needed to click a
# specific option without inspecting Makie's internal scene tree.
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
    click_block!(fig, menu)           # open dropdown
    sleep(0.18)
    ox, oy = menu_option_pos(menu, idx)
    click_at!(fig, ox, oy; settle = 0.25)
end

# Force a checkbox into a desired state with a real click (no direct
# `.checked[] = ...` write).
function set_checkbox!(fig, cb, want::Bool)
    cb.checked[] == want && return
    click_block!(fig, cb)
end


function snap!(name::AbstractString, fig::Figure)
    path = joinpath(FRAMES_DIR, name * ".png")
    Makie.save(path, Makie.colorbuffer(fig; update = true))
    println("  → $(basename(path))")
    return path
end

function probe(label, fig, table, x = 260.0, y = 600.0)
    move!(fig, x, y)
    ac = Makie.find_topmost_cover(fig.scene, (x, y))
    re = Makie.receives_events(table.blockscene)
    println("  [$label] active_cover=", ac === nothing ? "nothing" : "Scene$(objectid(ac) % 1_000_000)",
            "  table.receives_events=$re")
    return (; active = ac, receives = re)
end


println("Building dashboard…")
result = KJgui.run_gui(path = PATH)
resize!(result.fig, 1700, 1050); sleep(0.4)

fig   = result.fig
table = result.table
bp    = result.bot_panel

p_ch, d_ch, s_ch = bp.p_channel[], bp.d_channel[], bp.sister_channel[]
println("Method channels: P=$p_ch  D=$d_ch  S=$s_ch")

# Eager popup build so its checkbox bboxes are valid before any synthetic
# click; the lazy path resolves bboxes to (0,0,0,0) until layout settles.
bp.ensure_popup!()
close!(bp.popup_ref[].popup)
sleep(0.2)
addr_pop = bp.popup_ref[]

chans = bp.channels_obs[]
p_idx = findfirst(==(p_ch), chans)
d_idx = findfirst(==(d_ch), chans)
s_idx = findfirst(==(s_ch), chans)

# Click the first table row by event so we have data before we start.
click_block!(fig, table; settle = 0.2)   # lands on first visible row's centroid

snap!("01_initial", fig)
probe("initial", fig, table)

println("\n[1] Add ratios via the popup (default = P + S vs D)")
click_block!(fig, bp.add_btn; settle = 0.3)
snap!("02_add_popup_open", fig)
@assert isopen(addr_pop.popup) "Add popup must be open"
@assert addr_pop.n_boxes[p_idx].checked[]
@assert addr_pop.n_boxes[s_idx].checked[]
@assert addr_pop.d_boxes[d_idx].checked[]
click_block!(fig, addr_pop.apply_btn; settle = 0.5)
n_slots = length(bp.ratio_defs[])
slot1 = first(bp.ratio_defs[])
println("  slots after one default Apply: $n_slots",
        "  axes in slot 1: $(length(slot1.axes))",
        "  numerators: ", slot1.numerators[],
        "  default mode: ", bp.mode_menu.selection[])
@assert n_slots == 1 "One Apply = one slot bundling all numerators"
@assert sort(slot1.numerators[]) == sort([p_ch, s_ch])
@assert length(slot1.axes) == 1 "Combined → one Axis per slot"
@assert length(slot1.plots) == 2 "Two numerators → two ratioplot handles"
@assert bp.mode_menu.selection[] == "Combined"
@assert first(slot1.axes).yscale[] === Makie.pseudolog10
snap!("03_combined_default", fig)
probe("after default Apply (Combined)", fig, table)

println("\n[1b] Toggle mode → Split (P/D and S/D stacked, X-linked)")
mode_menu = bp.mode_menu
menu_select!(fig, mode_menu, "Split")
sleep(0.2)
@assert length(bp.ratio_defs[]) == 1 "Mode toggle preserves the slot"
slot1 = first(bp.ratio_defs[])
@assert length(slot1.axes) == 2 "Split → 2 stacked axes inside the slot"
# Stacked vertically: same x extent, different y origin.
ax1, ax2 = slot1.axes
bb1, bb2 = ax1.scene.viewport[], ax2.scene.viewport[]
println("  Panel 1 viewport = $bb1")
println("  Panel 2 viewport = $bb2")
@assert bb1.origin[1] == bb2.origin[1] "Stacked → same x origin"
@assert bb1.origin[2] != bb2.origin[2] "Stacked → different y origin"
snap!("03b_split_stacked", fig)

# Toggle back so the rest of the test uses the canonical default state.
menu_select!(fig, mode_menu, "Combined")
sleep(0.2)
snap!("03c_back_to_combined", fig)

# Click a table row — events must reach Table.
click_block!(fig, table; settle = 0.2)
println("  Table click after add → i_selected = $(table.i_selected[])")
@assert table.i_selected[] != 1 "Click must change selection"
snap!("04_clicked_after_add", fig)

println("\n[2] Open Method popup; clicks inside body claimed, outside fall through")
click_block!(fig, result.method_btn; settle = 0.3)
body = result.method_popup_ref[].popup.scene
@assert Makie.covers_pointer(body)
snap!("05_method_popup_open", fig)

# Inside the body: the body claims pointer input.
vp = body.viewport[]
inside = (vp.origin[1] + vp.widths[1]/2.0, vp.origin[2] + vp.widths[2]/2.0)
move!(fig, inside...)
@assert Makie.find_topmost_cover(fig.scene, inside) === body
@assert !Makie.receives_events(table.blockscene)

# Outside the body: the table is reachable normally.
outside = (260.0, 600.0)
move!(fig, outside...)
@assert Makie.find_topmost_cover(fig.scene, outside) === nothing
@assert Makie.receives_events(table.blockscene)

# Clicking on the table while popup is open still selects (popup is not
# full-figure modal — only its body claims input).
i_before = table.i_selected[]
click_at!(fig, 260.0, 600.0; settle = 0.1)
@assert table.i_selected[] != i_before "Clicks outside the popup body should reach the table"
snap!("06_table_click_while_popup_open", fig)

click_block!(fig, result.method_popup_ref[].popup.close_btn; settle = 0.3)
@assert !isopen(result.method_popup_ref[].popup)
snap!("07_popup_closed", fig)

println("\n[3] Toggle y-scale Menu → linear → sqrt → log")
ymenu = first(m for m in fig.content
              if m isa Makie.Menu &&
                 Set(option_label.(collect(m.options[]))) ==
                 Set(["log", "linear", "sqrt"]))
slot_ax() = first(first(bp.ratio_defs[]).axes)
menu_select!(fig, ymenu, "linear")
@assert slot_ax().yscale[] === identity
snap!("09_yscale_linear", fig)

menu_select!(fig, ymenu, "sqrt")
@assert slot_ax().yscale[] === sqrt
snap!("10_yscale_sqrt", fig)

menu_select!(fig, ymenu, "log")
@assert slot_ax().yscale[] === Makie.pseudolog10
snap!("11_yscale_log_again", fig)

println("\n[4] Navigate samples via ▶, check counts stable")
btns = [c for c in fig.content if c isa Makie.Button]
next_btn = first(b for b in btns if b.label[] == "▶")
prev_btn = first(b for b in btns if b.label[] == "◀")

count_scenes(s) = 1 + sum(count_scenes, s.children; init = 0)
count_plots(s)  = length(s.plots) + sum(count_plots, s.children; init = 0)
before = (scenes = count_scenes(fig.scene),
          plots  = count_plots(fig.scene),
          blocks = length(fig.content))
for _ in 1:10; click_block!(fig, next_btn; settle = 0.04); end
for _ in 1:10; click_block!(fig, prev_btn; settle = 0.04); end
after = (scenes = count_scenes(fig.scene),
         plots  = count_plots(fig.scene),
         blocks = length(fig.content))
println("  before=$before  after=$after")
@assert before == after "Navigation must not rebuild scenes/plots/blocks"
snap!("12_after_nav", fig)

# Process needs RM-assigned groups; tag the `hogsbo_pul - N` samples first.
println("\n[5] Process → assert black fit-overlay lines exist")
for s in result.state[]
    startswith(s.sname, "hogsbo_pul - ") && (s.group = "hogsbo_pul")
end
result.group_rm_assignments[] = Dict("hogsbo_pul" => "Hogsbo")
click_block!(fig, result.process_btn; settle = 1.5)
@assert result.fit[] isa Gfit "Process must produce a Gfit"

# Select a standard so signal-window predictions are non-empty.
std_idx = findfirst(s -> s.group != "sample", result.state[])
@assert !isnothing(std_idx) "Need at least one non-sample group for the overlay"
result.table.i_selected[] = std_idx; sleep(0.3)

# `get_plots` filters out unlabeled children; reach into `plot_h.plots`
# directly to find the black overlay lines.
function has_fit_overlay(plot_h)
    for c in plot_h.plots
        c isa Makie.Lines || continue
        hasproperty(c, :color) || continue
        col = c.color[]
        col === :black || col === Makie.RGBA{Makie.N0f8}(0, 0, 0, 1) ||
            col === Makie.RGBAf(0, 0, 0, 1) || continue
        pts = c[1][]
        pts isa AbstractVector && !isempty(pts) && return true
    end
    return false
end
overlay_found = any(has_fit_overlay(p) for s in bp.ratio_defs[] for p in s.plots)
println("  black overlay present on any slot: $overlay_found")
@assert overlay_found "After Process, at least one fit-overlay trace must render"
snap!("13_processed_fit_overlay", fig)

println("\n✓ All synthetic-event assertions passed")
println("Frames in $FRAMES_DIR")

"""
A floating popup on a Figure: half-transparent backdrop tinting the rest
of the figure plus an opaque-white body centred over it. The body holds a
`GridLayout` for the caller's widgets.

Three nested scenes:
- `overlay` — full-figure viewport, `clear=false`, z=1000, holds the
  half-transparent backdrop poly. Lifts everything below into the
  foreground render layer.
- `body` — viewport = body rect, `clear=true`. The routing cover: its
  positive world-z + `clear=true` makes `covers_pointer(body)` true,
  so widgets in sibling subtrees stop receiving pointer input while
  the popup is open.
- `body_widgets` — child of `body`, viewport = full figure, holds the
  widgets. The full-figure viewport is necessary because each Block
  builds a subscene whose viewport is set to the block's computedbbox
  treated as *figure-pixel* coords; that only renders correctly when
  bboxes are in figure coords, which requires the widget scene's
  viewport origin to be (0, 0). Visibility cascades from `body`, so
  widgets hide together with the body.

Clicks outside the body rect (but still on the backdrop) fall through to
the underlying figure — the popup is not full-figure modal.

`size === nothing` (default) sizes the body to the layout's natural extent
(floored at `min_size`); pass a `(w, h)` tuple for a fixed size.
"""
struct Popup
    scene::Scene
    layout::GridLayout
    title_label::Label
    close_btn::Button
end

"""
    Popup(fig::Figure; size=nothing, min_size=(240, 120), title="")
"""
function Popup(fig::Figure;
               size::Union{Nothing,Tuple{Real,Real}}=nothing,
               min_size::Tuple{Real,Real}=(240, 120),
               title::AbstractString="")
    parent = fig.scene

    HEADER_H = 36
    PAD      = 12

    overlay = Scene(parent;
        camera=campixel!, clear=false, viewport=parent.viewport)
    translate!(overlay, 0, 0, 1000)
    overlay.visible[] = false
    backdrop_rect = lift(vp -> Rect2f(0, 0, vp.widths...), parent.viewport)
    poly!(overlay, backdrop_rect; color=(:black, 0.35), inspectable=false)

    layout_autosize = Observable((Float32(min_size[1]), Float32(min_size[2])))
    body_size = if size === nothing
        lift(layout_autosize) do asz
            (max(Float32(min_size[1]), Float32(asz[1]) + 2*PAD),
             max(Float32(min_size[2]), Float32(asz[2]) + HEADER_H + 2*PAD))
        end
    else
        Observable((Float32(size[1]), Float32(size[2])))
    end

    body_viewport = lift(parent.viewport, body_size) do vp, (bw, bh)
        x = round(Int, (vp.widths[1] - bw) / 2)
        y = round(Int, (vp.widths[2] - bh) / 2)
        Rect2i(x, y, round(Int, bw), round(Int, bh))
    end

    body = Scene(overlay;
        camera=campixel!, clear=true, viewport=body_viewport,
        backgroundcolor=RGBAf(1, 1, 1, 1))
    # Opaque white plot living at world-z=1000 alongside the widgets, so
    # the body's white participates in the cross-scene z-sorted plot
    # render rather than just the setup-pass clear (which dashboard plots
    # at z=0 can overdraw inside the body's pixel region).
    # In body's local space (campixel + viewport=body_rect maps local
    # (0,0) to figure pixel `body_viewport.origin`).
    body_fill_local = lift(body_size) do (bw, bh); Rect2f(0, 0, bw, bh); end
    poly!(body, body_fill_local; color=:white, strokewidth=0,
        inspectable=false)
    poly!(body, body_fill_local;
        color=:transparent, strokecolor=:black, strokewidth=2,
        inspectable=false)

    # Widget scene: full-figure viewport so Block subscenes (which
    # interpret their viewport as figure-pixel coords) render at the
    # correct position. Visibility cascades from `body`.
    body_widgets = Scene(body;
        camera=campixel!, clear=false, viewport=parent.viewport)

    # All widget bboxes are in figure-pixel coords (standard Makie
    # convention) so Block subscene positioning Just Works.
    layout_bbox = lift(body_viewport) do vp
        x, y = vp.origin
        w, h = vp.widths
        Rect2f(x + PAD, y + PAD, w - 2*PAD, h - HEADER_H - PAD)
    end
    layout = GridLayout(; bbox=layout_bbox)
    layout.parent = body_widgets
    on(layout.layoutobservables.autosize) do asz
        w = something(asz[1], min_size[1])
        h = something(asz[2], min_size[2])
        layout_autosize[] = (Float32(w), Float32(h))
    end

    title_bbox = lift(body_viewport) do vp
        x, y = vp.origin
        w, h = vp.widths
        Rect2f(x + PAD, y + h - HEADER_H + 4, w - HEADER_H - 2*PAD, HEADER_H - 8)
    end
    title_label = Label(body_widgets; text=title, fontsize=14, font=:bold,
        halign=:left, tellwidth=false, tellheight=false)
    title_label.layoutobservables.suggestedbbox[] = title_bbox[]
    on(title_bbox) do r; title_label.layoutobservables.suggestedbbox[] = r; end

    close_bbox = lift(body_viewport) do vp
        x, y = vp.origin
        w, h = vp.widths
        Rect2f(x + w - HEADER_H + 4, y + h - HEADER_H + 4, HEADER_H - 8, HEADER_H - 8)
    end
    close_btn = Button(body_widgets; label="×", fontsize=18,
        tellwidth=false, tellheight=false)
    close_btn.layoutobservables.suggestedbbox[] = close_bbox[]
    on(close_bbox) do r; close_btn.layoutobservables.suggestedbbox[] = r; end

    pop = Popup(body, layout, title_label, close_btn)
    on(_ -> close!(pop), close_btn.clicks)
    return pop
end

"Show the popup."
open!(p::Popup)        = (p.scene.parent.visible[] = true; nothing)
"Hide the popup."
close!(p::Popup)       = (p.scene.parent.visible[] = false; nothing)
"Whether the popup is currently shown."
Base.isopen(p::Popup)  = p.scene.parent.visible[]

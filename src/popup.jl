"""
    Popup(fig::Figure; size=(420, 420), title="")

A floating modal overlay scene on top of `fig`, with its own `GridLayout`
parented to a `campixel!` Scene so any Makie block (Menu, Checkbox, Button,
Label, …) drops into `popup.layout[i, j]` like a normal figure cell.

Borrows the `GridLayout(; bbox=…)` + `layout.parent = scene` trick from
Makie's `Subfigure`: the layout is given an explicit bbox observable, its
parent is the overlay scene, and the bbox follows the popup body so resizes
work.

Returns a NamedTuple with:
- `scene`        the overlay scene
- `layout`       the GridLayout for content (top-aligned, padded)
- `title_label`  Label block for the title
- `close_btn`    × button in the top-right corner; pre-wired to close
- `open!`        function to show the popup
- `close!`       function to hide the popup
- `is_open`      Observable{Bool} mirroring visibility
"""
function Popup(fig::Figure; size::Tuple{Real,Real}=(420, 420), title::AbstractString="")
    parent = fig.scene
    overlay = Scene(parent;
        camera=campixel!, clear=false, viewport=parent.viewport)
    # Push the entire overlay scene above every block in the parent — same
    # trick Menu uses for its dropdown (see makielayout/blocks/menu.jl:93).
    # Without this, sibling Block subscenes drawn later in the tree paint
    # over the popup body and its content.
    translate!(overlay, 0, 0, 1000)
    overlay.visible[] = false

    # Body rect centred on the figure; recomputed if the figure resizes.
    body_bbox = lift(parent.viewport) do vp
        fw, fh = vp.widths
        bw, bh = Float32(size[1]), Float32(size[2])
        x = (fw - bw) / 2
        y = (fh - bh) / 2
        return Rect2f(x, y, bw, bh)
    end

    # Backdrop covering the whole figure — half-transparent, modal-ish.
    backdrop_rect = lift(vp -> Rect2f(0, 0, vp.widths...), parent.viewport)
    poly!(overlay, backdrop_rect; color=(:black, 0.35), inspectable=false)

    # Popup body
    poly!(overlay, body_bbox;
        color=:white, strokecolor=:black, strokewidth=2, inspectable=false)

    # The GridLayout — bbox follows the body minus padding for the header bar.
    HEADER_H = 36
    PAD      = 12
    layout_bbox = lift(body_bbox) do b
        x, y = b.origin
        w, h = b.widths
        Rect2f(x + PAD, y + PAD, w - 2PAD, h - HEADER_H - PAD)
    end
    layout = GridLayout(; bbox=layout_bbox)
    layout.parent = overlay

    # Header (title + close button) lives ABOVE the content layout, in its
    # own positioned blocks rather than the GridLayout so the user's content
    # always starts at the top of the grid.
    title_bbox = lift(body_bbox) do b
        x, y = b.origin
        w, h = b.widths
        Rect2f(x + PAD, y + h - HEADER_H + 4, w - HEADER_H - 2PAD, HEADER_H - 8)
    end
    title_label = Label(overlay; text=title, fontsize=14, font=:bold,
        halign=:left, tellwidth=false, tellheight=false)
    title_label.layoutobservables.suggestedbbox[] = title_bbox[]
    on(title_bbox) do r; title_label.layoutobservables.suggestedbbox[] = r; end

    close_bbox = lift(body_bbox) do b
        x, y = b.origin
        w, h = b.widths
        Rect2f(x + w - HEADER_H + 4, y + h - HEADER_H + 4, HEADER_H - 8, HEADER_H - 8)
    end
    close_btn = Button(overlay; label="×", fontsize=18,
        tellwidth=false, tellheight=false)
    close_btn.layoutobservables.suggestedbbox[] = close_bbox[]
    on(close_bbox) do r; close_btn.layoutobservables.suggestedbbox[] = r; end

    is_open = lift(identity, overlay.visible)

    # Blocks added via Block(gridposition; ...) get their blockscene parented
    # to the FIGURE's top scene, not to `overlay` — so hiding overlay only
    # hides the backdrop and body poly, while Labels/Checkboxes/Buttons keep
    # rendering at their popup positions (visible as floating text when
    # closed). `track!` lets the caller register every popup-owned Block so
    # we can drive their blockscene.visible from `overlay.visible`.
    tracked = Any[]
    function track!(block)
        push!(tracked, block)
        try; block.blockscene.visible[] = overlay.visible[]; catch; end
        return block
    end
    on(overlay.visible) do v
        for b in tracked
            try; b.blockscene.visible[] = v; catch; end
        end
    end
    # Auto-track the header widgets so callers only need to register their
    # own additions.
    track!(title_label)
    track!(close_btn)

    # MODAL EVENT INTERCEPTION
    #
    # Makie's Table installs a click+hover handler at priority=63 that
    # consumes clicks landing in its bbox AND updates the hover highlight
    # on every mouseposition change. Our popup Buttons/Checkboxes register
    # at the default priority=1, so they NEVER FIRE when the popup overlaps
    # the table area — Table grabs the click first. Hover state also leaks
    # through because mouseposition events fire continuously.
    #
    # Fix: install priority=100 handlers on both mousebutton AND mouseposition
    # that fire first when the popup is visible.
    #
    # - mouseposition: always Consume(true) when popup visible, so Table
    #   (priority=63) never sees a hover position update. (Minor cost: popup
    #   Menus lose their inside-dropdown hover-color tracking, but the
    #   selection-on-click still works because that fires on mousebutton.)
    # - mousebutton: hit-test against tracked widgets. Manually trigger
    #   Button/Checkbox clicks (their own priority=1 handlers won't get a
    #   chance), defer to Menu's priority=64 native handler on Menu hits
    #   or when any popup Menu has its dropdown open, and consume otherwise.
    on(parent.events.mouseposition; priority=100) do _
        return overlay.visible[] ? Consume(true) : Consume(false)
    end
    on(parent.events.mousebutton; priority=100) do butt
        overlay.visible[] || return Consume(false)
        butt.action == Mouse.press || return Consume(false)
        butt.button == Mouse.left || return Consume(false)

        mp = parent.events.mouseposition[]

        # If any popup Menu has its dropdown open, let Menu's own priority=64
        # handler process the click (option selection or click-elsewhere-
        # closes-dropdown logic).
        for block in tracked
            if block isa Makie.Menu && block.is_open[]
                return Consume(false)
            end
        end

        # Hit-test against tracked widgets.
        for block in tracked
            bbox = try
                block.layoutobservables.computedbbox[]
            catch
                continue
            end
            mp in bbox || continue
            if block isa Makie.Button
                block.clicks[] = block.clicks[] + 1
                return Consume(true)
            elseif block isa Makie.Checkbox
                block.checked[] = !block.checked[]
                return Consume(true)
            elseif block isa Makie.Menu
                # Let Menu's priority=64 handler fire and open dropdown.
                return Consume(false)
            else
                # Labels and other passive blocks — block the click from
                # falling through to anything behind.
                return Consume(true)
            end
        end

        # Click landed on empty popup body, backdrop, or fully outside —
        # consume to maintain modal behavior.
        return Consume(true)
    end

    open!  = () -> (overlay.visible[] = true;  nothing)
    close! = () -> (overlay.visible[] = false; nothing)
    on(_ -> close!(), close_btn.clicks)

    return (; scene=overlay, layout, title_label, close_btn,
              open! = open!, close! = close!, is_open,
              track! = track!)
end

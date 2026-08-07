"Maximum number of channels a `SamplePlot` will display."
const SAMPLE_MAX = 32

"Maximum number of numerator lines a `RatioPlot` will display."
const RATIO_MAX = 8

"""
    sampleplot(samp::KJ.Sample; channels=Makie.automatic, ...)
    sampleplot!(ax_or_fig, samp; kwargs...)

Plot one `KJ.Sample`: per-channel count rates as a `series`, with shaded
blank/signal windows and the t0 line. The `sample` input flows through
Makie's ComputeGraph, so swapping it (via `Observable` or `update!`)
re-renders without manual cleanup.

Each line carries its channel name as a `label`, so
`Legend(fig[i, j], sample_plot)` or `axislegend(ax)` picks them up
without any extra wiring.
"""
@recipe SamplePlot (sample,) begin
    "Channels to plot; `Makie.automatic` uses all channels from the sample"
    channels = Makie.automatic
    "Fill color for the blank window rectangles"
    blank_color = (:steelblue, 0.15)
    "Fill color for the signal window rectangles"
    signal_color = (:orange, 0.15)
    "Color of the t0 line"
    t0_color = :gray
    "Linestyle of the t0 line"
    t0_linestyle = :dash
    "Linewidth of the t0 line"
    t0_linewidth = 1.0
    "Linewidth of the channel lines"
    line_linewidth = 1.2
    "Colormap for the per-channel line colors"
    line_colormap = :tab20
    "Per-channel visibility; empty means all visible (driven by the Key)"
    channel_visible = Bool[]
    "Per-channel highlight = thicker line; empty means none (driven by the Key)"
    channel_highlight = Bool[]
    "Fit linewidth for the prediction overlay."
    fit_linewidth = 1.5
    "Post-process fit (`nothing` = no overlay). Set from the dashboard's fit_obs."
    fit = nothing
    "Method used to derive `fit` (needed for `KJ.predict` on the signal window)."
    method = nothing
    Makie.mixin_generic_plot_attributes()...
end

Makie.convert_arguments(::Type{<:SamplePlot}, s::KJ.Sample) = (s,)
Makie.convert_arguments(::Type{<:SamplePlot}, ::Nothing) = (nothing,)

function Makie.plot!(p::SamplePlot)
    Makie.map!(p.attributes,
               [:sample, :channels],
               [:times, :ymat, :channel_names]) do samp, chans
        isnothing(samp) && return (Float64[], Matrix{Float64}(undef, 0, 0), String[])
        chans_resolved = chans === Makie.automatic ? KJ.getChannels(samp) : chans
        t = Vector{Float64}(samp.dat[!, 1])
        ymat = Matrix{Float64}(undef, length(chans_resolved), length(t))
        for (i, c) in enumerate(chans_resolved)
            ymat[i, :] = samp.dat[!, c]
        end
        return (t, ymat, chans_resolved)
    end

    Makie.map!(p.attributes, [:sample], [:blank_xmins, :blank_xmaxs]) do samp
        isnothing(samp) && return (Float64[], Float64[])
        return window_edges(samp, samp.bwin)
    end

    Makie.map!(p.attributes, [:sample], [:signal_xmins, :signal_xmaxs]) do samp
        isnothing(samp) && return (Float64[], Float64[])
        return window_edges(samp, samp.swin)
    end

    Makie.map!(p.attributes, [:sample], :t0_value) do samp
        return isnothing(samp) ? 0.0 : Float64(samp.t0)
    end

    vspan!(p, p.blank_xmins,  p.blank_xmaxs;  color=p.blank_color)
    vspan!(p, p.signal_xmins, p.signal_xmaxs; color=p.signal_color)
    vlines!(p, p.t0_value;
            color=p.t0_color, linestyle=p.t0_linestyle, linewidth=p.t0_linewidth)

    # Red xcross on every flagged (channel, time) pair — matches the biplot
    # marker style and doesn't get confused with the fit-prediction line
    # (which crosses the same axis).
    outlier_pts = lift(p.sample, p.times, p.ymat, p.channel_visible) do samp, t, ymat, vis
        (isnothing(samp) || !hasproperty(samp.dat, :outlier)) && return Point2f[]
        outliers = samp.dat.outlier
        length(outliers) == length(t) || return Point2f[]
        pts = Point2f[]
        for ci in 1:size(ymat, 1)
            (isempty(vis) || ci > length(vis) || vis[ci]) || continue
            for i in eachindex(outliers)
                outliers[i] || continue
                y = ymat[ci, i]
                (isnan(y) || iszero(y)) && continue
                push!(pts, Point2f(t[i], y))
            end
        end
        return pts
    end
    scatter!(p, outlier_pts; color = :red, marker = :xcross, markersize = 10,
             strokewidth = 0, inspectable = false)

    # Fit-prediction overlay per channel (RMs only; `nothing` for `sample`
    # rows). One `Point2f[]` per pre-allocated line slot: blank + signal
    # windows concatenated with a NaN separator so a single line can span
    # both windows without connecting them.
    fit_lines = lift(p.sample, p.channel_names, p.fit, p.method) do samp, chans, fit, m
        empty = [Point2f[] for _ in 1:SAMPLE_MAX]
        (isnothing(samp) || isnothing(fit) || KJ.emptyFit(fit) ||
         isnothing(m) || samp.group == "sample") && return empty
        # Method-switch transient: `fit_obs` can briefly hold a fit whose
        # type doesn't match the newly-selected method (e.g. Gfit + Cmethod
        # after a Gmethod→Cmethod switch, until Process runs again). Skip
        # the overlay rather than blow up in `KJ.predict`.
        ((fit isa KJ.Gfit && m isa KJ.Gmethod) ||
         (fit isa KJ.Cfit && m isa KJ.Cmethod)) || return empty
        # `KJ.predict(samp, m, fit)` returns nothing for the "sample" group;
        # its columns are exactly the P/D/d channels the fit uses.
        pred_sig = KJ.predict(samp, m, fit; generic_names=false)
        isnothing(pred_sig) && return empty
        fit_chans = names(pred_sig)
        pred_blank = KJ.predict(samp, fit.blank)
        blk = KJ.bwinData(samp); sig = KJ.swinData(samp)
        # Row alignment assumption for pred_blank/pred_sig ↔ blk/sig.
        (isnothing(pred_blank) || size(pred_blank, 1) == size(blk, 1)) || return empty
        size(pred_sig, 1) == size(sig, 1) || return empty
        good_b = .!Vector{Bool}(blk.outlier)
        good_s = .!Vector{Bool}(sig.outlier)
        xb = Vector{Float64}(blk[good_b, 1])
        xs = Vector{Float64}(sig[good_s, 1])
        segments = copy(empty)
        for (i, ch) in enumerate(chans)
            i <= SAMPLE_MAX || break
            ch in fit_chans || continue
            pts = Point2f[]
            if !isnothing(pred_blank) && ch in names(pred_blank)
                append!(pts, Point2f.(xb, Vector{Float64}(pred_blank[good_b, ch])))
                push!(pts, Point2f(NaN, NaN))
            end
            append!(pts, Point2f.(xs, Vector{Float64}(pred_sig[good_s, ch])))
            segments[i] = pts
        end
        return segments
    end
    cols = line_colors(p.line_colormap[], SAMPLE_MAX)
    # Colour by rank among visible channels, not by absolute slot: keeps
    # visible traces on the vivid front of :tab20 even when their slot
    # indices are high (e.g. Lu-Hf's P/D/d land at 15/17/18).
    visible_rank = lift(p.channel_visible) do vis
        rank = zeros(Int, max(length(vis), SAMPLE_MAX))
        r = 0
        for i in eachindex(vis)
            vis[i] || continue
            r += 1
            rank[i] = r
        end
        return rank
    end
    color_for(i) = lift(rk -> cols[mod1(iszero(rk[i]) ? i : rk[i], length(cols))],
                        visible_rank)

    # Fit lines are drawn before raw so the coloured signal sits on top;
    # dashed to distinguish from raw while sharing the channel colour.
    for i in 1:SAMPLE_MAX
        pts = lift(v -> v[i], fit_lines)
        lines!(p, pts; color = color_for(i), linewidth = p.fit_linewidth,
               linestyle = :dash, label = "", inspectable = false)
    end

    # Pre-allocate `SAMPLE_MAX` raw-signal line children — updated
    # reactively when the sample / channel set changes. Hidden channels
    # collapse to empty data so they don't inflate autolimits.
    for i in 1:SAMPLE_MAX
        ydata = lift(p.times, p.ymat, p.channel_visible) do t, m, vis
            shown = isempty(vis) || i > length(vis) || vis[i]
            (shown && i <= size(m, 1) && length(t) == size(m, 2)) ?
                Point2f.(t, view(m, i, :)) : Point2f[]
        end
        lines!(p, ydata;
               color     = color_for(i),
               label     = lift(cn -> i <= length(cn) ? cn[i] : "", p.channel_names),
               linewidth = lift(p.channel_highlight, p.line_linewidth) do h, lw
                   (i <= length(h) && h[i]) ? 2.5lw : lw
               end)
    end
    return p
end

# Distinct per-channel colors from a categorical colormap (cycles past 20).
function line_colors(colormap, n)
    n < 1 && return Makie.RGBAf[]
    k = clamp(n, 2, 20)
    palette = Makie.categorical_colors(colormap, k)
    return [palette[mod1(i, k)] for i in 1:n]
end

# Surface only the labeled line children so `Legend` doesn't include the
# pre-allocated empty slots (channels not in the current sample).
function Makie.get_plots(p::SamplePlot)
    children = reduce(vcat, Makie.get_plots.(p.plots); init=Makie.AbstractPlot[])
    return filter(children) do c
        c isa Lines || return true
        hasproperty(c, :label) || return false
        l = c.label[]
        l isa AbstractString && !isempty(l)
    end
end

"""
    ratioplot(samp::KJ.Sample; numerators=[…], denominator="…", …)
    ratioplot!(ax_or_fig, samp; kwargs...)

Plot one or more isotope ratios (numerator / denominator) for a single
sample as continuous lines:

* Data is `(channel + offset) / (den + offset)` via `KJ.transformeer`,
  with `offset = KJ.get_offset(samp; transformation="log", …)` so the
  axis can be set to `ax.yscale = log10` / `sqrt` without `log(0)`.
* Outlier rows produce `NaN` — each line breaks at flagged outliers.
* Blank/signal windows render as `vspan!`s, `t0` as a `vlines!`.
* If `fit` (and `method`) are passed, fitted predictions are overlaid as
  `fit_color` lines (blank window for every sample, signal window for
  standards/RMs only).

`numerators` selects which non-denominator channels appear; an empty
vector or empty `denominator` draws nothing.
"""
@recipe RatioPlot (sample,) begin
    "Channel names used as numerators"
    numerators = String[]
    "Channel name used as the common denominator"
    denominator = ""
    """
    Optional fit (`KJ.Gfit` / `KJ.Cfit`). When non-`nothing`, fitted
    predictions are overlaid in `fit_color`.
    """
    fit = nothing
    """
    Optional `KJ.KJmethod`. Required for the signal-window prediction;
    the blank-window overlay only needs `fit`.
    """
    method = nothing
    "Colour of the fitted-prediction overlay lines."
    fit_color = :black
    "Linewidth of the fitted-prediction overlay lines."
    fit_linewidth = 1.25
    "Fill color for the blank window rectangles"
    blank_color = (:steelblue, 0.15)
    "Fill color for the signal window rectangles"
    signal_color = (:orange, 0.15)
    "Color of the t0 line"
    t0_color = :gray
    "Linestyle of the t0 line"
    t0_linestyle = :dash
    "Linewidth of the t0 line"
    t0_linewidth = 1.0
    "Width of the ratio lines"
    line_linewidth = 1.5
    "Colormap used to colour the ratio series — one slot per numerator."
    line_colormap = :tab10
    """
    Single-colour override for every ratio line. When `nothing`, each
    numerator takes its colour from `line_colormap`. Set this when
    overlaying several one-numerator ratioplots on a shared Axis, since
    each one's `line_colormap` index starts at 1 and would otherwise
    collide.
    """
    line_color = nothing
    Makie.mixin_generic_plot_attributes()...
end

Makie.convert_arguments(::Type{<:RatioPlot}, s::KJ.Sample) = (s,)
Makie.convert_arguments(::Type{<:RatioPlot}, ::Nothing) = (nothing,)

# `(channel + offset) / (den + offset)` matrix via `KJ.transformeer` with
# `transformation=""`. The offset (from `KJ.get_offset(...; "log")`) keeps
# the data positive so the host Axis can use `yscale = log10`.
function compute_ratios(samp::KJ.Sample, nums::AbstractVector, den::AbstractString)
    t = Vector{Float64}(samp.dat[!, 1])
    valid_den  = den in names(samp.dat) ? den : ""
    # Drop channels not in this sample, and the degenerate `c == den` case
    # (`formRatios` would double-count it and `D/D == 1` carries no info).
    nums_valid = filter(c -> c in names(samp.dat) && c != valid_den, nums)
    if isempty(nums_valid) || isempty(valid_den)
        return (t, Matrix{Float64}(undef, 0, length(t)), String[], 0.0)
    end
    channels = String[nums_valid; valid_den]
    offset = KJ.get_offset(samp; transformation="log",
                           channels=channels, num="", den=valid_den)
    y_df = KJ.transformeer(samp.dat[:, channels], "";
                           num="", den=valid_den, offset=offset)
    # `formRatios` labels each output column `"<num>/<den>"`.
    labels = names(y_df)
    ymat = Matrix{Float64}(undef, length(labels), length(t))
    for (i, lbl) in enumerate(labels)
        col = Vector{Float64}(y_df[!, lbl])
        # NaN out non-finite entries so they don't poison `data_limits`.
        @. col = ifelse(isfinite(col), col, NaN)
        ymat[i, :] = col
    end
    return (t, ymat, labels, offset)
end

# Fit-overlay data per numerator slot: `(blank_pts, signal_pts)`. Signal
# predictions exist for standards/RMs only; blank predictions for all.
function compute_fit_overlay(samp, nums::AbstractVector, den::AbstractString,
                              offset::Real, fit, method,
                              ratio_labels::AbstractVector)
    empty_lines = [Point2f[] for _ in 1:RATIO_MAX]
    (isnothing(samp) || isnothing(fit) || KJ.emptyFit(fit)) &&
        return (empty_lines, empty_lines)
    valid_den = den in names(samp.dat) ? den : ""
    nums_valid = filter(c -> c in names(samp.dat) && c != valid_den, nums)
    (isempty(nums_valid) || isempty(valid_den)) &&
        return (empty_lines, empty_lines)

    blank_lines  = copy(empty_lines)
    signal_lines = copy(empty_lines)

    # Blank window prediction — available for every sample.
    pred_blank = KJ.predict(samp, fit.blank)
    if !isnothing(pred_blank)
        chans_blank = intersect(String[nums_valid; valid_den], names(pred_blank))
        if valid_den in chans_blank && length(chans_blank) > 1
            blk_dat = KJ.bwinData(samp)
            good = .!Vector{Bool}(blk_dat.outlier)
            xb = Vector{Float64}(blk_dat[good, 1])
            y_df = KJ.transformeer(pred_blank[good, chans_blank], "";
                                   num="", den=valid_den, offset=offset)
            for lbl in names(y_df)
                slot = findfirst(==(lbl), ratio_labels)
                isnothing(slot) && continue
                slot <= RATIO_MAX || continue
                y = Vector{Float64}(y_df[!, lbl])
                @. y = ifelse(isfinite(y), y, NaN)
                blank_lines[slot] = Point2f.(xb, y)
            end
        end
    end

    # Signal window prediction — only standards / RMs have it (the rest
    # are "sample" group and `predict` returns nothing for them). Also
    # skip when `fit` and `method` are of incompatible types (method-
    # switch transient before Process re-runs).
    compat = (fit isa KJ.Gfit && method isa KJ.Gmethod) ||
             (fit isa KJ.Cfit && method isa KJ.Cmethod)
    if compat && samp.group != "sample"
        pred_sig = KJ.predict(samp, method, fit; generic_names=false)
        if !isnothing(pred_sig)
            chans_sig = intersect(String[nums_valid; valid_den], names(pred_sig))
            if valid_den in chans_sig && length(chans_sig) > 1
                sig_dat = KJ.swinData(samp)
                good = .!Vector{Bool}(sig_dat.outlier)
                xs = Vector{Float64}(sig_dat[good, 1])
                y_df = KJ.transformeer(pred_sig[good, chans_sig], "";
                                       num="", den=valid_den, offset=offset)
                for lbl in names(y_df)
                    slot = findfirst(==(lbl), ratio_labels)
                    isnothing(slot) && continue
                    slot <= RATIO_MAX || continue
                    y = Vector{Float64}(y_df[!, lbl])
                    @. y = ifelse(isfinite(y), y, NaN)
                    signal_lines[slot] = Point2f.(xs, y)
                end
            end
        end
    end

    return (blank_lines, signal_lines)
end

function Makie.plot!(p::RatioPlot)
    Makie.map!(p.attributes,
               [:sample, :numerators, :denominator],
               [:times, :ymat, :ratio_labels, :offset]) do samp, nums, den
        isnothing(samp) && return (Float64[], Matrix{Float64}(undef, 0, 0),
                                   String[], 0.0)
        return compute_ratios(samp, nums, den)
    end

    Makie.map!(p.attributes, [:sample], [:blank_xmins, :blank_xmaxs]) do samp
        isnothing(samp) && return (Float64[], Float64[])
        return window_edges(samp, samp.bwin)
    end

    Makie.map!(p.attributes, [:sample], [:signal_xmins, :signal_xmaxs]) do samp
        isnothing(samp) && return (Float64[], Float64[])
        return window_edges(samp, samp.swin)
    end

    Makie.map!(p.attributes, [:sample], :t0_value) do samp
        return isnothing(samp) ? 0.0 : Float64(samp.t0)
    end

    vspan!(p, p.blank_xmins,  p.blank_xmaxs;  color=p.blank_color)
    vspan!(p, p.signal_xmins, p.signal_xmaxs; color=p.signal_color)
    vlines!(p, p.t0_value;
            color=p.t0_color, linestyle=p.t0_linestyle, linewidth=p.t0_linewidth)

    # Red xcross on every flagged (numerator, time) pair — mirrors the
    # SamplePlot/biplot outlier marker style.
    outlier_pts = lift(p.sample, p.times, p.ymat) do samp, t, ymat
        (isnothing(samp) || !hasproperty(samp.dat, :outlier)) && return Point2f[]
        outliers = samp.dat.outlier
        length(outliers) == length(t) || return Point2f[]
        pts = Point2f[]
        for ri in 1:size(ymat, 1), i in eachindex(outliers)
            outliers[i] || continue
            y = ymat[ri, i]
            isnan(y) && continue
            push!(pts, Point2f(t[i], y))
        end
        return pts
    end
    scatter!(p, outlier_pts; color = :red, marker = :xcross, markersize = 10,
             strokewidth = 0, inspectable = false)

    # Pre-allocate `RATIO_MAX` line children so `numerators` can grow at
    # runtime without rebuilding. Unused slots get empty data + empty
    # label, so they don't render and don't pollute the Legend.
    cols = line_colors(p.line_colormap[], RATIO_MAX)
    for i in 1:RATIO_MAX
        pts = lift(p.times, p.ymat) do t, m
            (i <= size(m, 1) && length(t) == size(m, 2)) ?
                Point2f.(t, view(m, i, :)) : Point2f[]
        end
        color = lift(p.line_color) do c
            isnothing(c) ? cols[i] : c
        end
        lines!(p, pts;
               color     = color,
               linewidth = p.line_linewidth,
               label     = lift(lbl -> i <= length(lbl) ? lbl[i] : "",
                                p.ratio_labels))
    end

    # Two overlay line slots per numerator (blank-window + signal-window).
    # Empty data unless `fit` is set; signal-window prediction is empty for
    # samples in the "sample" group.
    overlay = lift(p.sample, p.numerators, p.denominator,
                   p.offset, p.fit, p.method, p.ratio_labels
                   ) do samp, nums, den, offset, fit, method, labels
        compute_fit_overlay(samp, nums, den, offset, fit, method, labels)
    end
    # Fit line: per-ratio colour (honouring `line_color` when Combined
    # mode sets it) + dash so raw and fit stay visually paired.
    for i in 1:RATIO_MAX
        blank_pts  = lift(o -> o[1][i], overlay)
        signal_pts = lift(o -> o[2][i], overlay)
        color_i = lift(c -> isnothing(c) ? cols[i] : c, p.line_color)
        lines!(p, blank_pts;
               color     = color_i,
               linewidth = p.fit_linewidth,
               linestyle = :dash,
               label     = "")
        lines!(p, signal_pts;
               color     = color_i,
               linewidth = p.fit_linewidth,
               linestyle = :dash,
               label     = "")
    end
    return p
end

"""
Surface only labeled line children to `Legend` — pre-allocated empty
slots and the fitted-prediction overlay carry empty labels.
"""
function Makie.get_plots(p::RatioPlot)
    children = reduce(vcat, Makie.get_plots.(p.plots); init=Makie.AbstractPlot[])
    return filter(children) do c
        c isa Lines || return true   # vspan/vlines etc. pass through
        l = c.label[]
        l isa AbstractString && !isempty(l)
    end
end

function window_edges(samp, win)
    t = samp.dat[!, 1]
    n = length(t)
    xmins = Float64[t[clamp(a, 1, n)] for (a, _) in win]
    xmaxs = Float64[t[clamp(b, 1, n)] for (_, b) in win]
    return (xmins, xmaxs)
end

"""
    biplot(samp::KJ.Sample; x_numerator, y_numerator, denominator, method=nothing, fit=nothing, …)
    biplot!(ax_or_fig, samp; kwargs...)

Isochron-style scatter: x = `x_numerator / denominator`, y = `y_numerator /
denominator`, one point per signal-window step in the sample. Points are
colour-coded by their order (time gradient).

Two modes, depending on whether a fit is available:

* **Raw** (`fit === nothing`): scatter uses the raw channel columns from
  `samp.dat`, one point per time step. Useful for visual selection before
  processing.
* **Processed** (`fit::KJ.Gfit` + `method::KJ.Gmethod` supplied): scatter
  uses corrected `Phat ./ Dhat` vs `dhat ./ Dhat` from `KJ.atomic`, and the
  fitted internal isochron line + age annotation are drawn on top.
"""
@recipe BiPlot (sample,) begin
    "Channel name for the x-axis numerator (e.g. parent P)"
    x_numerator = ""
    "Channel name for the y-axis numerator (e.g. sister S/d)"
    y_numerator = ""
    "Channel name for the shared denominator (e.g. daughter D)"
    denominator = ""
    "Marker size"
    markersize = 10
    "Colormap used for the time gradient"
    point_colormap = :viridis
    "Geochronology method; when set together with `fit`, switches to processed mode"
    method = nothing
    "Fit returned by `KJ.process!`; when set together with `method`, switches to processed mode"
    fit = nothing
    "Colour of the fitted isochron line"
    isochron_color = :black
    "Linewidth of the fitted isochron line"
    isochron_linewidth = 2.0
    Makie.mixin_generic_plot_attributes()...
end

Makie.convert_arguments(::Type{<:BiPlot}, s::KJ.Sample) = (s,)
Makie.convert_arguments(::Type{<:BiPlot}, ::Nothing) = (nothing,)

function Makie.plot!(p::BiPlot)
    # `outlier_mask` aligns with the scatter rows (signal-window slice in
    # processed mode, full `samp.dat` in raw mode). The plot below splits
    # it into two scatter layers so outliers stay visible-but-marked.
    Makie.map!(p.attributes,
               [:sample, :x_numerator, :y_numerator, :denominator, :method, :fit],
               [:xs, :ys, :ts, :outlier_mask]) do samp, xnum, ynum, den, m, fit
        empty_out = (Float64[], Float64[], Float64[], Bool[])
        # Processed mode — only when both method and fit are real Gmethod/Gfit.
        if !isnothing(samp) && !isnothing(fit) && m isa KJ.Gmethod
            try
                res = KJ.atomic(samp, m, fit)
                x = res.P ./ res.D
                y = res.d ./ res.D
                @. x = ifelse(isfinite(x), x, NaN)
                @. y = ifelse(isfinite(y), y, NaN)
                # `KJ.atomic` iterates `swinData(samp)` — outlier mask
                # follows the same row slice.
                sel, _, _ = KJ.windows2selection(samp.swin)
                mask = hasproperty(samp.dat, :outlier) ?
                    Vector{Bool}(samp.dat.outlier[sel]) :
                    falses(length(x))
                return (collect(x), collect(y),
                        Float64.(1:length(x)), mask)
            catch err
                @debug "KJ.atomic threw; biplot falls back to raw mode" exception=err
            end
        end
        # Raw mode
        if isnothing(samp) || isempty(xnum) || isempty(ynum) || isempty(den)
            return empty_out
        end
        cols = names(samp.dat)
        (xnum in cols && ynum in cols && den in cols) || return empty_out
        d = Vector{Float64}(samp.dat[!, den])
        x = Vector{Float64}(samp.dat[!, xnum]) ./ d
        y = Vector{Float64}(samp.dat[!, ynum]) ./ d
        @. x = ifelse(isfinite(x), x, NaN)
        @. y = ifelse(isfinite(y), y, NaN)
        t = Vector{Float64}(samp.dat[!, 1])
        mask = hasproperty(samp.dat, :outlier) ?
            Vector{Bool}(samp.dat.outlier) : falses(length(x))
        return (x, y, t, mask)
    end

    # Split scatter into in-fit and outlier layers. Good rows keep the
    # time-gradient colour; outliers render as red ✗ markers on top.
    Makie.map!(p.attributes, [:xs, :ys, :ts, :outlier_mask],
               [:xs_good, :ys_good, :ts_good,
                :xs_outlier, :ys_outlier]) do x, y, t, mask
        if isempty(mask) || length(mask) != length(x)
            return (x, y, t, Float64[], Float64[])
        end
        good = .!mask
        return (x[good], y[good], t[good], x[mask], y[mask])
    end

    # Isochron line + 2σ ribbon + age annotation. Empty observables when
    # no fit. Ribbon follows `KJ.internoplot`: covariance from the
    # `internochron` (x0, y0) propagated through `y = y0 - x*y0/x0`.
    Makie.map!(p.attributes, [:sample, :method, :fit],
               [:line_xs, :line_ys, :age_pos, :age_text,
                :ribbon_xs, :ribbon_lo, :ribbon_hi]) do samp, m, fit
        empty_ribbon = (Float64[], Float64[], Point2f(NaN, NaN), "",
                        Float64[], Float64[], Float64[])
        if isnothing(samp) || isnothing(fit) || !(m isa KJ.Gmethod)
            return empty_ribbon
        end
        try
            x0, sx0, y0, sy0, rx0y0 = KJ.internochron(samp, m, fit)
            E = [sx0^2          rx0y0*sx0*sy0;
                 rx0y0*sx0*sy0  sy0^2]
            ty0 = KJ.x0y02t(x0, y0, E, m.name)
            sdig = 2
            tdig = max(sdig, ceil(Int, log10(abs(ty0.t/ty0.st))) + sdig)
            txt = "t = " * string(round(ty0.t; sigdigits=tdig)) *
                  " ± " * string(round(ty0.st; sigdigits=sdig)) * " Ma"
            # 2σ band: propagate (x0, y0) covariance through y(x) = y0 - x*y0/x0.
            # Partial derivatives: ∂y/∂x0 = x*y0/x0², ∂y/∂y0 = 1 - x/x0.
            nstep = 50
            xband = collect(range(0.0, float(x0); length=nstep))
            yband = @. y0 - xband*y0/x0
            J1 = @. xband*y0/x0^2
            J2 = @. 1.0 - xband/x0
            sy2 = @. J1^2*E[1,1] + 2*J1*J2*E[1,2] + J2^2*E[2,2]
            sy = sqrt.(max.(sy2, 0.0))
            nsigma = 2.0
            return ([0.0, x0], [y0, 0.0], Point2f(x0/2, y0/2), txt,
                    xband, yband .- nsigma .* sy, yband .+ nsigma .* sy)
        catch err
            @debug "KJ.internochron threw; biplot drops the isochron overlay" exception=err
            return empty_ribbon
        end
    end

    scatter!(p, p.xs_good, p.ys_good;
             color = p.ts_good,
             colormap = p.point_colormap,
             markersize = p.markersize)
    scatter!(p, p.xs_outlier, p.ys_outlier;
             color = :red, marker = :xcross,
             markersize = p.markersize[] * 1.8)
    band!(p, p.ribbon_xs, p.ribbon_lo, p.ribbon_hi;
          color = (p.isochron_color[], 0.15))
    lines!(p, p.line_xs, p.line_ys;
           color = p.isochron_color, linewidth = p.isochron_linewidth)
    text!(p, p.age_pos; text = p.age_text,
          fontsize = 12, align = (:left, :bottom), offset = (8, 8))
    return p
end

"""
Restrict autolimits to the scatter children. The isochron `band!` + `lines!`
extend to `(0, 0)` and would otherwise yank the axis range out to include
the origin, leaving the actual data points clustered in a tiny corner.
"""
function Makie.data_limits(p::BiPlot)
    bb = nothing
    for child in p.plots
        child isa Makie.Scatter || continue
        cbb = Makie.data_limits(child)
        bb = isnothing(bb) ? cbb : union(bb, cbb)
    end
    return something(bb, Makie.Rect3d(Point3d(NaN, NaN, 0), Vec3d(0, 0, 0)))
end
Makie.boundingbox(p::BiPlot, space::Symbol = :data) =
    Makie.apply_transform_and_model(p, Makie.data_limits(p))

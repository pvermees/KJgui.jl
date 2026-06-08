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

    # One `lines!` per channel (instead of a `series`) so the Key can toggle
    # each channel's visibility and highlight (thicker line) independently —
    # series derives its children's linewidth and won't allow per-line edits.
    # The channel count is fixed for a loaded run, so the loop runs once.
    n = length(p.channel_names[])
    cols = line_colors(p.line_colormap[], n)
    for i in 1:n
        ydata = lift(p.times, p.ymat) do t, m
            (i <= size(m, 1) && length(t) == size(m, 2)) ?
                Point2f.(t, view(m, i, :)) : Point2f[]
        end
        lines!(p, ydata;
               color     = cols[i],
               label     = lift(cn -> i <= length(cn) ? cn[i] : "", p.channel_names),
               visible   = lift(v -> isempty(v) || i > length(v) ? true : v[i],
                                p.channel_visible),
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

# Recurse into the recipe's children so Legend can see their labels.
# Makie's default `get_plots(::AbstractPlot) = [p]` stops at the recipe.
Makie.get_plots(p::SamplePlot) =
    reduce(vcat, Makie.get_plots.(p.plots); init=Makie.AbstractPlot[])

"""
    ratioplot(samp::KJ.Sample; numerators=[…], denominator="…", …)
    ratioplot!(ax_or_fig, samp; kwargs...)

Plot one or more isotope ratios (numerator / denominator) for a single
sample. `numerators` is a vector of channel names; `denominator` is one.
Each ratio gets its own labeled `lines`, so
`Legend(fig[i, j], ratio_plot)` works the same way as for `sampleplot`.
"""
@recipe RatioPlot (sample,) begin
    "Channel names used as numerators"
    numerators = String[]
    "Channel name used as the common denominator"
    denominator = ""
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
    "Linewidth of the ratio lines"
    line_linewidth = 1.5
    "Colormap used to colour the ratio lines"
    line_colormap = :tab10
    Makie.mixin_generic_plot_attributes()...
end

Makie.convert_arguments(::Type{<:RatioPlot}, s::KJ.Sample) = (s,)
Makie.convert_arguments(::Type{<:RatioPlot}, ::Nothing) = (nothing,)

function Makie.plot!(p::RatioPlot)
    Makie.map!(p.attributes,
               [:sample, :numerators, :denominator],
               [:times, :ymat, :ratio_labels]) do samp, nums, den
        isnothing(samp) && return (Float64[], Matrix{Float64}(undef, 0, 0), String[])
        t = Vector{Float64}(samp.dat[!, 1])
        nums_valid = filter(c -> c in names(samp.dat), nums)
        valid_den  = den in names(samp.dat) ? den : ""
        if isempty(nums_valid) || isempty(valid_den)
            return (t, Matrix{Float64}(undef, 0, length(t)), String[])
        end
        d = Vector{Float64}(samp.dat[!, valid_den])
        ymat = Matrix{Float64}(undef, length(nums_valid), length(t))
        for (i, num) in enumerate(nums_valid)
            ratio = Vector{Float64}(samp.dat[!, num]) ./ d
            # Zero-denominator samples (blank window) produce Inf, which
            # poisons `data_limits` and breaks `autolimits!`. NaN renders
            # as a gap and is ignored by the limit computation.
            @. ratio = ifelse(isfinite(ratio), ratio, NaN)
            ymat[i, :] = ratio
        end
        labels = [string(num, " / ", valid_den) for num in nums_valid]
        return (t, ymat, labels)
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

    # Pre-allocate up to RATIO_MAX `lines!` children so the user can grow
    # `numerators` at runtime without rebuilding the plot. `series!` would
    # be conceptually nicer but does not adapt its child count when the
    # matrix grows rows. Unused slots get empty data + empty label, so the
    # legend skips them.
    cols = line_colors(p.line_colormap[], RATIO_MAX)
    for i in 1:RATIO_MAX
        ydata = lift(p.times, p.ymat) do t, m
            (i <= size(m, 1) && length(t) == size(m, 2)) ?
                Point2f.(t, view(m, i, :)) : Point2f[]
        end
        lines!(p, ydata;
               color     = cols[i],
               label     = lift(lbl -> i <= length(lbl) ? lbl[i] : "",
                                p.ratio_labels),
               linewidth = p.line_linewidth)
    end
    return p
end

# Cap on simultaneous ratios per panel. Beyond this the user should split
# into another panel.
const RATIO_MAX = 8

# Surface only the actively-labeled line children to Legend — unused
# pre-allocated slots have a nothing/empty label and should not appear.
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
    markersize = 6
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
    Makie.map!(p.attributes,
               [:sample, :x_numerator, :y_numerator, :denominator, :method, :fit],
               [:xs, :ys, :ts]) do samp, xnum, ynum, den, m, fit
        # Processed mode — only when both method and fit are real Gmethod/Gfit.
        if !isnothing(samp) && !isnothing(fit) && m isa KJ.Gmethod
            try
                res = KJ.atomic(samp, m, fit)
                x = res.P ./ res.D
                y = res.d ./ res.D
                @. x = ifelse(isfinite(x), x, NaN)
                @. y = ifelse(isfinite(y), y, NaN)
                return (collect(x), collect(y), Float64.(1:length(x)))
            catch
                # fall through to raw mode if KJ rejects the inputs
            end
        end
        # Raw mode
        if isnothing(samp) || isempty(xnum) || isempty(ynum) || isempty(den)
            return (Float64[], Float64[], Float64[])
        end
        cols = names(samp.dat)
        (xnum in cols && ynum in cols && den in cols) ||
            return (Float64[], Float64[], Float64[])
        d = Vector{Float64}(samp.dat[!, den])
        x = Vector{Float64}(samp.dat[!, xnum]) ./ d
        y = Vector{Float64}(samp.dat[!, ynum]) ./ d
        @. x = ifelse(isfinite(x), x, NaN)
        @. y = ifelse(isfinite(y), y, NaN)
        t = Vector{Float64}(samp.dat[!, 1])
        return (x, y, t)
    end

    # Isochron line + 2σ uncertainty ribbon + age annotation. Empty data when
    # no fit, so the band!/lines!/text! children render nothing but stay in
    # the plot tree. The ribbon follows KJ.internoplot — covariance from the
    # `internochron` x0/y0 estimate propagates through `y = y0 - x*y0/x0`.
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
        catch
            return empty_ribbon
        end
    end

    scatter!(p, p.xs, p.ys;
             color = p.ts,
             colormap = p.point_colormap,
             markersize = p.markersize)
    band!(p, p.ribbon_xs, p.ribbon_lo, p.ribbon_hi;
          color = (p.isochron_color[], 0.15))
    lines!(p, p.line_xs, p.line_ys;
           color = p.isochron_color, linewidth = p.isochron_linewidth)
    text!(p, p.age_pos; text = p.age_text,
          fontsize = 12, align = (:left, :bottom), offset = (8, 8))
    return p
end

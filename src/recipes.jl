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
    series!(p, p.times, p.ymat;
            labels=p.channel_names, color=p.line_colormap, linewidth=p.line_linewidth)
    return p
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
    series!(p, p.times, p.ymat;
            labels=p.ratio_labels, color=p.line_colormap, linewidth=p.line_linewidth)
    return p
end

Makie.get_plots(p::RatioPlot) =
    reduce(vcat, Makie.get_plots.(p.plots); init=Makie.AbstractPlot[])

function window_edges(samp, win)
    t = samp.dat[!, 1]
    n = length(t)
    xmins = Float64[t[clamp(a, 1, n)] for (a, _) in win]
    xmaxs = Float64[t[clamp(b, 1, n)] for (_, b) in win]
    return (xmins, xmaxs)
end

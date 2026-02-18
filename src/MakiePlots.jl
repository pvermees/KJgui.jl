function MakiePlot!(ctrl::AbstractDict;
                    seriestype=:scatter,
                    ms=5,
                    ma=1,
                    xlim=:auto,
                    ylim=:auto,
                    show_title=true,
                    titlefontsize=14)
    samp = ctrl["run"][ctrl["i"]]
    ax = ctrl["ax"]
    if isnothing(ctrl["method"])
        channels = KJ.getChannels(samp)
    else
        channels = KJ.getChannels(ctrl["method"])
    end
    offset = KJ.get_offset(samp;
                           method=ctrl["method"],
                           fit=ctrl["fit"],
                           channels=channels,
                           transformation=ctrl["transformation"],
                           den=ctrl["den"])
    x, y, xlab, ylab = KJ.prep_plot(samp,channels;
                                    den=ctrl["den"],
                                    transformation=ctrl["transformation"],
                                    offset=offset)
    ax.xlabel = xlab
    ax.ylabel = ylab
    ax.tellheight = false
    n_cols = size(y,2)
    Random.seed!(4)
    for i in 1:n_cols
        good = isfinite.(y[:,i])
        if seriestype == :scatter
            scatter!(ax, x[good], y[good,i];
                     color = RGBf(rand(3)...),
                     markersize=ms, 
                     strokewidth=ma, 
                     label=names(y)[i])
        else
            lines!(ax, x[good], y[good,i]; linewidth=ms)
        end
    end
    if xlim != :auto
        xlims!(ax, xlim)
    end
    if ylim != :auto
        ylims!(ax, ylim)
    end
    if show_title
        ax.title = string(ctrl["i"]) * ". " * samp.sname * " [" * samp.group * "]"
        ax.titlesize = titlefontsize
    end
    ylim_dat = [minimum(Matrix(y)),maximum(Matrix(y))]
    interactive_windows(ctrl,x,ylim_dat)
end
export MakiePlot!

function interactive_windows(ctrl::AbstractDict,
                             x::AbstractVector,
                             ylim_dat::AbstractVector)
    samp = ctrl["run"][ctrl["i"]]
    ax = ctrl["ax"]
    reset_limits!(ax)
    ylim_ax = collect(ax.yaxis.attributes.limits.val)
    ylims = @. (ylim_dat + ylim_ax)/2
    if :select_window in keys(interactions(ax))
        Makie.deregister_interaction!(ax, :select_window)
    end
    add_listener!(ctrl,x,ylims[1],ylims[2])
end

function add_listener!(ctrl::AbstractDict,
                       x::AbstractVector,
                       ym::AbstractFloat,
                       yM::AbstractFloat)
    ax = ctrl["ax"]
    samp = ctrl["run"][ctrl["i"]]
    obs_t0 = Observable(Point2f[(samp.t0,ym),(samp.t0,yM)])
    lines!(ax,obs_t0; color=:gray, linestyle=:dash)
    bwin = draw_windows(ax,samp.bwin,x,ym,yM)
    swin = draw_windows(ax,samp.swin,x,ym,yM)
    obs_win = nothing
    selected = nothing
    fresh = true
    windows = []
    boxes = []
    x1,x2,xm,xM = 0.0,0.0,0.0,0.0
    register_interaction!(ax,:select_window) do event::MouseEvent, axis
        if event.type === MouseEventTypes.leftdragstart
            x1 = event.data[1]
            t0 = obs_t0.val[1][1]
            max_blk = i2t(samp,samp.bwin[end][2])
            min_sig = i2t(samp,samp.swin[1][1])
            min_buf = i2t(samp,1)
            if x1 < t0 - max(min_buf,(t0-max_blk)/3)
                selected = "blank"
                boxes = bwin
            elseif x1 > t0 + max(min_buf,(min_sig-t0)/3)
                selected = "signal"
                boxes = swin
            else
                selected = "t0"
                boxes = nothing
            end
            if selected in ("blank","signal")
                if !ispressed(ax,Keyboard.m)
                    fresh = true
                end
                if fresh
                    for box in boxes
                        delete!(ax.scene,box)
                    end
                    windows = []
                    fresh = !ispressed(ax,Keyboard.m)
                end
                obs_win = Observable(Point2f[(xm,ym),(xm,yM),(xM,yM),(xM,ym)])
                box = poly!(ax,obs_win;color=:transparent, strokewidth=1.0, linestyle=:dot)
                push!(boxes,box)
            end
        end
        if event.type === MouseEventTypes.leftdrag
            x2 = event.data[1]
            if selected == "t0"
                obs_t0.val = [(x2,ym),(x2,yM)]
                notify(obs_t0)
            else
                xm = minimum([x1,x2])
                xM = maximum([x1,x2])
                obs_win.val = [(xm,ym),(xm,yM),(xM,yM),(xM,ym)]
                notify(obs_win)
            end
        end
        if event.type === MouseEventTypes.leftdragstop
            push!(windows,(xm,xM))
            obj = ispressed(ax,Keyboard.a) ? ctrl["run"] : samp
            if selected == "blank"
                setBwin!(obj,windows;seconds=true)
            elseif selected == "t0"
                sett0!(obj,obs_t0.val[1][1])
                for win in bwin
                    delete!(ax.scene,win)
                end
                for win in swin
                    delete!(ax.scene,win)
                end
                setBwin!(obj)
                setSwin!(obj)
                draw_windows(ax,samp.bwin,x,ym,yM)
                draw_windows(ax,samp.swin,x,ym,yM)
            elseif selected == "signal"
                setSwin!(obj,windows;seconds=true)
            end
        end
    end
end

function draw_windows(ax::Axis,
                      win::AbstractVector,
                      x::AbstractVector,
                      ym::AbstractFloat,
                      yM::AbstractFloat)
    out = []
    for w in win
        xm, xM = x[w[1]], x[w[2]]
        xy = [(xm,ym),(xm,yM),(xM,yM),(xM,ym)]
        box = poly!(ax, xy; color=:transparent, strokewidth=1.0, linestyle=:dot)
        push!(out,box)
    end
    return out
end
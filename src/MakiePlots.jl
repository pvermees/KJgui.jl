function MakiePlot!(ctrl::AbstractDict,
                    method::AbstractString,
                    channels::AbstractDict,
                    blank::AbstractDataFrame,
                    pars::NamedTuple,
                    standards::AbstractVector,
                    glass::AbstractVector;
                    num=nothing,den=ctrl["den"],
                    transformation=nothing,
                    seriestype=:scatter,
                    ms=5,ma=1,xlim=:auto,ylim=:auto,
                    linecol="black",linestyle=:solid,
                    i=nothing,show_title=true,
                    titlefontsize=14)
    Sanchors = getAnchors(method,standards,false)
    Ganchors = getAnchors(method,glass,true)
    anchors = merge(Sanchors,Ganchors)
    MakiePlot!(ctrl,channels,blank,pars,anchors;
               num=num,den=den,transformation=transformation,
               seriestype=seriestype,
               ms=ms,ma=ma,xlim=xlim,ylim=ylim,i=i,
               show_title=show_title,
               titlefontsize=titlefontsize)
end
function MakiePlot!(ctrl::AbstractDict,
                    method::AbstractString,
                    channels::AbstractDict,
                    blank::AbstractDataFrame,
                    pars::NamedTuple,
                    standards::AbstractDict,
                    glass::AbstractDict;
                    num=nothing,den=ctrl["den"],
                    transformation=nothing,
                    seriestype=:scatter,
                    ms=5,ma=1,xlim=:auto,ylim=:auto,
                    linecol="black",linestyle=:solid,i=nothing,
                    show_title=true,
                    titlefontsize=14)
    MakiePlot!(ctrl,method,channels,blank,pars,
               collect(keys(standards)),collect(keys(glass));
               num=num,den=den,transformation=transformation,
               seriestype=seriestype,ms=ms,ma=ma,
               xlim=xlim,ylim=ylim,
               linecol=linecol,linestyle=linestyle,i=i,
               show_title=show_title,
               titlefontsize=titlefontsize)
end
function MakiePlot!(ctrl::AbstractDict,
                    channels::AbstractDict;
                    num=nothing,den=ctrl["den"],
                    transformation=nothing,
                    seriestype=:scatter,
                    ms=5,ma=1,xlim=:auto,ylim=:auto,
                    display=true,i=nothing,
                    show_title=true,
                    titlefontsize=14)
    MakiePlot!(ctrl,collect(values(channels));
               num=num,den=den,transformation=transformation,
               seriestype=seriestype,
               ms=ms,ma=ma,xlim=xlim,ylim=ylim,i=i,
               show_title=show_title,
               titlefontsize=titlefontsize)
end
function MakiePlot!(ctrl::AbstractDict;
                    num=nothing,den=ctrl["den"],
                    transformation=nothing,
                    seriestype=:scatter,
                    ms=5,ma=1,xlim=:auto,ylim=:auto,
                    display=true,i=nothing,
                    show_title=true,
                    titlefontsize=14)
    MakiePlot!(ctrl,getChannels(samp);
               num=num,den=den,transformation=transformation,
               seriestype=seriestype,
               ms=ms,ma=ma,
               xlim=xlim,ylim=ylim,i=i,
               show_title=show_title,
               titlefontsize=titlefontsize)
end
function MakiePlot!(ctrl::AbstractDict,
                    channels::AbstractDict,
                    blank::AbstractDataFrame,
                    pars::NamedTuple,
                    anchors::AbstractDict;
                    num=nothing,den=ctrl["den"],
                    transformation=nothing,
                    seriestype=:scatter,
                    ms=5,ma=1,
                    xlim=:auto,ylim=:auto,
                    linecol="black",
                    linestyle=:solid,
                    i=nothing,
                    show_title=true,
                    titlefontsize=14)

    samp = ctrl["run"][ctrl["i"]]
    
    if samp.group == "sample"

        MakiePlot!(ctrl,channels;
                   num=num,den=den,transformation=transformation,
                   seriestype=seriestype,ms=ms,ma=ma,
                   xlim=xlim,ylim=ylim,display=display,i=i,
                   show_title=show_title,
                   titlefontsize=titlefontsize)
        
    else
        
        MakiePlot!(ctrl,channels;
                   num=num,den=den,transformation=transformation,
                   seriestype=seriestype,ms=ms,ma=ma,xlim=xlim,ylim=ylim,
                   display=display,i=i,show_title=show_title,
                   titlefontsize=titlefontsize)

        MakiePlotFitted!(ctrl["ax"],samp,blank,pars,channels,anchors;
                         num=num,den=den,transformation=transformation,
                         linecolor=linecol,linestyle=linestyle)
        
    end
end
# concentrations
function MakiePlot!(ctrl::AbstractDict,
                    blank::AbstractDataFrame,
                    pars::AbstractVector,
                    elements::AbstractDataFrame,
                    internal::AbstractString;
                    num=nothing,den=ctrl["den"],
                    transformation=nothing,
                    seriestype=:scatter,
                    ms=5,ma=1,xlim=:auto,ylim=:auto,
                    linecol="black",linestyle=:solid,i=nothing,
                    show_title=true,titlefontsize=14)

    samp = ctrl["run"][ctrl["i"]]
    
    if samp.group == "sample"

        MakiePlot!(ctrl;
                   num=num,den=den,transformation=transformation,
                   seriestype=seriestype,ms=ms,ma=ma,
                   xlim=xlim,ylim=ylim,display=display,i=i,
                   show_title=show_title,
                   titlefontsize=titlefontsize)
        
    else
        
        MakiePlot!(ctrl;
                   num=num,den=den,transformation=transformation,
                   seriestype=seriestype,ms=ms,ma=ma,xlim=xlim,ylim=ylim,
                   display=display,i=i,show_title=show_title,
                   titlefontsize=titlefontsize)

        MakiePlotFitted!(ctrl["ax"],samp,blank,pars,elements,internal;
                         num=num,den=den,transformation=transformation,
                         linecolor=linecol,linestyle=linestyle)
        
    end
end
function MakiePlot!(ctrl::AbstractDict,
                    blank::AbstractDataFrame,
                    pars::AbstractVector,
                    internal::AbstractString;
                    num=nothing,den=ctrl["den"],
                    transformation=nothing,
                    seriestype=:scatter,
                    ms=5,ma=1,xlim=:auto,ylim=:auto,
                    linecol="black",linestyle=:solid,i=nothing,
                    show_title=true,titlefontsize=14)
    elements = channels2elements(samp)
    MakiePlot!(ctrl,blank,pars,elements,internal;
               num=num,den=den,transformation=transformation,
               seriestype=seriestype,ms=ms,ma=ma,xlim=xlim,ylim=ylim,
               linecol=linecol,linestyle=linestyle,i=i,
               show_title=show_title,titlefontsize=titlefontsize)
end
function MakiePlot!(ctrl::AbstractDict,
                    channels::AbstractVector;
                    num=nothing,den=ctrl["den"],
                    transformation=nothing,
                    seriestype=:scatter,ms=5,ma=1,
                    xlim=:auto,ylim=:auto,
                    i::Union{Nothing,Integer}=nothing,
                    show_title=true,
                    titlefontsize=14)
    samp = ctrl["run"][ctrl["i"]]
    ax = ctrl["ax"]
    x, y, ty, xlab, ylab, ylim = KJ.prep_plot(samp,channels,num,den,ylim,transformation)
    ax.xlabel = xlab
    ax.ylabel = ylab
    ax.tellheight = false
    n_cols = size(ty,2)
    Random.seed!(4)
    for i in 1:n_cols
        good = isfinite.(ty[:,i])
        if seriestype == :scatter
            scatter!(ax, x[good], ty[good,i];
                     color = RGBf(rand(3)...),
                     markersize=ms, strokewidth=ma, label=names(ty)[i])
        else
            lines!(ax, x[good], ty[good,i]; linewidth=ms)
        end
    end
    if xlim != :auto
        xlimits!(ax, xlim)
    end
    if ylim != :auto
        ylimits!(ax, ylim)
    end
    if show_title
        title = samp.sname * " [" * samp.group * "]"
        if !isnothing(i)
            title = string(i) * ". " * title
        end
        ax.title = title
        ax.titlesize = titlefontsize
    end
    interactive_windows(ctrl,x)
    
end
export MakiePlot!

function interactive_windows(ctrl::AbstractDict,
                             x::AbstractVector)
    samp = ctrl["run"][ctrl["i"]]
    ax = ctrl["ax"]
    reset_limits!(ax)
    ylims = collect(ax.yaxis.attributes.limits.val)
    if !isnothing(samp.t0)
        lines!(ax, [samp.t0, samp.t0], ylims;
               color=:gray, linestyle=:dash)
    end
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
    bwin = draw_windows(ax,samp.bwin,x,ym,yM)
    swin = draw_windows(ax,samp.swin,x,ym,yM)
    blank = false
    fresh = true
    xy = nothing
    windows = []
    boxes = []
    x1,x2,xm,xM = 0.0,0.0,0.0,0.0
    register_interaction!(ax,:select_window) do event::MouseEvent, axis
        if event.type === MouseEventTypes.leftdragstart
            x1 = event.data[1]
            blank = x1 < samp.t0
            boxes = blank ? bwin : swin
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
            xy = Observable(Point2f[(xm,ym),(xm,yM),(xM,yM),(xM,ym)])
            box = poly!(ax,xy;color=:transparent, strokewidth=1.0, linestyle=:dot)
            push!(boxes,box)
        end
        if event.type === MouseEventTypes.leftdrag
            x2 = event.data[1]
            xm = minimum([x1,x2])
            xM = maximum([x1,x2])
            xy.val = [(xm,ym),(xm,yM),(xM,yM),(xM,ym)]
            notify(xy)
        end
        if event.type === MouseEventTypes.leftdragstop
            push!(windows,(xm,xM))
            obj = ispressed(ax,Keyboard.a) ? ctrl["run"] : samp
            if blank
                setBwin!(obj,windows;seconds=true)
            else
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

function MakiePlotFitted!(ax::Axis,
                          samp::Sample,
                          blank::AbstractDataFrame,
                          pars::NamedTuple,
                          channels::AbstractDict,
                          anchors::AbstractDict;
                          num=nothing,den=nothing,transformation=nothing,
                          linecolor="black",linestyle=:solid)
    pred = predict(samp,pars,blank,channels,anchors)
    rename!(pred,[channels[i] for i in names(pred)])
    MakiePlotFitted!(ax,samp,pred;
                     num=num,den=den,transformation=transformation,
                     linecolor=linecolor,linestyle=linestyle)
end
function MakiePlotFitted!(ax::Axis,
                          samp::Sample,
                          blank::AbstractDataFrame,
                          pars::AbstractVector,
                          elements::AbstractDataFrame,
                          internal::AbstractString;
                          num=nothing,den=nothing,transformation=nothing,
                          linecolor="black",linestyle=:solid)
    pred = predict(samp,pars,blank,elements,internal)
    MakiePlotFitted!(ax,samp,pred;
                     num=num,den=den,transformation=transformation,
                     linecolor=linecolor,linestyle=linestyle)
end
function MakiePlotFitted!(ax::Axis,
                          samp::Sample,
                          pred::AbstractDataFrame;
                          num=nothing,den=nothing,transformation=nothing,
                          linecolor="black",linestyle=:solid)
    x = KJ.windowData(samp,signal=true)[:,1]
    y = KJ.formRatios(pred,num,den)
    ty = KJ.transformeer(y,transformation)
    for tyi in eachcol(ty)
        lines!(x,tyi;color=linecolor,linestyle=linestyle)
    end
end
export MakiePlotFitted!

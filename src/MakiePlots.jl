function MakiePlot!(ax::Axis,
                    samp::Sample,
                    method::AbstractString,
                    channels::AbstractDict,
                    blank::AbstractDataFrame,
                    pars::NamedTuple,
                    standards::AbstractVector,
                    glass::AbstractVector;
                    num=nothing,den=nothing,
                    transformation=nothing,
                    seriestype=:scatter,
                    ms=5,ma=1,xlim=:auto,ylim=:auto,
                    linecol="black",linestyle=:solid,
                    i=nothing,show_title=true,
                    titlefontsize=14)
    Sanchors = getAnchors(method,standards,false)
    Ganchors = getAnchors(method,glass,true)
    anchors = merge(Sanchors,Ganchors)
    MakiePlot!(ax,samp,channels,blank,pars,anchors;
               num=num,den=den,transformation=transformation,
               seriestype=seriestype,
               ms=ms,ma=ma,xlim=xlim,ylim=ylim,i=i,
               show_title=show_title,
               titlefontsize=titlefontsize)
end
function MakiePlot!(ax::Axis,
                    samp::Sample,
                    method::AbstractString,
                    channels::AbstractDict,
                    blank::AbstractDataFrame,
                    pars::NamedTuple,
                    standards::AbstractDict,
                    glass::AbstractDict;
                    num=nothing,den=nothing,
                    transformation=nothing,
                    seriestype=:scatter,
                    ms=5,ma=1,xlim=:auto,ylim=:auto,
                    linecol="black",linestyle=:solid,i=nothing,
                    show_title=true,
                    titlefontsize=14)
    MakiePlot!(ax,samp,method,channels,blank,pars,
               collect(keys(standards)),collect(keys(glass));
               num=num,den=den,transformation=transformation,
               seriestype=seriestype,ms=ms,ma=ma,
               xlim=xlim,ylim=ylim,
               linecol=linecol,linestyle=linestyle,i=i,
               show_title=show_title,
               titlefontsize=titlefontsize)
end
function MakiePlot!(ax::Axis,
                    samp::Sample,
                    channels::AbstractDict;
                    num=nothing,den=nothing,
                    transformation=nothing,offset=nothing,
                    seriestype=:scatter,
                    ms=5,ma=1,xlim=:auto,ylim=:auto,
                    display=true,i=nothing,
                    show_title=true,
                    titlefontsize=14)
    MakiePlot!(ax,samp,collect(values(channels));
               num=num,den=den,transformation=transformation,
               offset=offset,seriestype=seriestype,
               ms=ms,ma=ma,xlim=xlim,ylim=ylim,i=i,
               show_title=show_title,
               titlefontsize=titlefontsize)
end
function MakiePlot!(ax::Axis,
                    samp::Sample;
                    num=nothing,den=nothing,
                    transformation=nothing,offset=nothing,
                    seriestype=:scatter,
                    ms=5,ma=1,xlim=:auto,ylim=:auto,
                    display=true,i=nothing,
                    show_title=true,
                    titlefontsize=14)
    MakiePlot!(ax,samp,getChannels(samp);
               num=num,den=den,transformation=transformation,
               offset=offset,seriestype=seriestype,
               ms=ms,ma=ma,
               xlim=xlim,ylim=ylim,i=i,
               show_title=show_title,
               titlefontsize=titlefontsize)
end
function MakiePlot!(ax::Axis,
                    samp::Sample,
                    channels::AbstractDict,
                    blank::AbstractDataFrame,
                    pars::NamedTuple,
                    anchors::AbstractDict;
                    num=nothing,den=nothing,
                    transformation=nothing,
                    seriestype=:scatter,
                    ms=5,ma=1,
                    xlim=:auto,ylim=:auto,
                    linecol="black",
                    linestyle=:solid,
                    i=nothing,
                    show_title=true,
                    titlefontsize=14)
    if samp.group == "sample"

        MakiePlot!(ax,samp,channels;
                   num=num,den=den,transformation=transformation,
                   seriestype=seriestype,ms=ms,ma=ma,
                   xlim=xlim,ylim=ylim,display=display,i=i,
                   show_title=show_title,
                   titlefontsize=titlefontsize)
        
    else

        offset = getOffset(samp,channels,blank,pars,anchors,transformation;
                           num=num,den=den)

        MakiePlot!(ax,samp,channels;
                   num=num,den=den,transformation=transformation,offset=offset,
                   seriestype=seriestype,ms=ms,ma=ma,xlim=xlim,ylim=ylim,
                   display=display,i=i,show_title=show_title,
                   titlefontsize=titlefontsize)

        MakiePlotFitted!(ax,samp,blank,pars,channels,anchors;
                         num=num,den=den,transformation=transformation,
                         offset=offset,linecolor=linecol,linestyle=linestyle)
        
    end
end
# concentrations
function MakiePlot!(ax::Axis,
                    samp::Sample,
                    blank::AbstractDataFrame,
                    pars::AbstractVector,
                    elements::AbstractDataFrame,
                    internal::AbstractString;
                    num=nothing,den=nothing,
                    transformation=nothing,
                    seriestype=:scatter,
                    ms=5,ma=1,xlim=:auto,ylim=:auto,
                    linecol="black",linestyle=:solid,i=nothing,
                    show_title=true,titlefontsize=14)
    if samp.group == "sample"

        MakiePlot!(ax,samp;
                   num=num,den=den,transformation=transformation,
                   seriestype=seriestype,ms=ms,ma=ma,
                   xlim=xlim,ylim=ylim,display=display,i=i,
                   show_title=show_title,
                   titlefontsize=titlefontsize)
        
    else

        offset = getOffset(samp,blank,pars,elements,internal,transformation;
                           num=num,den=den)

        MakiePlot!(ax,samp;
                   num=num,den=den,transformation=transformation,offset=offset,
                   seriestype=seriestype,ms=ms,ma=ma,xlim=xlim,ylim=ylim,
                   display=display,i=i,show_title=show_title,
                   titlefontsize=titlefontsize)

        MakiePlotFitted!(ax,samp,blank,pars,elements,internal;
                         num=num,den=den,transformation=transformation,
                         offset=offset,linecolor=linecol,linestyle=linestyle)
        
    end
end
function MakiePlot!(ax::Axis,
                    samp::Sample,
                    blank::AbstractDataFrame,
                    pars::AbstractVector,
                    internal::AbstractString;
                    num=nothing,den=nothing,
                    transformation=nothing,
                    seriestype=:scatter,
                    ms=5,ma=1,xlim=:auto,ylim=:auto,
                    linecol="black",linestyle=:solid,i=nothing,
                    show_title=true,titlefontsize=14)
    elements = channels2elements(samp)
    MakiePlot!(ax,samp,blank,pars,elements,internal;
               num=num,den=den,transformation=transformation,
               seriestype=seriestype,ms=ms,ma=ma,xlim=xlim,ylim=ylim,
               linecol=linecol,linestyle=linestyle,i=i,
               show_title=show_title,titlefontsize=titlefontsize)
end
function MakiePlot!(ax::Axis,
                    samp::Sample,
                    channels::AbstractVector;
                    num=nothing,den=nothing,
                    transformation=nothing,offset=nothing,
                    seriestype=:scatter,ms=5,ma=1,
                    xlim=:auto,ylim=:auto,
                    i::Union{Nothing,Integer}=nothing,
                    show_title=true,
                    titlefontsize=14)
    xlab = names(samp.dat)[1]
    x = samp.dat[:,xlab]
    meas = samp.dat[:,channels]
    y = (isnothing(num) && isnothing(den)) ? meas : KJ.formRatios(meas,num,den)
    if isnothing(offset)
        offset = Dict(zip(names(y),fill(0.0,size(y,2))))
    end
    ty = KJ.transformeer(y;transformation=transformation,offset=offset)
    ratsig = isnothing(den) ? "signal" : "ratio"
    ylab = isnothing(transformation) ? ratsig : transformation*"("*ratsig*")"

    ax.xlabel = xlab
    ax.tellheight = false
    n_cols = size(ty,2)
    Random.seed!(4)
    for i in 1:n_cols
        good = isfinite.(ty[:,i])
        if seriestype == :scatter
            sc = scatter!(ax, x[good], ty[good,i];
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
    reset_limits!(ax)
    ylims = collect(ax.yaxis.attributes.limits.val)
    if !isnothing(samp.t0)
        lines!(ax, [samp.t0, samp.t0], ylims;
               color=:gray, linestyle=:dash)
    end
    bwin = draw_windows(ax,samp.bwin,x,ylims)
    swin = draw_windows(ax,samp.swin,x,ylims)
    spoint = select_point(ax.scene, marker = :circle)
    on(spoint) do xy
        update_windows!(ax,samp,bwin,swin,x,ylims,xy)
    end

end
export MakiePlot!

function draw_windows(ax::Axis,
                      win::AbstractVector,
                      x::AbstractVector,
                      ylims::AbstractVector)
    out = []
    for w in win
        xy = Observable(Point2f[])
        xm, xM = x[w[1]], x[w[2]]
        ym, yM = ylims[1], ylims[2]
        xy[] = [[xm,ym],[xm,yM],[xM,yM],[xM,ym],[xm,ym]]
        poly!(ax, xy; color=:transparent, strokewidth=1.0, linestyle=:dot)
        push!(out,xy)
    end
    return out
end

function update_windows!(ax::Axis,
                         samp::Sample,
                         bwin::AbstractVector,
                         swin::AbstractVector,
                         x::AbstractVector,
                         ylims::AbstractVector,
                         xy::AbstractVector)
    println(xy)
end

function MakiePlotFitted!(ax::Axis,
                          samp::Sample,
                          blank::AbstractDataFrame,
                          pars::NamedTuple,
                          channels::AbstractDict,
                          anchors::AbstractDict;
                          num=nothing,den=nothing,transformation=nothing,
                          offset::AbstractDict,linecolor="black",linestyle=:solid)
    pred = predict(samp,pars,blank,channels,anchors)
    rename!(pred,[channels[i] for i in names(pred)])
    MakiePlotFitted!(ax,samp,pred;
                     num=num,den=den,transformation=transformation,
                     offset=offset,linecolor=linecolor,linestyle=linestyle)
end
function MakiePlotFitted!(ax::Axis,
                          samp::Sample,
                          blank::AbstractDataFrame,
                          pars::AbstractVector,
                          elements::AbstractDataFrame,
                          internal::AbstractString;
                          num=nothing,den=nothing,transformation=nothing,
                          offset::AbstractDict,linecolor="black",linestyle=:solid)
    pred = predict(samp,pars,blank,elements,internal)
    MakiePlotFitted!(ax,samp,pred;
                     num=num,den=den,transformation=transformation,
                     offset=offset,linecolor=linecolor,linestyle=linestyle)
end
function MakiePlotFitted!(ax::Axis,
                          samp::Sample,
                          pred::AbstractDataFrame;
                          num=nothing,den=nothing,transformation=nothing,
                          offset::AbstractDict,linecolor="black",linestyle=:solid)
    x = windowData(samp,signal=true)[:,1]
    y = formRatios(pred,num,den)
    ty = KJ.transformeer(y;transformation=transformation,offset=offset)
    for tyi in eachcol(ty)
        lines!(x,tyi)
    end
end
export MakiePlotFitted!

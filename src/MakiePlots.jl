function MakiePlot(fig,
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
                   i=nothing,legend=:lt,
                   show_title=true,
                   titlefontsize=14)
    Sanchors = getAnchors(method,standards,false)
    Ganchors = getAnchors(method,glass,true)
    anchors = merge(Sanchors,Ganchors)
    return MakiePlot(fig,samp,channels,blank,pars,anchors;
                     num=num,den=den,transformation=transformation,
                     seriestype=seriestype,
                     ms=ms,ma=ma,xlim=xlim,ylim=ylim,i=i,
                     legend=legend,show_title=show_title,
                     titlefontsize=titlefontsize)
end
function MakiePlot(fig,
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
                   legend=:lt,
                   show_title=true,
                   titlefontsize=14)
    return MakiePlot(fig,samp,method,channels,blank,pars,
                     collect(keys(standards)),collect(keys(glass));
                     num=num,den=den,transformation=transformation,
                     seriestype=seriestype,ms=ms,ma=ma,
                     xlim=xlim,ylim=ylim,
                     linecol=linecol,linestyle=linestyle,i=i,
                     legend=legend,show_title=show_title,
                     titlefontsize=titlefontsize)
end
function MakiePlot(fig,
                   samp::Sample,
                   channels::AbstractDict;
                   num=nothing,den=nothing,
                   transformation=nothing,offset=nothing,
                   seriestype=:scatter,
                   ms=5,ma=1,xlim=:auto,ylim=:auto,
                   display=true,i=nothing,
                   legend=:lt,
                   show_title=true,
                   titlefontsize=14)
    return MakiePlot(fig,samp,collect(values(channels));
                     num=num,den=den,transformation=transformation,
                     offset=offset,seriestype=seriestype,
                     ms=ms,ma=ma,xlim=xlim,ylim=ylim,i=i,
                     legend=legend,show_title=show_title,
                     titlefontsize=titlefontsize)
end
function MakiePlot(fig,
                   samp::Sample;
                   num=nothing,den=nothing,
                   transformation=nothing,offset=nothing,
                   seriestype=:scatter,
                   ms=5,ma=1,xlim=:auto,ylim=:auto,
                   display=true,i=nothing,
                   legend=:lt,
                   show_title=true,
                   titlefontsize=14)
    return MakiePlot(fig,samp,getChannels(samp);
                     num=num,den=den,transformation=transformation,
                     offset=offset,seriestype=seriestype,
                     ms=ms,ma=ma,
                     xlim=xlim,ylim=ylim,i=i,
                     legend=legend,show_title=show_title,
                     titlefontsize=titlefontsize)
end
function MakiePlot(fig,
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
                   legend=:lt,
                   show_title=true,
                   titlefontsize=14)
    if samp.group == "sample"

        ax = MakiePlot(fig,samp,channels;
                       num=num,den=den,transformation=transformation,
                       seriestype=seriestype,ms=ms,ma=ma,
                       xlim=xlim,ylim=ylim,display=display,i=i,
                       legend=legend,show_title=show_title,
                       titlefontsize=titlefontsize)
        
    else

        offset = getOffset(samp,channels,blank,pars,anchors,transformation;
                           num=num,den=den)

        ax = MakiePlot(fig,samp,channels;
                       num=num,den=den,transformation=transformation,offset=offset,
                       seriestype=seriestype,ms=ms,ma=ma,xlim=xlim,ylim=ylim,
                       display=display,i=i,legend=legend,show_title=show_title,
                       titlefontsize=titlefontsize)

        MakiePlotFitted!(ax,samp,blank,pars,channels,anchors;
                         num=num,den=den,transformation=transformation,
                         offset=offset,linecolor=linecol,linestyle=linestyle)
        
    end
    return ax
end
# concentrations
function MakiePlot(fig,
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
                   legend=:lt,show_title=true,titlefontsize=14)
    if samp.group == "sample"

        ax = MakiePlot(fig,samp;
                       num=num,den=den,transformation=transformation,
                       seriestype=seriestype,ms=ms,ma=ma,
                       xlim=xlim,ylim=ylim,display=display,i=i,
                       legend=legend,show_title=show_title,
                       titlefontsize=titlefontsize)
        
    else

        offset = getOffset(samp,blank,pars,elements,internal,transformation;
                           num=num,den=den)

        ax = MakiePlot(fig,samp;
                       num=num,den=den,transformation=transformation,offset=offset,
                       seriestype=seriestype,ms=ms,ma=ma,xlim=xlim,ylim=ylim,
                       display=display,i=i,legend=legend,show_title=show_title,
                       titlefontsize=titlefontsize)

        MakiePlotFitted!(ax,samp,blank,pars,elements,internal;
                         num=num,den=den,transformation=transformation,
                         offset=offset,linecolor=linecol,linestyle=linestyle)
        
    end
    return ax
end
function MakiePlot(fig,
                   samp::Sample,
                   blank::AbstractDataFrame,
                   pars::AbstractVector,
                   internal::AbstractString;
                   num=nothing,den=nothing,
                   transformation=nothing,
                   seriestype=:scatter,
                   ms=5,ma=1,xlim=:auto,ylim=:auto,
                   linecol="black",linestyle=:solid,i=nothing,
                   legend=:lt,show_title=true,titlefontsize=14)
    elements = channels2elements(samp)
    return MakiePlot(fig,samp,blank,pars,elements,internal;
                     num=num,den=den,transformation=transformation,
                     seriestype=seriestype,ms=ms,ma=ma,xlim=xlim,ylim=ylim,
                     linecol=linecol,linestyle=linestyle,i=i,
                     legend=legend,show_title=show_title,
                     titlefontsize=titlefontsize)
end
function MakiePlot(fig,
                   samp::Sample,
                   channels::AbstractVector;
                   num=nothing,den=nothing,
                   transformation=nothing,offset=nothing,
                   seriestype=:scatter,ms=5,ma=1,
                   xlim=:auto,ylim=:auto,
                   i::Union{Nothing,Integer}=nothing,
                   legend=:lt,
                   show_title=true,
                   titlefontsize=14)
    xlab = names(samp.dat)[1]
    x = samp.dat[:,xlab]
    meas = samp.dat[:,channels]
    y = (isnothing(num) && isnothing(den)) ? meas : formRatios(meas,num,den)
    if isnothing(offset)
        offset = Dict(zip(names(y),fill(0.0,size(y,2))))
    end
    ty = KJ.transformeer(y;transformation=transformation,offset=offset)
    ratsig = isnothing(den) ? "signal" : "ratio"
    ylab = isnothing(transformation) ? ratsig : transformation*"("*ratsig*")"

    if show_title
        title = samp.sname * " [" * samp.group * "]"
        if !isnothing(i)
            title = string(i) * ". " * title
        end
        ax = Axis(fig;
                  xlabel=xlab,title=title,
                  titlesize=titlefontsize,tellheight=false)
    else
        ax = Axis(fig;
                  xlabel=xlab,tellheight=false)
    end
    n_cols = size(ty,2)
    if seriestype == :scatter
        for i in 1:n_cols
            sc = scatter!(ax, x, ty[:,i];
                          markersize=ms, strokewidth=ma, label=names(ty)[i])
        end
    else
        for i in 1:n_cols
            lines!(ax, x, ty[:,i]; linewidth=ms)
        end
    end
    if xlim != :auto
        xlimits!(ax, xlim)
    end
    if ylim != :auto
        ylimits!(ax, ylim)
    end
    reset_limits!(ax)
    ylims = collect(ax.yaxis.attributes.limits.val)
    if !isnothing(samp.t0)
        lines!(ax, [samp.t0, samp.t0], ylims;
               color=:gray, linestyle=:dash)
    end
    for win in [samp.bwin, samp.swin]
        for w in win
            xm, xM = x[w[1]], x[w[2]]
            ym, yM = ylims[1], ylims[2]
            poly!(ax, [xm, xm, xM, xM, xm], [ym, yM, yM, ym, ym];
                  color=:transparent, strokewidth=1.0, linestyle=:dot)
        end
    end
    if legend != :none
        axislegend(ax;position=legend)
    end
    
    return ax
end

function MakiePlotFitted!(ax,
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
function MakiePlotFitted!(ax,
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
function MakiePlotFitted!(ax,
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

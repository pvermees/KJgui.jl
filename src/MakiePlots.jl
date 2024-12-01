function MakiePlot(samp::Sample,
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
                   i=nothing,legend=:topleft,
                   show_title=true,
                   titlefontsize=14)
    Sanchors = getAnchors(method,standards,false)
    Ganchors = getAnchors(method,glass,true)
    anchors = merge(Sanchors,Ganchors)
    return MakiePlot(samp,channels,blank,pars,anchors;
                     num=num,den=den,transformation=transformation,
                     seriestype=seriestype,
                     ms=ms,ma=ma,xlim=xlim,ylim=ylim,i=i,
                     legend=legend,show_title=show_title,
                     titlefontsize=titlefontsize)
end
function MakiePlot(samp::Sample,
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
                   legend=:topleft,
                   show_title=true,
                   titlefontsize=14)
    return MakiePlot(samp,method,channels,blank,pars,
                     collect(keys(standards)),collect(keys(glass));
                     num=num,den=den,transformation=transformation,
                     seriestype=seriestype,ms=ms,ma=ma,
                     xlim=xlim,ylim=ylim,
                     linecol=linecol,linestyle=linestyle,i=i,
                     legend=legend,show_title=show_title,
                     titlefontsize=titlefontsize)
end
function MakiePlot(samp::Sample,
                   channels::AbstractDict;
                   num=nothing,den=nothing,
                   transformation=nothing,offset=nothing,
                   seriestype=:scatter,
                   ms=5,ma=1,xlim=:auto,ylim=:auto,
                   display=true,i=nothing,
                   legend=:topleft,
                   show_title=true,
                   titlefontsize=14)
    return MakiePlot(samp,collect(values(channels));
                     num=num,den=den,transformation=transformation,
                     offset=offset,seriestype=seriestype,
                     ms=ms,ma=ma,xlim=xlim,ylim=ylim,i=i,
                     legend=legend,show_title=show_title,
                     titlefontsize=titlefontsize)
end
function MakiePlot(samp::Sample;
                   num=nothing,den=nothing,
                   transformation=nothing,offset=nothing,
                   seriestype=:scatter,
                   ms=5,ma=1,xlim=:auto,ylim=:auto,
                   display=true,i=nothing,
                   legend=:topleft,
                   show_title=true,
                   titlefontsize=14)
    return MakiePlot(samp,getChannels(samp);
                  num=num,den=den,transformation=transformation,
                  offset=offset,seriestype=seriestype,
                  ms=ms,ma=ma,
                  xlim=xlim,ylim=ylim,i=i,
                  legend=legend,show_title=show_title,

                  titlefontsize=titlefontsize)
end
function MakiePlot(samp::Sample,
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
                   legend=:topleft,
                   show_title=true,
                   titlefontsize=14)
    if samp.group == "sample"

        p = MakiePlot(samp,channels;
                      num=num,den=den,transformation=transformation,
                      seriestype=seriestype,ms=ms,ma=ma,
                      xlim=xlim,ylim=ylim,display=display,i=i,
                      legend=legend,show_title=show_title,
                      titlefontsize=titlefontsize)
        
    else

        offset = getOffset(samp,channels,blank,pars,anchors,transformation;
                           num=num,den=den)

        p = MakiePlot(samp,channels;
                      num=num,den=den,transformation=transformation,offset=offset,
                      seriestype=seriestype,ms=ms,ma=ma,xlim=xlim,ylim=ylim,
                      display=display,i=i,legend=legend,show_title=show_title,
                      titlefontsize=titlefontsize)

        MakiePlotFitted!(p,samp,blank,pars,channels,anchors;
                         num=num,den=den,transformation=transformation,
                         offset=offset,linecolor=linecol,linestyle=linestyle)
        
    end
    return p
end
# concentrations
function MakiePlot(samp::Sample,
                   blank::AbstractDataFrame,
                   pars::AbstractVector,
                   elements::AbstractDataFrame,
                   internal::AbstractString;
                   num=nothing,den=nothing,
                   transformation=nothing,
                   seriestype=:scatter,
                   ms=5,ma=1,xlim=:auto,ylim=:auto,
                   linecol="black",linestyle=:solid,i=nothing,
                   legend=:topleft,show_title=true,titlefontsize=14)
    if samp.group == "sample"

        p = MakiePlot(samp;
                      num=num,den=den,transformation=transformation,
                      seriestype=seriestype,ms=ms,ma=ma,
                      xlim=xlim,ylim=ylim,display=display,i=i,
                      legend=legend,show_title=show_title,
                      titlefontsize=titlefontsize)
        
    else

        offset = getOffset(samp,blank,pars,elements,internal,transformation;
                           num=num,den=den)

        p = MakiePlot(samp;
                      num=num,den=den,transformation=transformation,offset=offset,
                      seriestype=seriestype,ms=ms,ma=ma,xlim=xlim,ylim=ylim,
                      display=display,i=i,legend=legend,show_title=show_title,
                      titlefontsize=titlefontsize)

        MakiePlotFitted!(p,samp,blank,pars,elements,internal;
                         num=num,den=den,transformation=transformation,
                         offset=offset,linecolor=linecol,linestyle=linestyle)
        
    end
    return p
end
function MakiePlot(samp::Sample,
                   blank::AbstractDataFrame,
                   pars::AbstractVector,
                   internal::AbstractString;
                   num=nothing,den=nothing,
                   transformation=nothing,
                   seriestype=:scatter,
                   ms=5,ma=1,xlim=:auto,ylim=:auto,
                   linecol="black",linestyle=:solid,i=nothing,
                   legend=:topleft,show_title=true,titlefontsize=14)
    elements = channels2elements(samp)
    return MakiePlot(samp,blank,pars,elements,internal;
                     num=num,den=den,transformation=transformation,
                     seriestype=seriestype,ms=ms,ma=ma,xlim=xlim,ylim=ylim,
                     linecol=linecol,linestyle=linestyle,i=i,
                     legend=legend,show_title=show_title,
                     titlefontsize=titlefontsize)
end
function MakiePlot(samp::Sample,
                   channels::AbstractVector;
                   num=nothing,den=nothing,
                   transformation=nothing,offset=nothing,
                   seriestype=:scatter,ms=5,ma=1,
                   xlim=:auto,ylim=:auto,
                   i::Union{Nothing,Integer}=nothing,
                   legend=:topleft,
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

    p = Figure()
    if show_title
        title = samp.sname * " [" * samp.group * "]"
        if !isnothing(i)
            title = string(i) * ". " * title
        end
        ax = Axis(p[1,1];xlabel=xlab,title=title,titlesize=titlefontsize)
    else
        ax = Axis(p[1,1];xlabel=xlab)
    end
    n_cols = size(ty,2)
    if seriestype == :scatter
        for i in 1:n_cols
            scatter!(ax, x, ty[:,i];
                     markersize=ms, strokewidth=ma, label=names(ty))
        end
    else
        for i in 1:n_cols
            lines!(ax, x, ty[:,i]; linewidth=ms, label=names(ty))
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
               color=:gray, linestyle=:dash, label="")
    end
    for win in [samp.bwin, samp.swin]
        for w in win
            xm, xM = x[w[1]], x[w[2]]
            ym, yM = ylims[1], ylims[2]
            poly!(ax, [xm, xm, xM, xM, xm], [ym, yM, yM, ym, ym];
                  color=:transparent, strokewidth=1.0, linestyle=:dot)
        end
    end
    return p
end

function MakiePlotFitted!(p,
                          samp::Sample,
                          blank::AbstractDataFrame,
                          pars::NamedTuple,
                          channels::AbstractDict,
                          anchors::AbstractDict;
                          num=nothing,den=nothing,transformation=nothing,
                          offset::AbstractDict,linecolor="black",linestyle=:solid)
    pred = predict(samp,pars,blank,channels,anchors)
    rename!(pred,[channels[i] for i in names(pred)])
    MakiePlotFitted!(p,samp,pred;
                     num=num,den=den,transformation=transformation,
                     offset=offset,linecolor=linecolor,linestyle=linestyle)
end
function MakiePlotFitted!(p,
                          samp::Sample,
                          blank::AbstractDataFrame,
                          pars::AbstractVector,
                          elements::AbstractDataFrame,
                          internal::AbstractString;
                          num=nothing,den=nothing,transformation=nothing,
                          offset::AbstractDict,linecolor="black",linestyle=:solid)
    pred = predict(samp,pars,blank,elements,internal)
    MakiePlotFitted!(p,samp,pred;
                     num=num,den=den,transformation=transformation,
                     offset=offset,linecolor=linecolor,linestyle=linestyle)
end
function MakiePlotFitted!(p,
                          samp::Sample,
                          pred::AbstractDataFrame;
                          num=nothing,den=nothing,transformation=nothing,
                          offset::AbstractDict,linecolor="black",linestyle=:solid)
    x = windowData(samp,signal=true)[:,1]
    y = formRatios(pred,num,den)
    ty = KJ.transformeer(y;transformation=transformation,offset=offset)
    ax = Axis(p[1,1])
    for tyi in eachcol(ty)
        lines!(x,tyi)
    end
end
export MakiePlotFitted!

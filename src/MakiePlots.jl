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
                   ms=2,ma=0.5,xlim=:auto,ylim=:auto,
                   linecol="black",linestyle=:solid,
                   i=nothing,legend=:topleft,
                   show_title=true,
                   titlefontsize=10)
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
                   ms=2,ma=0.5,xlim=:auto,ylim=:auto,
                   linecol="black",linestyle=:solid,i=nothing,
                   legend=:topleft,
                   show_title=true,
                   titlefontsize=10)
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
                   ms=2,ma=0.5,xlim=:auto,ylim=:auto,
                   display=true,i=nothing,
                   legend=:topleft,
                   show_title=true,
                   titlefontsize=10)
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
                   ms=2,ma=0.5,xlim=:auto,ylim=:auto,
                   display=true,i=nothing,
                   legend=:topleft,
                   show_title=true,
                   titlefontsize=10)
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
                   ms=2,ma=0.5,
                   xlim=:auto,ylim=:auto,
                   linecol="black",
                   linestyle=:solid,
                   i=nothing,
                   legend=:topleft,
                   show_title=true,
                   titlefontsize=10)
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
                   ms=2,ma=0.5,xlim=:auto,ylim=:auto,
                   linecol="black",linestyle=:solid,i=nothing,
                   legend=:topleft,show_title=true,titlefontsize=10)
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
                   ms=2,ma=0.5,xlim=:auto,ylim=:auto,
                   linecol="black",linestyle=:solid,i=nothing,
                   legend=:topleft,show_title=true,titlefontsize=10)
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
                   seriestype=:scatter,ms=2,ma=0.5,
                   xlim=:auto,ylim=:auto,
                   i::Union{Nothing,Integer}=nothing,
                   legend=:topleft,
                   show_title=true,
                   titlefontsize=10)
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

    n_cols = size(ty,2)
    p = Figure()
    ax = Axis(p[1, 1])
    for i in 1:n_cols
        scatter!(ax, x,ty[:,i])
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

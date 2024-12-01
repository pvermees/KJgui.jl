function GUIviewer!(ctrl::AbstractDict)
    GUIplotter(ctrl)
    return "view"
end

function GUIplotter(ctrl::AbstractDict)
    samp = ctrl["run"][ctrl["i"]]
    if ctrl["method"] == "concentrations"
        fig = GUIconcentrationPlotter(ctrl,samp)
    else
        fig = GUIgeochronPlotter(ctrl,samp)
    end
    if !isnothing(ctrl["PAcutoff"])
        GUIaddPAline!(p,ctrl["PAcutoff"])
    end
    display(fig)
    return nothing
end

function GUIconcentrationPlotter(ctrl::AbstractDict,samp::Sample)
    if (samp.group in keys(ctrl["glass"])) & !isnothing(ctrl["blank"])
        fig = MakiePlot(samp,ctrl["blank"],ctrl["par"],ctrl["internal"][1];
                        den=ctrl["den"],transformation=ctrl["transformation"],
                        i=ctrl["i"])
    else
        fig = MakiePlot(samp;den=ctrl["den"],
                        transformation=ctrl["transformation"],
                        i=ctrl["i"])
    end
    return fig
end

function GUIgeochronPlotter(ctrl::AbstractDict,samp::Sample)
    if isnothing(ctrl["blank"]) | (samp.group=="sample")
        fig = MakiePlot(samp,ctrl["channels"];
                        den=ctrl["den"],transformation=ctrl["transformation"],i=ctrl["i"])
    else
        anchors = KJ.getAnchors(ctrl["method"],ctrl["standards"],ctrl["glass"])
        fig = MakiePlot(samp,ctrl["method"],ctrl["channels"],ctrl["blank"],
                        ctrl["par"],ctrl["standards"],ctrl["glass"];
                        den=ctrl["den"],transformation=ctrl["transformation"],i=ctrl["i"])
    end
    return fig
end

function GUInext!(ctrl::AbstractDict)
    ctrl["i"] += 1
    if ctrl["i"]>length(ctrl["run"]) ctrl["i"] = 1 end
    return GUIplotter(ctrl)
end

function GUIprevious!(ctrl::AbstractDict)
    ctrl["i"] -= 1
    if ctrl["i"]<1 ctrl["i"] = length(ctrl["run"]) end
    return GUIplotter(ctrl)
end

function GUIgoto!(ctrl::AbstractDict,
                  response::AbstractString)
    ctrl["i"] = parse(Int,response)
    if ctrl["i"]>length(ctrl["run"]) ctrl["i"] = 1 end
    if ctrl["i"]<1 ctrl["i"] = length(ctrl["run"]) end
    GUIplotter(ctrl)
    return "x"
end

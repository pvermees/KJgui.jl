function GUIviewer!(ctrl::AbstractDict)
    GUIplotter(ctrl)
    return "view"
end

function GUIplotter(ctrl::AbstractDict)
    samp = ctrl["run"][ctrl["i"]]
    fig = Figure()
    grid = fig[1,1] = GridLayout()
    prev = Button(fig, label = "<")
    next = Button(fig, label = ">")
    if ctrl["method"] == "concentrations"
        ax = GUIconcentrationPlotter(fig,ctrl,samp)
    else
        ax = GUIgeochronPlotter(fig,ctrl,samp)
    end
    if !isnothing(ctrl["PAcutoff"])
        GUIaddPAline!(ax,ctrl["PAcutoff"])
    end
    grid[1:2, 1] = prev
    grid[1:2, 2] = ax
    grid[1:2, 3] = next
    display(fig)
    return nothing
end

function GUIconcentrationPlotter!(fig,ctrl::AbstractDict,samp::Sample)
    if (samp.group in keys(ctrl["glass"])) & !isnothing(ctrl["blank"])
        ax = MakiePlot(fig,samp,ctrl["blank"],ctrl["par"],ctrl["internal"][1];
                       den=ctrl["den"],transformation=ctrl["transformation"],
                       i=ctrl["i"])
    else
        ax = MakiePlot(fig,samp;den=ctrl["den"],
                       transformation=ctrl["transformation"],
                       i=ctrl["i"])
    end
    return ax
end

function GUIgeochronPlotter(fig,ctrl::AbstractDict,samp::Sample)
    if isnothing(ctrl["blank"]) | (samp.group=="sample")
        ax = MakiePlot(fig,samp,ctrl["channels"];
                       den=ctrl["den"],transformation=ctrl["transformation"],i=ctrl["i"])
    else
        anchors = KJ.getAnchors(ctrl["method"],ctrl["standards"],ctrl["glass"])
        ax = MakiePlot(fig,samp,ctrl["method"],ctrl["channels"],ctrl["blank"],
                       ctrl["par"],ctrl["standards"],ctrl["glass"];
                       den=ctrl["den"],transformation=ctrl["transformation"],i=ctrl["i"])
    end
    return ax
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

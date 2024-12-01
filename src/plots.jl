function GUIviewer!(ctrl::AbstractDict)
    GUIplotter(ctrl)
    return "view"
end

function GUIplotter(ctrl::AbstractDict)
    fig = Figure()
    grid = fig[1,1] = GridLayout()
    prev = Button(fig, label = "<")
    next = Button(fig, label = ">")
    ax = Axis(fig)
    GUIplotter!(ax,ctrl)
    axislegend(ax;position=:lt)
    on(prev.clicks) do _
        empty!(ax)
        GUIprevious!(ctrl,ax)
    end
    on(next.clicks) do _
        empty!(ax)
        GUInext!(ctrl,ax)
    end
    grid[1:2, 1] = prev
    grid[1:2, 2] = ax
    grid[1:2, 3] = next
    display(fig)
end

function GUIplotter!(ax::Axis,ctrl::AbstractDict)
    samp = ctrl["run"][ctrl["i"]]
    if ctrl["method"] == "concentrations"
        GUIconcentrationPlotter!(ax,ctrl,samp)
    else
        GUIgeochronPlotter!(ax,ctrl,samp)
    end
    if !isnothing(ctrl["PAcutoff"])
        GUIaddPAline!(ax,ctrl["PAcutoff"])
    end
end

function GUIconcentrationPlotter!(ax::Axis,ctrl::AbstractDict,samp::Sample)
    if (samp.group in keys(ctrl["glass"])) & !isnothing(ctrl["blank"])
        MakiePlot!(ax,samp,ctrl["blank"],ctrl["par"],ctrl["internal"][1];
                   den=ctrl["den"],transformation=ctrl["transformation"],
                   i=ctrl["i"])
    else
        MakiePlot!(ax,samp;den=ctrl["den"],
                   transformation=ctrl["transformation"],
                   i=ctrl["i"])
    end
end

function GUIgeochronPlotter!(ax::Axis,ctrl::AbstractDict,samp::Sample)
    if isnothing(ctrl["blank"]) | (samp.group=="sample")
        MakiePlot!(ax,samp,ctrl["channels"];
                   den=ctrl["den"],transformation=ctrl["transformation"],i=ctrl["i"])
    else
        anchors = KJ.getAnchors(ctrl["method"],ctrl["standards"],ctrl["glass"])
        MakiePlot!(ax,samp,ctrl["method"],ctrl["channels"],ctrl["blank"],
                   ctrl["par"],ctrl["standards"],ctrl["glass"];
                   den=ctrl["den"],transformation=ctrl["transformation"],i=ctrl["i"])
    end
end

function GUInext!(ctrl::AbstractDict,ax::Axis)
    ctrl["i"] += 1
    if ctrl["i"]>length(ctrl["run"]) ctrl["i"] = 1 end
    return GUIplotter!(ax,ctrl)
end

function GUIprevious!(ctrl::AbstractDict,ax::Axis)
    ctrl["i"] -= 1
    if ctrl["i"]<1 ctrl["i"] = length(ctrl["run"]) end
    return GUIplotter!(ax,ctrl)
end

function GUIgoto!(ctrl::AbstractDict,
                  response::AbstractString)
    ctrl["i"] = parse(Int,response)
    if ctrl["i"]>length(ctrl["run"]) ctrl["i"] = 1 end
    if ctrl["i"]<1 ctrl["i"] = length(ctrl["run"]) end
    GUIplotter(ctrl)
    return "x"
end

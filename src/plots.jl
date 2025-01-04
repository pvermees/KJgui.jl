function GUIviewer!(ctrl::AbstractDict)
    GUIplotter(ctrl)
    return "view"
end

function GUIplotter(ctrl::AbstractDict)
    fig = Figure()
    grid = fig[1,1] = GridLayout()
    prev = Button(fig, label = "<")
    next = Button(fig, label = ">")
    ctrl["ax"] = Axis(fig)
    GUIplotter!(ctrl)
    on(prev.clicks) do _
        GUIprevious!(ctrl)
    end
    on(next.clicks) do _
        GUInext!(ctrl)
    end
    grid[1:2, 1] = prev
    grid[1:2, 2] = ctrl["ax"]
    grid[1:2, 3] = next
    display(fig)
end

function GUIplotter!(ctrl::AbstractDict)
    GUIclear!(ctrl)
    samp = ctrl["run"][ctrl["i"]]
    if ctrl["method"] == "concentrations"
        GUIconcentrationPlotter!(ctrl,samp)
    else
        GUIgeochronPlotter!(ctrl,samp)
    end
    ctrl["legend"] = axislegend(ctrl["ax"];position=:lt)
    if !isnothing(ctrl["PAcutoff"])
        GUIaddPAline!(ctrl["PAcutoff"])
    end
end

function GUIconcentrationPlotter!(ctrl::AbstractDict,samp::Sample)
    if (samp.group in keys(ctrl["glass"])) & !isnothing(ctrl["blank"])
        MakiePlot!(ctrl["ax"],samp,ctrl["blank"],ctrl["par"],ctrl["internal"][1];
                   den=ctrl["den"],transformation=ctrl["transformation"],
                   i=ctrl["i"])
    else
        MakiePlot!(ctrl["ax"],samp;den=ctrl["den"],
                   transformation=ctrl["transformation"],
                   i=ctrl["i"])
    end
end

function GUIgeochronPlotter!(ctrl::AbstractDict,samp::Sample)
    if isnothing(ctrl["blank"]) | (samp.group=="sample")
        MakiePlot!(ctrl["ax"],samp,ctrl["channels"];
                   den=ctrl["den"],transformation=ctrl["transformation"],i=ctrl["i"])
    else
        anchors = KJ.getAnchors(ctrl["method"],ctrl["standards"],ctrl["glass"])
        MakiePlot!(ctrl["ax"],samp,ctrl["method"],ctrl["channels"],ctrl["blank"],
                   ctrl["par"],ctrl["standards"],ctrl["glass"];
                   den=ctrl["den"],transformation=ctrl["transformation"],i=ctrl["i"])
    end
end

function GUInext!(ctrl::AbstractDict)
    ctrl["i"] += 1
    if ctrl["i"]>length(ctrl["run"]) ctrl["i"] = 1 end
    return GUIplotter!(ctrl)
end

function GUIprevious!(ctrl::AbstractDict)
    ctrl["i"] -= 1
    if ctrl["i"]<1 ctrl["i"] = length(ctrl["run"]) end
    return GUIplotter!(ctrl)
end

function GUIgoto!(ctrl::AbstractDict,
                  response::AbstractString)
    ctrl["i"] = parse(Int,response)
    if ctrl["i"]>length(ctrl["run"]) ctrl["i"] = 1 end
    if ctrl["i"]<1 ctrl["i"] = length(ctrl["run"]) end
    GUIplotter(ctrl)
    return "x"
end

function GUIratios!(ctrl::AbstractDict,
                    response::AbstractString)
    if response=="n"
        ctrl["den"] = nothing
    elseif response=="x"
        return "xx"
    else
        i = parse(Int,response)
        if isa(ctrl["channels"],AbstractVector)
            channels = ctrl["channels"]
        elseif isa(ctrl["channels"],AbstractDict)
            channels = collect(values(ctrl["channels"]))
        else
            channels = getChannels(ctrl["run"])
        end
        ctrl["den"] = channels[i]
    end
    GUIplotter!(ctrl)
    return "x"
end

function GUIclear!(ctrl::AbstractDict)
    if "legend" in keys(ctrl)
        delete!(ctrl["legend"])
    end
    empty!(ctrl["ax"])
end

function adjustable_rectangle(w)
end

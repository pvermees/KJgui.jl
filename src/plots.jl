function GUIviewer!(ctrl::AbstractDict)
    GUIinitPlotter!(ctrl)
    return "view"
end

function GUIinitPlotter!(ctrl::AbstractDict)
    ctrl["fig"] = Figure()
    grid = ctrl["fig"][1,1] = GridLayout()
    prev = Button(ctrl["fig"], label = "<")
    next = Button(ctrl["fig"], label = ">")
    ctrl["ax"] = Axis(ctrl["fig"])
    Makie.deactivate_interaction!(ctrl["ax"], :rectanglezoom)
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
    display(ctrl["fig"])
end
export GUIinitPlotter!

function GUIplotter!(ctrl::AbstractDict)
    GUIempty!(ctrl)
    if ctrl["method"] == "concentrations"
        GUIconcentrationPlotter!(ctrl)
    else
        GUIgeochronPlotter!(ctrl)
    end
    ctrl["legend"] = axislegend(ctrl["ax"];position=:lt)
    if !isnothing(ctrl["PAcutoff"])
        GUIaddPAline!(ctrl["PAcutoff"])
    end
end

function GUIconcentrationPlotter!(ctrl::AbstractDict)
    samp = ctrl["run"][ctrl["i"]]
    if (samp.group in keys(ctrl["glass"])) & !isnothing(ctrl["blank"])
        MakiePlot!(ctrl,ctrl["blank"],ctrl["par"],ctrl["internal"][1];
                   den=ctrl["den"],transformation=ctrl["transformation"],
                   i=ctrl["i"])
    else
        MakiePlot!(ctrl;den=ctrl["den"],
                   transformation=ctrl["transformation"],
                   i=ctrl["i"])
    end
end

function GUIgeochronPlotter!(ctrl::AbstractDict)
    samp = ctrl["run"][ctrl["i"]]
    if isnothing(ctrl["blank"])
        MakiePlot!(ctrl,ctrl["channels"];
                   den=ctrl["den"],
                   transformation=ctrl["transformation"],
                   i=ctrl["i"])
    else
        anchors = KJ.getAnchors(ctrl["method"],ctrl["standards"],ctrl["glass"])
        MakiePlot!(ctrl,ctrl["method"],ctrl["channels"],ctrl["blank"],
                   ctrl["par"],ctrl["standards"],ctrl["glass"];
                   den=ctrl["den"],
                   transformation=ctrl["transformation"],
                   i=ctrl["i"])
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
    GUIinitPlotter!(ctrl)
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

function GUIoneAutoWindow!(ctrl::AbstractDict)
    setBwin!(ctrl["run"][ctrl["i"]])
    setSwin!(ctrl["run"][ctrl["i"]])
    return GUIplotter!(ctrl)
end

function GUIallAutoWindow!(ctrl::AbstractDict)
    setBwin!(ctrl["run"])
    setSwin!(ctrl["run"])
    return GUIplotter!(ctrl)
end

function GUItransformation!(ctrl::AbstractDict,
                            response::AbstractString)
    if response=="L"
        ctrl["transformation"] = "Log"
    elseif response=="s"
        ctrl["transformation"] = "sqrt"
    else
        ctrl["transformation"] = nothing
    end
    GUIplotter!(ctrl)
    return "x"
end

function GUIempty!(ctrl::AbstractDict)
    if "legend" in keys(ctrl)
        delete!(ctrl["legend"])
    end
    empty!(ctrl["ax"])
end

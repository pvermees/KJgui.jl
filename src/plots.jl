function GUIviewer!(ctrl::AbstractDict)
    GUIinitPlotter!(ctrl)
    return "view"
end

function GUIinitPlotter!(ctrl::AbstractDict)
    ctrl["fig"] = Figure()
    ctrl["fig"][1,1] = grid = GridLayout()
    prev = Button(grid[1:2,1], label = "<")
    on(prev.clicks) do _
        GUIprevious!(ctrl)
    end
    ctrl["ax"] = Axis(grid[1:2,2])
    Makie.deactivate_interaction!(ctrl["ax"], :rectanglezoom)
    next = Button(grid[1:2,3], label = ">")
    on(next.clicks) do _
        GUInext!(ctrl)
    end
    GUIplotter!(ctrl)
    display(ctrl["fig"])
end
export GUIinitPlotter!

function GUIplotter!(ctrl::AbstractDict)
    GUIempty!(ctrl)
    if ctrl["method"].name == "concentrations"
        GUIconcentrationPlotter!(ctrl)
    else
        GUIgeochronPlotter!(ctrl)
    end
    ctrl["legend"] = axislegend(ctrl["ax"];position=:lt)
    if !isnothing(ctrl["method"].PAcutoff)
        GUIaddPAline!(ctrl["method"].PAcutoff)
    end
end

function GUIconcentrationPlotter!(ctrl::AbstractDict)
    samp = ctrl["run"][ctrl["i"]]
    if isnothing(ctrl["fit"])
        channels = getChannels(samp)
        MakiePlot!(ctrl,
                   channels;
                   den=ctrl["den"],
                   transformation=ctrl["transformation"],
                   i=ctrl["i"])
    else
        MakiePlot!(ctrl,
                   ctrl["fit"].blank,
                   ctrl["fit"].par,
                   ctrl["method"].internal[1];
                   den=ctrl["den"],transformation=ctrl["transformation"],
                   i=ctrl["i"])
    end
end

function GUIgeochronPlotter!(ctrl::AbstractDict)
    return nothing
    channels = getChannels(ctrl["fit"].method)
    if isnothing(ctrl["fit"])
        MakiePlot!(ctrl,
                   channels,
                   den=ctrl["den"],
                   transformation=ctrl["transformation"],
                   i=ctrl["i"])
    else
        standards = collect(keys(ctrl["standards"]))
        glass = collect(keys(ctrl["glass"]))
        MakiePlot!(ctrl,
                   ctrl["method"],
                   channels,
                   ctrl["fit"].blank,
                   ctrl["fit"].par,
                   standards,
                   glass;
                   transformation=ctrl["transformation"],
                   i=ctrl["i"])
    end
end

function GUInext!(ctrl::AbstractDict)
    ctrl["i"] += 1
    if ctrl["i"]>length(ctrl["run"]) ctrl["i"] = 1 end
    GUIplotter!(ctrl)
end

function GUIprevious!(ctrl::AbstractDict)
    ctrl["i"] -= 1
    if ctrl["i"]<1 ctrl["i"] = length(ctrl["run"]) end
    GUIplotter!(ctrl)
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
    GUIplotter!(ctrl)
end

function GUIallAutoWindow!(ctrl::AbstractDict)
    setBwin!(ctrl["run"])
    setSwin!(ctrl["run"])
    GUIplotter!(ctrl)
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
    if "ax" in keys(ctrl)
        empty!(ctrl["ax"])
    end
end

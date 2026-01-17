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
    MakiePlot!(ctrl)
    ctrl["legend"] = axislegend(ctrl["ax"];position=:lt)
    if !isnothing(ctrl["method"].PAcutoff)
        GUIaddPAline!(ctrl["method"].PAcutoff)
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
        ctrl["den"] = ""
    elseif response=="x"
        return "xx"
    else
        i = parse(Int,response)
        if isnothing(ctrl["method"])
            channels = getChannels(ctrl["run"])
        else
            channels = getChannels(ctrl["method"])
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
        ctrl["transformation"] = ""
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

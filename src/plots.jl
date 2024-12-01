function MakiePlot()
    fig = Figure()
    ax = Axis(fig[1, 1])
    fig[2, 1] = buttongrid = GridLayout(tellwidth = false)
    counts = Observable([1, 4, 3, 7, 2])
    buttonlabels = [lift(x -> "Count: $(x[i])", counts) for i in 1:5]
    buttons = buttongrid[1, 1:5] = [Button(fig, label = l) for l in buttonlabels]
    for i in 1:5
        on(buttons[i].clicks) do n
            counts[][i] += 1
            notify(counts)
        end
    end
    barplot!(counts, color = cgrad(:Spectral)[LinRange(0, 1, 5)])
    ylims!(ax, 0, 20)
    return fig
end
export MakiePlot

function GUIviewer!(ctrl::AbstractDict)
    GUIplotter(ctrl)
    return "view"
end

function GUIplotter(ctrl::AbstractDict)
    fig = MakiePlot()
    display(fig)
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

# Cleaning the data in the power folder

using XLSX, DataFrames, CSV, Plots, Unitful, RollingFunctions, Dierckx

tts = 6u"inch/minute"

files = readdir("./power_data/")

frames = []
labels = []
split_frames = []
split_labels = []
for file in files
    path = "./power_data/"*file
    if file[end-2:end] == "lsx" && file[1]!="~"
        try 
        push!(frames, DataFrame(XLSX.readtable(path, 1, header = false, first_row = 2)))
        push!(labels, file[1:end-5])
    catch error
    end
    end
end

function average(x)
    sum(x)/length(x)
end

function smooth(data, x)
    rollmean(rollmean(rollmean(data, x), x), x)
end

function thing(vec)
for i in vec
    if i !=0
        return 1
    else
        return 0
    end
end
end


data = []
cutscuts = []
xdats = []
ydats = []
xsmooths = []
ysmooths = []
diffs = []
is0s = []
ends = []
starts =[]
for j in 1:length(labels)
    frame = frames[j]
    label = labels[j]

    xdata = convert(Vector{Float64}, frame[:, 1])
    xdata = (xdata .- xdata[1])/10^10
    ydata = convert(Vector{Float64}, frame[:, 2])
    ysmooth = smooth(ydata, 30)
    xsmooth = xdata[1:length(ysmooth)]
    spline = Spline1D(xsmooth, ysmooth)
    diff = Dierckx.derivative(spline, xsmooth)

    cuts = []
    for i in 1:(length(diff)-2)
        if i>2 && diff[i] ≈ 0 && diff[i-2] != 0 && xdata[i] > 2
            push!(cuts, i)
        end
    end
    try
        push!(cutscuts, cuts[1])
    catch 
        push!(cutscuts, 0)
    end

    try
    for i in 1:length(xdata)
        if diff[i] > 1000
            push!(starts, i)
            break
        end
    end
        catch
            push!(starts, 0)
    end

    # try
    for b in length(xsmooth):-1:3
        if ydata[b]>10
            push!(ends, b)
            break
        end
    end
        # catch err
            # println(err)
        # push!(ends, 0)
    # end

    push!(diffs, diff)
    push!(xdats, xdata)
    push!(ydats, ydata)
    push!(xsmooths, xsmooth)
    push!(ysmooths, ysmooth)
    push!(is0s, thing(diff))
end

println.(cutscuts)


# for i in 1:length(split_frames)
    # item = split_frames[i]
    # label = split_labels[i]
    # reg = plot(item.Time, [item.Current, item.Voltage], label = ["Current" "Voltage"], title = label)
    


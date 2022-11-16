# Script for cleaning up the thermocouple files and creating the heatmaps 

using DataFrames, CSV, Plots, PrettyTables, Unitful 

frames = []
files = readdir("./thermo_data/")
for file in files 
    path = "./thermo_data/"*file

    # read in the thermocouple data from the csv into a dataframe
    rd = CSV.read(path, DataFrame, header = true)
    rednames = names(rd)

    # try to select the 5th, 6th, and 12th column of the data 
    try
        global df = rd[:, [5, 6, 12]]
    catch err 
    # if there is no column 12, select 3, 4, 8, as this is the format of the alternate file
        global df = rd[:, [3, 4, 8]]
    end

    # create a name based on the file type
    if contains(file, "slash")
        nm = "Plate"*file[1:2]
    else 
        nm = file[1:7]
    end 

    dfnames = names(df)

    # change the names of the columns for consistency
    select!(df, dfnames[1] => "seconds", dfnames[2] => "nanosecs",
            dfnames[3]=> (x -> collect.(eval.(Meta.parse.(x)))) =>"temps")
    
    push!(frames, df)

    # this turns the temperature arrays into a massive matrix where the rows are times and
    # columns are individual thermocouples 
    global tmat = reduce(hcat, df.temps)'
    tmax = maximum(tmat)


    global updated = select(df, :seconds, :nanosecs);

    for i in eachindex(df.temps[1])
        eval(Meta.parse("updated[:, :T$i] = tmat[:, $i]"))
    end

    CSV.write("./thermo_cleaned_data/$(nm)_thermotemps.csv", updated)
        
    # function that takes the vector and reshapes it into the 4x4 array
    function to_heat(x::Vector{<:Real})
        hcat(x[[3, 7 , 11, 15]], x[[2, 6, 10, 14]], x[[1, 5, 9, 13]])'
    end

    transform!(df, "temps" => (x -> to_heat.(x)) => "heatmap")

    anim = @animate for i in eachindex(df.temps) 
        time = round(typeof(1u"s"), (df.seconds[i] - df.seconds[1])u"s"
                    + (df.nanosecs[i] - df.nanosecs[1])u"ns"|> u"s")
        heatmap(df.heatmap[i], clims = (25, tmax+10), title = "$nm Thermocouple Heatmap",
                xlabel = "Time: $(time)", yticks = collect(1:4), dpi = 200)
end

mp4(anim, "./thermo_vids/hm_$nm.mp4");
end

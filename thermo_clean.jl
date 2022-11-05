# Script for cleaning up the thermocouple files and creating the heatmaps 

using DataFrames, CSV, Plots, PrettyTables, Unitful 

files = readdir("./thermo_data/")
for file in files 
path = "./thermo_data/"*file

red = CSV.read(paths[3], DataFrame, header = true)
rednames = names(red)

try
    global df = red[:, [5, 6, 12]]
catch err 
    global df = red[:, [3, 4, 8]]
end

if contains(file, "slash")
    nm = "Plate"*file[1:2]
else 
    nm = file[1:7]
end 

dfnames = names(df)

select!(df, dfnames[1] => "seconds", dfnames[2] => "nanosecs",
        dfnames[3]=> (x -> collect.(eval.(Meta.parse.(x)))) =>"temps")

tmat = reduce(hcat, df.temps)'
tmax = maximum(tmat)


global updated = select(df, :seconds, :nanosecs);

for i in 1:length(df.temps[1])
     eval(Meta.parse("updated[:, :T$i] = tmat[:, $i]"))
end

CSV.write("./thermo_cleaned_data/$(nm)_thermotemps.csv", updated)
    
function to_heat(x::Vector{Float64})
    hcat([x[(1 + 4i):(4+4i)] for i in 0:3]...)'
end

transform!(df, "temps" => (x -> to_heat.(x)) => "heatmap")

anim = @animate for i in 1:length(df.temps) 
    time = round(typeof(1u"s"), (df.seconds[i] - df.seconds[1])u"s"
                 + (df.nanosecs[i] - df.nanosecs[1])u"ns"|> u"s")
    heatmap(df.heatmap[i], clims = (25, tmax+10), title = "$nm Thermocouple Heatmap",
            xlabel = "Time: $(time)" )
end

mp4(anim, "./thermo_vids/hm_$nm.mp4");
end

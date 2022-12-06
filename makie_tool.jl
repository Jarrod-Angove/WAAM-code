using CSV, DataFrames, Dates, Unitful, LsqFit, GLMakie, Makie, PrettyTables, Printf, Gtk

data_folder = open_dialog("Please select your data path", action=GtkFileChooserAction.SELECT_FOLDER)
files = 

# Parsing it into actual numbers and passing it to a new temp csv file
function pyro_clean(file_path)
    open(file_path) do file
        # Creating a temp file to hold the line-by-line data  
        line_by_line = readlines(file)
        rm("temp_out.txt", force=true) 
        outfile = open("temp_out.txt", "w")
        
        # Writing each line to the temp file
        # Have to do this to work with the CSV import package
        for line in line_by_line[14:end-2]
            println(outfile, line)
        end
        close(outfile)
    end

    # Using the CSV package to parse it into a dataframe 
    infile = open("temp_out.txt")
    df_raw = CSV.read(infile, header=1, delim='\t', DataFrame)
    rm("temp_out.txt", force=true) 

    # Defining some functions for later
    function timeunit(time)
        # Takes a Dates.Time type and converts it to a Unitful time in seconds
        # This is much easier to work with
        Minute(time) + Second(time) + Millisecond(time) |> u"s"
    end

    function to_time(string)
        timeunit(
        Time(
            map(
                x->parse(Int,x),
                (string[1:2], string[4:5], string[7:8], string[10:12], string[13]*"00"))...)
            ) |> float
    end

    function to_float(string::AbstractString)
        # Takes the weird number strings and turns them into floats, fixing the comma in the process
        parse(Float64, replace(string, ","=>"."))
    end

    # Just returns boolean true if it's in the given time range
    # Useful for sorting the dataframe with the units still in place
    function intime(time, a, b)
        b >= time >= a
    end;

    # Making a useable dataframe and applying the above functions to make it computer-legible
    # Note that I am stripping the units off here; time is in seconds, temp is in °C
    return select(df_raw,
                :Time => (x -> ustrip(to_time.(x))) => "Time",
                :TProc => ByRow(to_float) => "Temp"
            )
end



fig = Figure()
files = readdir(data_folder)
fig[3, 1] = buttongrid = GridLayout(tellwidth = false)
menu1 = Menu(buttongrid[1,1], options = files, default = files[8])
df = Observable(pyro_clean(data_folder*"/"*files[8]))
y = Observable(df[].Temp)
x = Observable(df[].Time)

on(menu1.selection) do s
    df[] = pyro_clean(data_folder*"/"*s)
    y.val = df[].Temp
    x.val = df[].Time
    eval(:(sl.range = 0:lastindex(x.val)))
    xlims!(ax1, (x[][1], x[][end]))
    ylims!(ax1, (500, max(y[]...)+10))
    notify(y)
    notify(x)
end 

s1 = Observable(1)
s2 = @lift(lastindex($x))
slope = Observable([0.0, 0.0])
CI = Observable([0.0, 0.0])

ax1 = Axis(fig[1,1], xlabel = "Time (s)", ylabel = "Temperature (°C)")
data_plot = lines!(ax1, x, y, label="data")

sp = @lift begin
    m = $slope[1]
    b = $slope[2]
    m.*$x .+ b
end

slope_plot = lines!(ax1, x, sp)


b1 = buttongrid[1, 5] = Button(fig, label = "zoom")
b2 = buttongrid[1, 4] = Button(fig, label = "get slope")
b3 = buttongrid[1, 6] = Button(fig, label = "return")
slabel = buttongrid[1, 3] = Label(fig, "Slope: ")
rng_label = buttongrid[1, 2] = Label(fig, "Index Range: ")
sl = IntervalSlider(fig[2, 1], range = s1[]:s2[], startvalues = (s1[], s2[]))

a = lift(sl.interval) do int
    int[1]
end

b = lift(sl.interval) do int
    int[2]
end

xa = @lift($x[$a])
xb = @lift($x[$b])
ya = @lift($y[$a])
yb = @lift($y[$b])

on(b1.clicks) do n
    xlims!(ax1, (xa[], xb[]))
    ylims!(ax1, (min(ya[], yb[])-1, max(ya[], yb[])))
    eval(:(aa = $(a[]); bb = $(b[])))
    eval(:(sl.range = aa:bb))
end

@. model(t, p) = p[1]*t + p[2]
p0 = [30.0, 50.0]

on(b2.clicks) do n
    fit = curve_fit(model, x[][a[]:b[]], y[][a[]:b[]], p0)
    slope[] = fit.param
    CI[] = margin_error(fit, 0.05)
    slabel.text[] = slabel_text[]
    rng_label.text[] = "Slope Range Index: " * string([sl.interval[][1], sl.interval[][2]])
    notify(slope)
    notify(CI)
    notify(slabel.text)
    notify(rng_label.text)
end

on(b3.clicks) do n
    xlims!(ax1, (x[][1], x[][end]))
    ylims!(ax1, (500, max(y[]...)+10))
    eval(:(sl.range = 0:lastindex(x[])))
end

slabel_text = @lift(Printf.@sprintf("Slope: %5.1f  ±%5.1f", $slope[1], $CI[1]))


vlines!(ax1, xa, color = :blue, label="line1")
vlines!(ax1, xb, color = :blue, label="line2")

dins = DataInspector(ax1)

display(fig)


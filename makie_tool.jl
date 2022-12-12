using CSV, DataFrames, Dates, Unitful, LsqFit, GLMakie, Makie, PrettyTables

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

function selector_tool(df)
    x = (df.Time)
    y = (df.Temp)
    ind = getindex(x)

    fig = Figure()
    ax1 = Axis(fig[1,1])
    data_plot = lines!(ax1, x, y)

    x_end = Observable(lastindex(x))
    x_i = Observable(0)

    fig[3, 1] = buttongrid = GridLayout(tellwidth = false)

    sl = IntervalSlider(fig[2, 1], range = 0:1:lastindex(x), startvalues = (20, 100))

    b1 = buttongrid[1, 1] = Button(fig, label = "cut")
    b2 = buttongrid[1, 2] = Button(fig, label = "push")

    a = lift(sl.interval) do int
        int[1]
    end

    b = lift(sl.interval) do int
        int[2]
    end

    xa = @lift(x[$a])
    xb = @lift(x[$b])

    on(b1.clicks) do n
        xlims!(ax1, (xa[], xb[]))
    end

    vlines!(ax1, xa, color = :blue)
    vlines!(ax1, xb, color = :blue)

    display(fig)
end

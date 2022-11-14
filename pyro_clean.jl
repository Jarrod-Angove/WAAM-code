# This is a julia script to parse pyrometer dat files
# Made by Jarrod Angove in September 2022

# Importing some packages

using CSV, DataFrames, Plots, Dates, Unitful, LsqFit

# Initiating some variables 
all_errors = Vector{Float32}()
all_cooling_rates = Vector{Float32}()
all_names = Vector{AbstractString}()
png_files = Vector{AbstractString}()
png_ref = Vector{AbstractString}()

# Parsing it into actual numbers and passing it to a new temp csv file
function to_plots(file_path)
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

    function sec_diff(x)
        # Take the second derivative of a vector
        ddt = []
        # I assume a constant time step of 0.02s here; this is not technically correct
        # Good enough for simple filter application
        for i in 2:(length(x)-1)
            # Append the derivative at the current index to ddt
            push!(
                ddt,
                (x[i+1]-2*x[i]+x[i-1])/(0.02)^2
                )
        end
        return ddt
    end

    # Just returns boolean true if it's in the given time range
    # Useful for sorting the dataframe with the units still in place
    function intime(time, a, b)
        b >= time >= a
    end;

    # Making a useable dataframe and applying the above functions to make it computer-legible
    # Note that I am stripping the units off here; time is in seconds, temp is in °C
    df = select(df_raw,
                :Time => (x -> ustrip(to_time.(x))) => "Time",
                :TProc => ByRow(to_float) => "Temp"
            )
    # Number of rows in the unaltered data
    osize = size(df)[1]

    # Making a dataframe is easier bc I need to resize time and temp to account for lost rows from diff
    clusters = DataFrame(
                    Time = df[2:osize-1, :Time],
                    Temp = df[2:osize-1, :Temp],
                    Diff = sec_diff(df.Temp)
                    ) 
    # Temp upper and lower bound based on the solidus and liquidus temperatures of 17-4PH SS; diff bound (symmetric for diff)
    temp_ub = 1457
    temp_lb = 1266
    diff_b = 10000

    # This is where the noise from splatter is removed 
    # The diff filter is doing most of the heavy lifting here
    # The diff filter bound diff_b is the hardest part to get right; needs to be tuned
    # The second part, I remove anything with near zero d2T/dt2 to get rid of stragglers
    subset!(clusters,
            :Temp => ByRow(T -> temp_ub > T > temp_lb),
            :Diff => ByRow(dT-> -diff_b < dT < diff_b && (dT>1 || dT<-1))
        )
    # If there is a time gap in clusters greater than 2 seconds, create 2 datasets
    # Else, create only one
    jump = argmax(diff(clusters.Time))
    jsize = clusters[jump+1, :Time] - clusters[jump, :Time]

    # This is the model (simple linear) used by the least squares fit in the loop below
    @. model(x, p) = p[1]*x + p[2]
    p0 = [-200.0, 800.0] # This is the starting guess for the fit

    regions = Vector{Any}()
    Rs = Vector{Float32}()

    # Tests if the time gap is greater than 5 seconds to figure out if there are two beads on the plate or just one
    if jsize>5
        # Seperating them into regions if there are two
        push!(regions,
        subset(df, :Time => x->intime.(x, clusters[1,:Time], clusters[jump, :Time])))
        push!(regions,
        subset(df, :Time => x->intime.(x, clusters[jump+1,:Time], clusters[size(clusters)[1], :Time])))
    else 
        # Using just the one if there is only a single region 
        push!(regions, 
        subset(df, :Time => x->intime.(x, clusters[1,:Time], clusters[size(clusters)[1], :Time])))
    end

    i = 0
    intervals = Vector{Any}()
    cooling_rates = Vector{Any}()
    errors = Vector{Float32}()
    png_file = Vector{AbstractString}()
    # Loop through all of the regions selected above
    for region in regions
        i += 1
        # Time is set to start at 0 for easier model fit and more reasonable graph
        xdata = region[:,:Time].- region[1,:Time]
        ydata = region[:,:Temp]

        # using the lsqfit package to fit the data to the linear model specified above
        fit = LsqFit.curve_fit(model, xdata, ydata, p0);
        # extracting the fitted parameters to varaibles
        (κ, T) = fit.param
        # extracting 95% confidence interval for both the cooling rate and the temperature adjustment
        (interval_κ, interval_T) = confidence_interval(fit, 0.05)
        # extracting the standard error 95%CI
        moe = margin_error(fit, 0.05)[1]
        # Pushing the marginal error into a vector for later use
        push!(intervals, interval_κ) # This is the 95% confidence interval
        push!(all_cooling_rates, κ)   # Pushing the cooling rate into initialized vector
        push!(all_errors, moe)
        name = "$(file_path[13:end-4]) region $i"
        push!(all_names, name)


        # This makes the plots of the individual regions
        scatterplot = scatter(xdata, ydata, label = "Data", title = "Plot of $name")
        plot!(x-> κ*x + T, label="$(round(κ,sigdigits=5)) x + $(round(T, sigdigits=5))")
        xlabel!("Time (s)")
        ylabel!("Temperature (°C)")
        #Saving the plot, creating a name for it based on the original file and it's position in 'regions'
        savefig(scatterplot, "./generated_plots/"*"$(file_path[13:end-4])"*"_plot$i.pdf")
        savefig(scatterplot, "./plots_pngs/"*"$(file_path[13:end-4])"*"_plot$i.png")
        push!(png_files, "./generated_plots/"*"$(file_path[13:end-4])"*"_plot$i.png")
        push!(png_ref, "./plots_pngs/"*"$(file_path[13:end-4])"*"_reference.pdf")

    end

    # This creates the plot that shows the regions over the whole data set (reference plots)
    referenceplot = plot(df.Time, df.Temp, label = "Original data")
    scatter!(clusters.Time, clusters.Temp, label = "Selected regions")
    xlabel!("Time (s)")
    ylabel!("Temperature (°C)")
    savefig(referenceplot, "./generated_plots/"*"$(file_path[13:end-4])"*"_reference.pdf")
    savefig(referenceplot, "./plots_pngs/"*"$(file_path[13:end-4])"*"_reference.png")
end

# Looping through every file in the pyro_data directory an running it through the code above
for file in readdir("./pyro_data/")
    filepath = "./pyro_data/"*file
    try
        to_plots(filepath)
    catch err
        println("The file $file threw an error: ")
        println(err)
    end
end

# Creating a summary table in a dataframe
cooling_summary = DataFrame("Sample Name"=>all_names,
                            "Cooling Rate (°C/s)"=>all_cooling_rates,
                            "95% Margin of Error (±)"=>all_errors, 
                            "Selected Region Plot"=>png_files, 
                            "Region Reference"=>png_ref)

# Writing the dataframe into a CSV file
CSV.write("cooling_summary.csv", cooling_summary)


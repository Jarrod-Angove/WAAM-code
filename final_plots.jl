using CSV, Plots, DataFrames, Unitful, XLSX, LsqFit
const η = 0.85

mean(x) = sum(x)/length(x);

path = "./cooling_summary_expanded.csv"
base_data = DataFrame(CSV.read(path, DataFrame, header=true))

scrubbed = select(dropmissing(base_data, [:name, :id, :powerfile, :range, :ttsms, :hotcold]), "name", "id", "powerfile", "range", "ttsms", "hotcold")

# Function that takes the powerfile name, tts, and range -> power [kJ/m], plot of range
function flip(file, range, tts)
	rng = eval(Meta.parse(range))
	r1 = rng[1] + 10; r2 = rng[2] - 10
	path = "./power_data/"*file
if file[end-2:end] == "lsx" && file[1]!="~"
		data = DataFrame(XLSX.readtable(path, 1, header = false, first_row = 2))
	# Some of the files are formatted differently due to the new python script for bag file conversion; this is a quick but dirty fix
elseif (file[end-2:end] == "csv") && (contains(file, "weld")) && (contains(file, "fronius"))
		data = DataFrame(CSV.read(path, DataFrame; header=false, skipto=2, footerskip = 2))
		try 
		data = data[!, [1, 8, 9]]
		catch err 
			data = data[!, [4, 6, 7]]
		end
elseif (file[end-2:end] == "csv")
	data = DataFrame(CSV.read(path, DataFrame; header=false, skipto=2, footerskip = 2))
	data = data[:, 1:3]
end
	powers = data[:, 2] .* data[:, 3] .* η
	power = (mean(data[r1:r2, 2])u"A" * mean(data[r1:r2,3])u"V" / Quantity(tts, u"m/s")) |> u"J/mm"
	rangeplot = Plots.plot(powers, label = "Data", legend = :bottomright, fontfamily="Times Roman", ylabel="Torch Power (J) = V × I", xlabel ="Time Index");
	plot!(r1:r2, powers[r1:r2], fill = (0, 0.2, :orange),
		  label = "Mean = $(round(mean(powers), sigdigits = 5)) ");
	return [power, rangeplot]
end;

powers = []
plots = []
named = []
captions = []
for row in eachrow(scrubbed)
	(pow, plt) = flip(row.powerfile, row.range, row.ttsms)
	push!(powers, pow)
	push!(plots, plt)
    push!(named, "Plate"*string(row.id)*"_"*row.hotcold)
	if row.hotcold == "c"
		cap = "Power input plot for plate $(row.id) (cold bead). "
	elseif row.hotcold == "h"
		cap = "Power input plot for plate $(row.id) (hot bead). "
	end
	push!(captions, cap)
end

texstring = ""
for i in 1:lastindex(plots)
	savefig(plots[i], "./final_plots/power_selection/"*named[i]*".pdf")
	global texstring *= 
"

\\begin{figure}[htp]
   \\centering
   \\includegraphics[width=0.7\\textwidth]{Figures/power_selection/$(named[i]).pdf}
   \\caption{$(captions[i])}
\\end{figure}
"
end

touch("./final_plots/power_figs.tex")
my_file = open("./final_plots/power_figs.tex", "w")
write(my_file, texstring)
close(my_file)

scrubbed.powers = powers

summary_data = leftjoin(base_data, select(scrubbed, :name, :powers), on = :name)

plot_data = dropmissing(summary_data[!, [:name, :id, :hotcold, :c_ratecs, :error95, :powers]])

# Dropping plates 6 and 7 as these had experimental errors
plot_data = plot_data[(plot_data.id .!= 6) .& (plot_data.id .!= 7), :]

hotplate = plot_data[(plot_data.hotcold .== "h"), :]
coldplate = plot_data[(plot_data.hotcold .== "c"), :]

# Including model data from Anqi
model_cr = [129.9987, 137.9946, 170.3942, 97.78071, 81.20779, 92.12833, 86.03073, 118.9481]
# Model powers from the plates corresponding to the model
model_power = [482.196727682091,
 616.297536437391,
 677.6194703710901,
 649.5880621007259,
 659.7991578482029,
 658.7953615727218,
 640.1630349988593,
 878.869965178166]


@. model(x, p) = p[1]/(x - p[2])
xdata = ustrip.(plot_data.powers)
ydata = abs.(plot_data.c_ratecs)
p0 = [90000.0, 100]
wt = abs.(1 ./(plot_data.error95.^2))
fit = curve_fit(model, xdata, ydata, wt, p0)
CI = margin_error(fit, 0.05)

x = range(200, 1100, length=1000)
y = model(x, fit.param)
y_upper = model(x, fit.param .+ CI)
y_lower = model(x, fit.param .- CI)

fit_cold = curve_fit(model, ustrip.(coldplate.powers), abs.(coldplate.c_ratecs), p0)
fit_hot = curve_fit(model, ustrip.(hotplate.powers), abs.(hotplate.c_ratecs), p0)
CI_cold = margin_error(fit_cold, 0.05)
CI_hot= margin_error(fit_hot, 0.05)

y_cold = model(x, fit_cold.param)
y_cold_upper = model(x, fit_cold.param .+ CI_cold)
y_cold_lower = model(x, fit_cold.param .- CI_cold)

y_hot = model(x, fit_hot.param)
y_hot_upper = model(x, fit_hot.param .+ CI_hot)
y_hot_lower = model(x, fit_hot.param .- CI_hot)

# This section generates the plot objects; see here for formatting changes
# The main plot that shows the cooling rate vs heat input
# This is the model fit of the data
base_plot = plot(x, [y_upper, y_lower]; fillrange =y_lower, label = ["95% CI " ""], color = :LightSeaGreen, alpha=0.5)
plot!(x, y, color=:black, label="Model")
# This is the actual data for the cold plate beads; coloured blue
scatter!(ustrip.(coldplate.powers), abs.(coldplate.c_ratecs), yerror = coldplate.error95, 
		fontfamily="Times Roman", label="Cold Plate", xlabel="Heat Input (J/mm)",
		ylabel="Cooling Rate °C/s", color=:DodgerBlue)
# This is the actual data for the hot plate cooling rates
scatter!(ustrip.(hotplate.powers), abs.(hotplate.c_ratecs), yerror = hotplate.error95, label="Hot Plate", color=:DarkOrange)

# This compares the model fits of the hot and cold plates individually
hot_v_cold = plot(x, [y_cold_upper, y_cold_lower]; fillrange=y_cold_lower, fontfamily="Times Roman",
				  xlabel="Heat Input (J/mm)", ylabel="Cooling Rate °C/s",
				  color = [:DodgerBlue :DodgerBlue], alpha=0.2, label="", ls=:dot)
plot!(x, [y_hot_upper, y_hot_lower]; fillrange=y_hot_lower, fontfamily="Times Roman",
	  xlabel="Heat Input (J/mm)", ylabel="Cooling Rate °C/s", color = [:DarkOrange :DarkOrange],
	  alpha = 0.2, label = "", ls =:dot)
plot!(x, [y_cold, y_hot], color=[:DodgerBlue :DarkOrange], label = ["Cold Plate Fit  " "Hot Plate Fit"])


savefig(base_plot, "./final_plots/results_overview_plot.pdf")
savefig(hot_v_cold, "./final_plots/hot_v_cold_plot.pdf")

# This tests if a number is in a set (couldn't get the built in function to work)
# Credit to GPT-3 :)
function is_in_set(input, set)
   result = Bool[]
   for x in input
	   push!(result, x in set)
   end
   return result
end

# These are the plate numbers that Anqi's model is tested on
myset = [4, 11, 12, 15, 17, 18, 19, 21]
model_comp_df = plot_data[is_in_set(plot_data.id, myset) .&& 
						  (plot_data.hotcold .== "h" .||
						   (plot_data.id .== 17)), :]
deleteat!(model_comp_df, 5)

compare_model = scatter(ustrip.(model_comp_df.powers),abs.(model_comp_df.c_ratecs), yerror = model_comp_df.error95, label="Emperical Data  ", color=:DarkOrange, fontfamily="Times Roman",
						xlabel="Heat Input (J/mm)", ylabel="Cooling Rate °C/s")
scatter!(model_power, model_cr, color=:Purple, markershape=:star5, label="Heat Flow Model Results  ")

savefig(compare_model, "./final_plots/model_anqi_comp.pdf")

fits = [fit, fit_cold, fit_hot]
fitnames = ["Combined", "Cold Plate", "Hot Plate"]
strings = []
using Printf
for i in 1:lastindex(fits)
	δ = margin_error(fits[i], 0.05)
	p1str = @sprintf("%5.1f ± %5.1f",fits[i].param[1]/1000, δ[1]/1000)
	p2str = @sprintf("%5.2f ± %5.1f",fits[i].param[2], δ[2])
	str1 = fitnames[i] * " p₁ = "*p1str
	str2 = fitnames[i] * " p₂ = "*p2str
	strs = [str1, str2]
	push!(strings, strs)
end

rel_err(emp, mod) = abs.((emp - mod)/emp) * 100

# Error of the model compared to the experimental data
exp_err = rel_err.(abs.(model_comp_df.c_ratecs), abs.(model_cr))

model_comp_df.rel_err = exp_err

corrected_df = model_comp_df[model_comp_df.id .!=4 .&& model_comp_df.id .!=19 , :]

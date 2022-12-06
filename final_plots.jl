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
names = []
for row in eachrow(scrubbed)
	(pow, plt) = flip(row.powerfile, row.range, row.ttsms)
	push!(powers, pow)
	push!(plots, plt)
    push!(names, "Plate"*string(row.id)*"_"*row.hotcold)
end

for i in 1:lastindex(plots)
	savefig(plots[i], "../final/Figures/power_selection/"*names[i]*".pdf")
end

scrubbed.powers = powers

summary_data = leftjoin(base_data, select(scrubbed, :name, :powers), on = :name)

plot_data = dropmissing(summary_data[!, [:name, :id, :hotcold, :c_ratecs, :error95, :powers]])

# Dropping plates 6 and 7 as these had experimental errors
plot_data = plot_data[(plot_data.id .!= 6) .& (plot_data.id .!= 7), :]

hotplate = plot_data[(plot_data.hotcold .== "h"), :]
coldplate = plot_data[(plot_data.hotcold .== "c"), :]

@. model(x, p) = p[1]/(x - p[2])
xdata = ustrip.(plot_data.powers)
ydata = abs.(plot_data.c_ratecs)
p0 = [90000.0, 100]
wt = abs.(1 ./(plot_data.error95.^2))
fit = curve_fit(model, xdata, ydata, wt, p0)
CI = standard_errors(fit)

x = range(200, 1100, length=1000)
y = model(x, fit.param)
y_upper = model(x, fit.param .+ CI)
y_lower = model(x, fit.param .- CI)

fit_cold = curve_fit(model, ustrip.(coldplate.powers), abs.(coldplate.c_ratecs), p0)
fit_hot = curve_fit(model, ustrip.(hotplate.powers), abs.(hotplate.c_ratecs), p0)
CI_cold = standard_errors(fit_cold)
CI_hot= standard_errors(fit_hot)

y_cold = model(x, fit_cold.param)
y_cold_upper = model(x, fit_cold.param .+ CI_cold)
y_cold_lower = model(x, fit_cold.param .- CI_cold)

y_hot = model(x, fit_hot.param)
y_hot_upper = model(x, fit_hot.param .+ CI_hot)
y_hot_lower = model(x, fit_hot.param .- CI_hot)

base_plot = plot(x, [y_upper, y_lower]; fillrange =y_lower, label = ["Standard Error  " ""], color = :LightSeaGreen, alpha=0.5)
plot!(x, y, color=:black, label="")
scatter!(ustrip.(coldplate.powers), abs.(coldplate.c_ratecs), yerror = coldplate.error95, 
		fontfamily="Times Roman", label="Cold Plate", xlabel="Heat Input (J/mm)",
		ylabel="Cooling Rate °C/s", color=:DodgerBlue)
scatter!(ustrip.(hotplate.powers), abs.(hotplate.c_ratecs), yerror = hotplate.error95, label="Hot Plate", color=:DarkOrange)

hot_v_cold = plot(x, [y_cold_upper, y_cold_lower]; fillrange=y_cold_lower, fontfamily="Times Roman",
				  xlabel="Heat Input (J/mm)", ylabel="Cooling Rate °C/s",
				  color = [:DodgerBlue :DodgerBlue], alpha=0.2, label="", ls=:dot)
plot!(x, [y_hot_upper, y_hot_lower]; fillrange=y_hot_lower, fontfamily="Times Roman",
	  xlabel="Heat Input (J/mm)", ylabel="Cooling Rate °C/s", color = [:DarkOrange :DarkOrange],
	  alpha = 0.2, label = "", ls =:dot)
plot!(x, [y_cold, y_hot], color=[:DodgerBlue :DarkOrange], label = ["Cold Plate Fit  " "Hot Plate Fit"])

savefig(base_plot, "../final/Figures/results_overview_plot.pdf")
savefig(hot_v_cold, "../final/Figures/hot_v_cold_plot.pdf")


### A Pluto.jl notebook ###
# v0.19.9

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
end

# ╔═╡ f7a28e7a-540f-11ed-3d35-03d9d4bafcd6
using PlutoUI, DataFrames, XLSX, CSV, PlotlyJS, Plots, Unitful, Dates, TimesDates

# ╔═╡ b205b383-3b93-4165-b98d-61b89131e34a
files = readdir("./power_data/")

# ╔═╡ f516201b-992c-49a3-b306-3f726f2f9744
mean(x) = sum(x)/length(x);

# ╔═╡ 5da2de9e-c0ce-4d19-9476-cd5b2527fd75
begin
frames = []
labels = []
split_frames = []
split_labels = []
df = DateFormat("yyy/mm/dd:hh:mm:ss")
for file in files
    path = "./power_data/"*file
    if ((file[end-2:end] == "lsx") && ! contains(file, "~") && !contains(file, "Joint") && !contains(file, "joint"))
			data = DataFrame(XLSX.readtable(path, 1, header = false, first_row = 2))
			label = file[1:end-5]
			data = data[!,1:3]
			metadata!(data, "label", label, style = :note)
        	push!(frames, data)
        	push!(labels, label)
	elseif ((file[end-2:end] == "csv") && (contains(file, "weld")) && (contains(file, "fronius")) && !contains(file, "joint") && !contains(file, "Joint"))
		data = DataFrame(CSV.read(path, DataFrame; header=true, footerskip = 2))
		label = file[1:end-4]
		try 
		data = data[!, [1, 8, 9]]
		catch err 
			data = data[!, [4, 6, 7]]
		end
		metadata!(data, "label", label, style = :note)
		push!(frames, data)
		push!(labels, label)
	elseif (file[end-2:end] == "csv") && !contains(file, "fronius") && !contains(file, "joint") && !contains(file, "Joint")
		data = DataFrame(CSV.read(path, DataFrame; header=false, skipto=2, footerskip = 2))
		data = data[!, 1:3]
		label = file[1:end-4]
		metadata!(data, "label", label, style = :note)
		push!(frames, data)
		push!(labels, label)
    end
end
end

# ╔═╡ 3c8111bc-c736-4062-90cc-9f3a4edecf56
# This creates a vector of key-value pairs from the imported data for the drop down selector to work properly
begin
s0 = "sense = [";
strings = []
sense = Nothing
for i in 1:length(labels)
	si = "frames[$i] => labels[$i], "
	push!(strings, si)
end
	fin = s0*string(strings...)[1:end-2]*"];"
	eval(Meta.parse(fin).args[1])
end;

# ╔═╡ d9ae5e69-717e-4149-896c-8f450381f130
labels[25]

# ╔═╡ e10fbb3d-9bee-4416-ab64-80642d964d1d
@bind frame Select(sense)

# ╔═╡ ec5e8fa2-f192-4f64-9443-80bc0df92c97
begin
	xdata = convert(Vector{Float64}, frame[:, 1])
    xdata = (xdata .- xdata[1])/10^10
    ydata = convert(Vector{Float64}, frame[:, 2].*frame[:, 3])
end;

# ╔═╡ c219b525-3af1-42d5-a8b0-350f5f5ac7e8
md"""
Select the regions:
"""

# ╔═╡ 74387142-7d2a-4a6b-921e-1d80c212b7b8
@bind a Slider(1:1:length(xdata), default = 100)

# ╔═╡ e6143f95-7270-4537-8433-feaf913b8940
@bind b Slider(1:length(xdata), default = 150)

# ╔═╡ 25364a7e-0372-4fa2-aee5-31551ee0fe7f
@bind c Slider(1:length(xdata), default = 200)

# ╔═╡ c5ab90ca-e04a-4154-85be-1d22beaadbe8
@bind d Slider(1:length(xdata), default = 250)

# ╔═╡ cd922f3d-7363-465b-b922-7838ea77859e
begin
lines = [a, b, c, d];
println("range1: $(lines[1:2])")
println("range1: $(lines[3:4])")

end

# ╔═╡ f74fd7a0-75bb-4d17-86f9-750681cfec84
begin
	range1 = a:b; range2 = c:d
	data = DataFrame(Time = xdata, Power = ydata)
	df1 = DataFrame(Time = xdata[range1], Power = ydata[range1])
	df2 = DataFrame(Time = xdata[range2], Power = ydata[range2])
	meand1 = mean(df1[:,2])
	meand2 = mean(df2[:,2])
	plotlyjs()
	rangeplot = Plots.plot(data[:, 2], label = "Power Data", legend = :bottomright)
	vline!([a, b, c, d], label="", color=:black)
	plot!((1:length(df1[:, 2])) .+ a, df1[:, 2], fill =(0, 0.1, :red), 
	label = "mean 1: $meand1")
	plot!((1:length(df2[:, 2])) .+ c, df2[:, 2], fill = (0, 0.1, :green), 
	label = "mean 2: $meand2")
end

# ╔═╡ 28089ccf-d267-4b9e-a1c7-2c027d393bdd
expanddf = DataFrame(CSV.read("./cooling_summary_expanded.csv", DataFrame, header = true))

# ╔═╡ 725b0819-937f-4298-9aa5-01ee11c5522f
scrubbed = select(dropmissing(expanddf), "name", "powerfile", "range", "ttsms")

# ╔═╡ 4cd77441-cfd6-467f-91ca-7534143941f3
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
	powers = data[:, 2] .* data[:, 3]
	power = (mean(data[r1:r2, 2])u"A" * mean(data[r1:r2,3])u"V" / Quantity(tts, u"m/s")) |> u"J/mm"
	rangeplot = Plots.plot(powers, label = "Data", legend = :bottomright);
	plot!(r1:r2, powers[r1:r2], fill = (0, 0.2, :orange), label = "mean = $(mean(powers))");

	return [power, rangeplot]
end;

# ╔═╡ b73468ce-182d-41a8-a529-290f584caa36
flip(scrubbed[2, :powerfile], scrubbed[2, :range], scrubbed[2, :ttsms]);

# ╔═╡ bb5e1ce8-c19b-417d-b933-ccb69be142f8
begin
powers = []
plots = []
for row in eachrow(scrubbed)
	(pow, plt) = flip(row.powerfile, row.range, row.ttsms)
	push!(powers, pow)
	push!(plots, plt)
end
	scrubbed.powers = powers
	scrubbed.selection = plots
end;

# ╔═╡ e4cc6c38-d120-4cd1-b5af-bae21f3aaa85
scrubbed.powers

# ╔═╡ 34d5635a-8e25-4f6b-9dd9-adb8831dcc0a
combinedf = leftjoin(expanddf, select(scrubbed, :name, :powers, :selection), on = :name);

# ╔═╡ ae2ac5a7-b502-4951-9ee0-f1e08e2e1597
begin
transform!(combinedf, :c_ratecs => (x -> abs.(x)) => :c_ratecs, :powers => (x->ustrip.(u"J/mm",x)) => :powers)
end;

# ╔═╡ d085f917-a8eb-4d1b-a2c1-73316203bc54
known_points = dropmissing(combinedf);

# ╔═╡ 34a7aa4b-2d40-4a66-be79-fed470cd6185
begin
using JSON, WebIO
myplt = PlotlyJS.plot(known_points, x = :powers, y = :c_ratecs, mode = "markers", error_y=attr(type="data", array=:error95, visible = true), marker=attr(size=12, line=attr(width=2, color="DarkSlateGrey")), text = :name,
	Layout(
    title="Heat input vs cooling rate",
    xaxis_title="Heat input (J/mm)",
    yaxis_title="Cooling rate (K/s)"))
end
#, text = :name

# ╔═╡ f1e49314-717c-4d7c-9140-8f4d56f61165
known_points.error95

# ╔═╡ d038cab7-22e0-4595-9bd6-ed2e7ff5f247
begin
PlotlyJS.savefig(myplt, "myplt.html")
PlotlyJS.savefig(myplt, "myplt.pdf")
end

# ╔═╡ 6cb06dbf-5239-44f2-8ac4-d1e776237167
html"""
<style>
input[type*="range"] {
	width: 100%;
}
</style>
"""

# ╔═╡ Cell order:
# ╠═f7a28e7a-540f-11ed-3d35-03d9d4bafcd6
# ╟─b205b383-3b93-4165-b98d-61b89131e34a
# ╠═f516201b-992c-49a3-b306-3f726f2f9744
# ╠═5da2de9e-c0ce-4d19-9476-cd5b2527fd75
# ╠═3c8111bc-c736-4062-90cc-9f3a4edecf56
# ╠═d9ae5e69-717e-4149-896c-8f450381f130
# ╟─e10fbb3d-9bee-4416-ab64-80642d964d1d
# ╟─ec5e8fa2-f192-4f64-9443-80bc0df92c97
# ╟─c219b525-3af1-42d5-a8b0-350f5f5ac7e8
# ╟─74387142-7d2a-4a6b-921e-1d80c212b7b8
# ╟─e6143f95-7270-4537-8433-feaf913b8940
# ╟─25364a7e-0372-4fa2-aee5-31551ee0fe7f
# ╟─c5ab90ca-e04a-4154-85be-1d22beaadbe8
# ╟─cd922f3d-7363-465b-b922-7838ea77859e
# ╟─f74fd7a0-75bb-4d17-86f9-750681cfec84
# ╠═28089ccf-d267-4b9e-a1c7-2c027d393bdd
# ╠═725b0819-937f-4298-9aa5-01ee11c5522f
# ╠═4cd77441-cfd6-467f-91ca-7534143941f3
# ╠═b73468ce-182d-41a8-a529-290f584caa36
# ╠═bb5e1ce8-c19b-417d-b933-ccb69be142f8
# ╠═e4cc6c38-d120-4cd1-b5af-bae21f3aaa85
# ╠═34d5635a-8e25-4f6b-9dd9-adb8831dcc0a
# ╠═ae2ac5a7-b502-4951-9ee0-f1e08e2e1597
# ╠═d085f917-a8eb-4d1b-a2c1-73316203bc54
# ╠═34a7aa4b-2d40-4a66-be79-fed470cd6185
# ╠═f1e49314-717c-4d7c-9140-8f4d56f61165
# ╠═d038cab7-22e0-4595-9bd6-ed2e7ff5f247
# ╠═6cb06dbf-5239-44f2-8ac4-d1e776237167

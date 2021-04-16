using JuMP, Plots, Ipopt

g = 9.81
Pmax = 1000  # Watts
FTP = 300    # Watts
Wmax = 20000 # kJs
mass = 75    # kgs

RR = 0.05    # W/(kgm/s)
CdA = 0.25

# Course parameters
grads = rand(n_sectors) .+ 5 .* sin.(collect(1:n_sectors) ./ 10) # gradient (%)
n = 100                                                          # number of sectors
sector_length = 0.050 .* ones(n)                                 # sector length (km)   

# Initializing model
m = Model(with_optimizer(Ipopt.Optimizer))

# Course variables
@variable(m, speed[1:n] >= 0)               # speed (m/s)
@variable(m, sector_time[1:n] >= 0)         # sector time (s)
@variable(m, xvel[1:n] >= 0)                # horizontal velocity (m/s)
@variable(m, yvel[1:n])                     # vertical velocity (m/s)

# Course constraints
@constraint(m, xvel .== speed / 3.6 .* (1 .- grads./ 100)) 
@constraint(m, yvel .== speed / 3.6 .* grads ./ 100)
@constraint(m, sector_time .*  xvel .== 1000 .* sector_length)

# Physiological variables
@variable(m, Pmax >= P[1:n] >= 0) # Power in each sector
@variable(m, Wcost[1:n] >= 0) # W' cost
@variable(m, Wrec[1:n])  # W' recovery
@variable(m, Wmax >= W[1:n] >= 0)

# Physiological constraints
for i=1:n
    @NLconstraint(m, P[i] >= (1/2*CdA) * (speed[i] / 3.6)^3 + RR*mass*speed[i]/3.6 + g*mass*yvel[i])
    @NLconstraint(m, Wcost[i] >= FTP*exp((P[i] - FTP)/FTP) - FTP)
    @constraint(m, Wrec[i] <= 0.5*(FTP - P[i]))
end
@constraint(m, W[1] == Wmax)
for i=2:n
    @constraint(m, W[i] <= W[i-1] + sector_time[i-1] * Wrec[i-1] - sector_time[i-1] * Wcost[i-1])
end
@constraint(m, P[n] <= 1/2 * Pmax) # For conditioning of the final sprint

# Objective: minimize total time
@objective(m, Min, sum(sector_time))
optimize!(m)

# Plotting results
xvals = [getvalue.(sector_time)[1]]
[push!(xvals, xvals[end] + getvalue.(sector_time)[i]) for i=2:n];
p1 = plot(xvals, getvalue.(speed), label = "Speed (kph)")
p2 = plot(xvals, grads, label = "Gradient (%)")
p3 = plot(xvals, getvalue.(P), label = "Power (W)")
p4 = plot(xvals, getvalue.(W), label = "W' (kJ)")
plot(p1, p2, p3, p4, layout = (4, 1), xlabel = "Time (s)", legend = :bottomleft)

# W' model validation
# W' consumption (exponential for now)
# Pexp = 0:25:500
# plot(Pexp, FTP.*exp.((Pexp .- FTP)./FTP) .- FTP)
# W' recovery (linear for now)
# plot(Pexp, -Pexp .+ FTP)

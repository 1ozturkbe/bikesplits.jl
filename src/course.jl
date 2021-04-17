using JuMP, Plots, Ipopt

g = 9.81
Pmax = 1000  # Watts
FTP = 300    # Watts
Wmax = 20000 # kJs
mass = 75    # kgs

RR = 0.05    # W/(kgm/s)
CdA = 0.25

# Course parameters
mutable struct Course
    name         # string
    lengths      # m, as the crow flies
    gradients    # %
end

n=100
rc = Course("Test", 
            50 .* ones(n), 
            rand(n) .+ 5 .* sin.(collect(1:n) ./ 10))

# Initializing model
m = Model(with_optimizer(Ipopt.Optimizer))

# Course variables
@variable(m, speed[1:n] >= 0)               # speed (m/s)
@variable(m, sector_time[1:n] >= 0)         # sector time (s)
@variable(m, xvel[1:n] >= 0)                # horizontal velocity (m/s)
@variable(m, yvel[1:n])                     # vertical velocity (m/s)

# Course constraints
@constraint(m, speed .* cos.(rc.gradients ./100) .== xvel)
@constraint(m, yvel .== xvel .* rc.gradients ./ 100)
@constraint(m, sector_time .*  xvel .== rc.lengths)

# Physiological variables
@variable(m, Pmax >= P[1:n] >= 0) # Power in each sector
@variable(m, Wcost[1:n] >= 0) # W' cost
@variable(m, Wrec[1:n])       # W' recovery
@variable(m, Wmax >= W[1:n] >= 0)

# Physiological constraints
@NLconstraint(m, P[1] >= (1/2*CdA) * speed[1]^3 + RR*mass*speed[1] + g*mass*yvel[1] + 
        0.5*mass*(speed[1]^2) / sector_time[1])
@NLconstraint(m, Wcost[1] >= FTP*exp((P[1] - FTP)/FTP) - FTP)
@constraint(m, Wrec[1] <= 0.5*(FTP - P[1]))
for i=2:n
    @NLconstraint(m, P[i] >= (1/2*CdA) * speed[i]^3 + RR*mass*speed[i] + g*mass*yvel[i] + 
                0.5*mass*(speed[i]^2 - speed[i-1]^2) / sector_time[i])
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
p1 = plot(xvals, 3.6*getvalue.(speed), label = "Speed (kph)")
p2 = plot(xvals, rc.gradients, label = "Gradient (%)")
p3 = plot(xvals, getvalue.(P), label = "Power (W)")
p4 = plot(xvals, getvalue.(W), label = "W' (kJ)")
plot(p1, p2, p3, p4, layout = (4, 1), xlabel = "Time (s)", legend = :bottomleft)

# W' model validation
# W' consumption (exponential for now)
# Pexp = 0:25:500
# plot(Pexp, FTP.*exp.((Pexp .- FTP)./FTP) .- FTP)
# W' recovery (linear for now)
# plot(Pexp, -Pexp .+ FTP)

using JuMP, Plots, Ipopt

g = 9.81
Pmax = 1000  # Watts
FTP = 300    # Watts
Wmax = 20000 # kJs
mass = 75    # kgs

rho = 1.2
Crr = 0.05    # W/(kgm/s)
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
           5 .* sin.(collect(1:n) ./ 10))

# Initializing model
m = Model(with_optimizer(Ipopt.Optimizer))

# Course variables
@variable(m, speed[1:n] >= 0)               # speed (m/s)
@variable(m, xtime[1:n] >= 0)               # sector time (s)
@variable(m, xvel[1:n] >= 0)                # horizontal velocity (m/s)
@variable(m, yvel[1:n])                     # vertical velocity (m/s)

# Drag variables
@variable(m, rrP[1:n] >= 0) # Rolling resistance power
@variable(m, dP[1:n] >= 0) # Drag power
@variable(m, gP[1:n]) # Gravitational power

# Physiological variables
@variable(m, Pmax >= P[1:n] >= 0) # Power in each sector
@variable(m, tw[1:n] >= 0)        # Recovery time constant    
@variable(m, deltaP[1:n])         # Power above CP                                               
@variable(m, Wcost[1:n] >= 0)     # W' cost (kJ/s)
@variable(m, Wrec[1:n])           # W' recovery (kJ/s)
@variable(m, Wmax >= W[1:n] >= 0) 

# Course constraints
@constraint(m, speed .* cos.(rc.gradients ./100) .== xvel)
@constraint(m, yvel .== xvel .* rc.gradients ./ 100)
@constraint(m, xtime .*  xvel .== rc.lengths)

# Drag constraints
@constraint(m, rrP .== Crr*mass*xvel) # TODO check assumption
@constraint(m, gP .== g*mass*yvel)
@NLconstraint(m, [i=1:n], dP[i] >= (0.5*rho*CdA) * speed[i] ^ 3)

# Energy conservation constraints
@NLconstraint(m, P[1] >= dP[1] + rrP[1] + gP[1] + 
        0.5*mass*(speed[1]^2) / xtime[1])
@NLconstraint(m, [i=2:n], P[i] >= dP[i] + rrP[i] + gP[i] + 
        0.5*mass*(speed[i]^2 - speed[i-1]^2) / xtime[i])

# Physiological constraints
@constraint(m, deltaP .== P .- FTP)
@constraint(m, W[1] == Wmax)
@constraint(m, Wcost[1] >= deltaP[1])
@NLconstraint(m, tw[1] >= 546*exp(-0.01*(deltaP[1])) + 316)
@NLconstraint(m, Wrec[1] <= Wmax / tw[1])
for i=2:n
    @constraint(m, Wcost[i] >= deltaP[i])
    @NLconstraint(m, tw[i] >= 546*exp(-0.01*(deltaP[i])) + 316)
    @NLconstraint(m, Wrec[i] <= Wmax / tw[i])
    @NLconstraint(m, W[i] <= W[i-1] + xtime[i-1] * Wrec[i-1] - xtime[i-1] * Wcost[i-1])
end
@constraint(m, P[n] <= 1/2 * Pmax) # For conditioning of the final sprint

# Objective: minimize total time
@objective(m, Min, sum(xtime))
optimize!(m)

# Plotting results
xvals = [getvalue.(xtime)[1]]
[push!(xvals, xvals[end] + getvalue.(xtime)[i]) for i=2:n];
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

# DCP = -300:5:300;
# timeconst = 546 .* exp.(0.01 .* (DCP));
# plot(DCP, timeconst)
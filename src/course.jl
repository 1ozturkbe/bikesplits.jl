using JuMP, Plots, Ipopt

g = 9.81
Pmax = 1000 # Watts
FTP = 300 # Watts
Wmax = 20000 # kJs
mass = 75 # kgs

RR = 0.05 #W/(kgm/s)
CdA = 0.03

n = 100
sector_distance = 50 # meters


grads = rand(n_sectors) .+ 5 .* sin.(collect(1:n_sectors) ./ 10) # percentage
plot(grads)


m = Model(with_optimizer(Ipopt.Optimizer))

@variable(m, Pmax >= P[1:n] >= 0) # Power in each sector

@variable(m, Wcost[1:n] >= 0) # W' cost
@variable(m, Wrec[1:n])  # W' recovery
@variable(m, Wmax >= W[1:n] >= 0)
for i=1:n
    @NLconstraint(m, Wcost[i] >= FTP*exp((P[i] - FTP)/FTP) - FTP)
    @constraint(m, Wrec[i] <= FTP - P[i])
end
@constraint(m, W[1] == Wmax)
for i=2:n
    @constraint(m, W[i] == W[i-1] + Wrec[i-1] - Wcost[i-1])
end

@variable(m, speed[1:n] >= 0) 
@variable(m, sector_time[1:n] >= 0)
@variable(m, xvel[1:n] >= 0)
@variable(m, yvel[1:n])

# Transit constraints
@constraint(m, xvel .== speed .* (1 .- grads./ 100)) 
@constraint(m, yvel .== speed .* grads ./ 100)
@constraint(m, sector_time .*  xvel .== sector_distance)

# Objective: minimize total time
@objective(m, Min, sum(sector_time))

# Power in each sector
for i=1:n
    @NLconstraint(m, P[i] >= (1/2*CdA) * speed[i]^3 + RR*mass*speed[i] + g*mass*yvel[i])
end

optimize!(m)

p1 = plot(getvalue.(speed), label = "Speed (m/s)")
p2 = plot(grads, label = "Gradient (%)")
p3 = plot(getvalue.(P), label = "Power (W)")
p4 = plot(getvalue.(W), label = "W' (kJ)")
plot(p1, p2, p3, p4, layout = (4, 1), legend = :inside)


# W' model validation
# W' consumption (exponential for now)
# Pexp = 0:25:500
# plot(Pexp, FTP.*exp.((Pexp .- FTP)./FTP) .- FTP)
# W' recovery (linear for now)
# plot(Pexp, -Pexp .+ FTP)

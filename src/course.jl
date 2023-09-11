using JuMP, Plots, Ipopt, Parameters

include("structs.jl")

include("plots.jl")

rider = Rider()
# course = Course(name = "Test",
#             lengths = 100 .* ones(100), 
#             gradients = 1 .* cos.(collect(1:100) ./ 50) + 5 .* sin.(collect(1:100) ./ 10))


test_gradients = zeros(10)
append!(test_gradients, 2*ones(10))
append!(test_gradients, 5*ones(10))
append!(test_gradients, zeros(20))
append!(test_gradients, -2*ones(10))
append!(test_gradients, 3*ones(40))

course = Course(name = "Test",
            lengths = 50 .* ones(100), 
            gradients = test_gradients
)



# Optimal pacing model
function pacing_model(rider::Rider, course::Course, solver = Ipopt.Optimizer)
    g = 9.81
    m = Model(with_optimizer(solver))
    n = course.n

    # Course variables
    @variables(m, begin
                    speed[1:n] >= 0             # speed (m/s)
                    xtime[1:n] >= 0             # sector time (s)
                    xvel[1:n] >= 0              # horizontal velocity (m/s)
                    yvel[1:n]                   # vertical velocity (m/s)

    # Drag variables
                    rrP[1:n] >= 0               # Rolling resistance power (W)
                    dP[1:n] >= 0                # Drag power (W)
                    gP[1:n]                     # Gravitational power (W)

    # Physiological variables
                    rider.Pmax >= P[1:n] >= 0   # Power in each sector (W)
                    tw[1:n] >= 0                # Recovery time constant (s) 
                    deltaP[1:n]                 # Power above CP (W)                                           
                    Wcost[1:n]                  # W' depletion rate (J/s)
                    rider.Wmax >= W[1:n] >= 0   # W' remaining (J)
    end)

    # Course constraints
    @constraint(m, speed .* cos.(course.gradients ./100) .== xvel)
    @constraint(m, yvel .== xvel .* course.gradients ./ 100)
    @constraint(m, xtime .*  xvel .== course.lengths)

    # Drag constraints
    @constraint(m, rrP .== rider.Crr*rider.mass*xvel)
    @constraint(m, gP .== g*rider.mass*yvel)
    @NLconstraint(m, [i=1:n], dP[i] >= (0.5*course.rho*rider.CdA) * speed[i] ^ 3)

    # Energy conservation constraints
    @NLconstraint(m, P[1] >= dP[1] + rrP[1] + gP[1] + 
            0.5*rider.mass*(speed[1]^2) / xtime[1])
    @NLconstraint(m, [i=2:n], P[i] >= dP[i] + rrP[i] + gP[i] + 
            0.5*rider.mass*(speed[i]^2 - speed[i-1]^2) / xtime[i])

    # Physiological constraints
    @constraint(m, deltaP .== P .- rider.CP)
    @NLconstraint(m, [i=1:n], Wcost[i] == deltaP[i] * exp(-xtime[i] * (tw[i] ^ -1)))
    @NLconstraint(m, [i=1:n], tw[i] == 546*exp(-0.01*(deltaP[i])) + 316)
    @constraint(m, W[1] == rider.Wmax)
    @NLconstraint(m, [i=2:n], W[i] <= W[i-1] - xtime[i-1] * Wcost[i-1])

    # Conditioning constraints
    @constraint(m, P .<= rider.CP*1.5)

    # Objective: minimize total time
    @objective(m, Min, sum(xtime)) 
    return m
end

m = pacing_model(rider, course)
optimize!(m)

# Plotting results
plot_optimal_strategy(m, course)
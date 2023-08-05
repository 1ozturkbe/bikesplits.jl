using JuMP, Plots, Ipopt, Parameters

include("structs.jl")

include("plots.jl")

m = Model(with_optimizer(Ipopt.Optimizer))
n = 84
n_weeks = Int(floor(n/7))
target_fitnesses = [80, 80]
initial_fatigue = 0
initial_fitness = 60
max_ramp_rate = 12 # per week
max_fatigue = 140
target_dates = [71, 82]
target_race_TSSs = [140, 200]

@variables(m, begin
    TSS[1:n] >= 0              # TSS on day i
    duration[1:n] >= 0         # duration on day i
    intensity[1:n] >= 0        # intensity on day i
    fitness[1:n] >= 0
    fatigue[1:n] >= 0
    form[1:n] >= 0
end)

# Objective function
@variable(m, fitness_error[1:length(target_dates)] >= 0)
@constraint(m, fitness_error .>= target_fitnesses .- fitness[target_dates])
@constraint(m, fitness_error .>= fitness[target_dates] .- target_fitnesses)
@objective(m, Min, sum(fitness_error))

# Constraints on fitness and fatigue
@constraint(m, [i=1:6], fatigue[i] == (sum(TSS[1:i]) + initial_fitness*(7-i))./7)
@constraint(m, [i=1:27], fitness[i] == (sum(TSS[1:i]) + initial_fitness*(28-i))./28)
@constraint(m, [i=7:n], fatigue[i] == sum(TSS[i-6:i])/7)
@constraint(m, [i=28:n], fitness[i] == sum(TSS[i-27:i])/28)
    
# Constraints on race day performance
@constraint(m, [i=target_dates], form[i] >= 0)
@constraint(m, TSS[target_dates] .== target_race_TSSs)

# Constraints on ramp rate per week
@constraint(m, [i=2:n_weeks], sum(TSS[(i-2)*7+1:7*(i-1)]) + 7*max_ramp_rate >= sum(TSS[(i-1)*7+1:7*i]))

# Constraints on max fatigue
@constraint(m, fatigue .<= max_fatigue)

optimize!(m)
plot(getvalue.(m[:TSS]), label="daily TSS")
plot!(getvalue.(m[:fitness]), label="fitness")
plot!(getvalue.(m[:fatigue]), label="fatigue")
scatter!(target_dates, target_fitnesses, label="TSS targets")


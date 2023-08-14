using JuMP, Plots, GLPK, Parameters

include("structs.jl")

include("plots.jl")

m = Model(GLPK.Optimizer)

# Dates

# Parameters
n = 140
n_weeks = Int(floor(n/7))
target_fitnesses = [80, 80]
initial_fatigue = 60
initial_fitness = 60
max_ramp_rate = 50 # TSS per week
max_fatigue = 120
rest_week_factor = 0.6
rest_day = 1 # Monday
target_dates = [124, 139]
target_race_TSSs = [200, 170]

rest_day_TSS = 40

@variables(m, begin
    TSS[1:n] >= 0              # TSS on day i
    duration[1:n] >= 0         # duration on day i
    intensity[1:n] >= 0        # intensity on day i
    fitness[1:n] >= 0
    fatigue[1:n] >= 0
    weekly_TSS[1:n_weeks] >= 0
    form[1:n]
end)

# Objective function
@variable(m, fitness_error[1:length(target_dates)] >= 0)
@variable(m, max_fitness >= 0)
@constraint(m, fitness_error .>= target_fitnesses .- fitness[target_dates])
@constraint(m, fitness_error .>= fitness[target_dates] .- target_fitnesses)
# Small regularization on maximum fitness
@constraint(m, max_fitness .>= fitness)
@constraint(m, max_fitness .>= target_fitnesses .+ 10)

@objective(m, Min, sum(fitness_error) + 1e-5*max_fitness + 1e-7*sum(TSS))

# Constraints on fitness, fatigue and form
@constraint(m, [i=1:6], fatigue[i] == (sum(TSS[1:i]) + initial_fitness*(7-i))./7)
@constraint(m, [i=1:27], fitness[i] == (sum(TSS[1:i]) + initial_fatigue*(28-i))./28)
@constraint(m, [i=7:n], fatigue[i] == sum(TSS[i-6:i])/7)
@constraint(m, [i=28:n], fitness[i] == sum(TSS[i-27:i])/28)
@constraint(m, form .== fitness - fatigue)

# Constraints on race day performance
@constraint(m, [i=target_dates], form[i] >= 0)
@constraint(m, TSS[target_dates] .== target_race_TSSs)

# Determine base, build and specialty
weeks_of_races = Int.(floor.(target_dates/7))


# # No more than  two rest days a week, but definitely at least one rest day
# # On rest days, AT MOST rest_day_TSS
# @variable(m, rest_day[1:n_weeks, 1:7], Bin)
# for j = 1:n_weeks
#     @constraint(m, sum(rest_day[j, :]) <= 2)
#     @constraint(m, sum(rest_day[j, :]) >= 1)
#     for i=1:7
#         @constraint(m, TSS[7*(j-1)+ i] <= 1000 * (1-rest_day[j, i]) + rest_day_TSS)
#         @constraint(m, TSS[7*(j-1)+ i] >= rest_day_TSS)
#     end
# end

# Adding rest days
@constraint(m, [i=1:n_weeks], TSS[4*(i-1) + rest_day] <= 40)

# Constraints on ramp rate
# Constraints on ramp rate per week
@constraint(m, [i=1:n_weeks], weekly_TSS[i] == sum(TSS[7*i-6:7*i]))
for i=1:n_weeks
    if (i == 1) && ((i in weeks_of_races) == false)
        @constraint(m, weekly_TSS[1] <= initial_fitness*7 + max_ramp_rate)
    elseif (i-1 in rest_weeks) == false
        @constraint(m, weekly_TSS[i-1] + max_ramp_rate >= weekly_TSS[i])
    elseif i >= 3
        @constraint(m, weekly_TSS[i-2] + 1.5*max_ramp_rate >= weekly_TSS[i])
    end
end


# Rest week every fourth week, corresponding to reduced TSS by rest_week_factor
rest_weeks = []
for i = 1:Int(floor(n_weeks/4))
    for j = (i-1)*4+1:i*4
        if (4*i != j) 
            if !(4*i in weeks_of_races) && !(j in weeks_of_races)
                @constraint(m, weekly_TSS[4*i] <= rest_week_factor*weekly_TSS[j])
            end
        end
    end
    push!(rest_weeks, Int(4*i))
end

# Constraints on max fatigue
@constraint(m, fatigue .<= max_fatigue)

optimize!(m)

# Plotting
mf = maximum(getvalue.(TSS))

plots1 = []
plots2 = []
push!(plots1, scatter(getvalue.(m[:TSS]), label="daily TSS"))
push!(plots1, plot!(getvalue.(m[:fitness]), label="fitness"))
push!(plots1, plot!(getvalue.(m[:fatigue]), label="fatigue"))
push!(plots1, scatter!(target_dates, target_fitnesses, label="fitness targets"))
for i=1:n_weeks
    push!(plots1, plot!([7*i + 0.5, 7*i + 0.5], [0, mf], label=false))
end
# # Plot weekly averages as well
# for i=1:n_weeks
#     week_avg = getvalue.(sum(m[:TSS][7*(i-1) + 1:7*i]))/7
#     push!(plots2, plot!([7*(i-1), i*7], [week_avg, week_avg], label=false))
# end

plot(plots1[length(plots1)])

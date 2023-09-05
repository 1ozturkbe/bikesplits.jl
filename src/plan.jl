using JuMP, Plots, GLPK, Parameters

include("structs.jl")

include("plots.jl")

m = Model(GLPK.Optimizer)
set_optimizer_attribute(m, "msg_lev", GLPK.GLP_MSG_ON)

# Dates

# Parameters
n = 175
n_weeks = Int(floor(n/7))
target_fitnesses = [85, 80]
initial_fatigue = 50
initial_fitness = 50
max_ramp_rate = 5 # fitness per week
max_fatigue = 120
rest_week_factor = 0.6
rest_day_choice = 1 # Monday
build_day_choice = [2, 4]   # Tuesday, Thursday
base_day_choice = [2, 4, 6] # Tuesday, Thursday, Saturday
weekday_max_TSS = 200
weekend_max_TSS = 300
target_dates = [154, 174]
target_race_TSSs = [200, 170]

# Determine base, build and specialty
# FEEL FREE TO OVERWRITE AND MODIFY THESE TO YOUR LIKING. 
# DEFINITELY NO MORE THAN 8 WEEKS IN BUILD, REGARDLESS OF YOUR SEASON!
race_weeks = Int.(floor.(target_dates/7))
rest_weeks  = collect(1:Int(floor(n_weeks/4)))*4
n_build_weeks = minimum([8, Int(floor(maximum([4, 0.4 * (n_weeks 
        - length(rest_weeks) - length(race_weeks))])))])
n_base_weeks = n_weeks - length(race_weeks) - length(rest_weeks) - n_build_weeks
base_weeks = [i for i in collect(1:n_base_weeks) if (i in rest_weeks) == false]
build_weeks = []
for i=n_base_weeks+1:n_weeks
    if ((i in race_weeks) == false) && ((i in rest_weeks) == false)
        append!(build_weeks, i)
    end
end

# ===========================
# VARIABLES
# ===========================
# Variables for measuring progress
@variables(m, begin
    1000 >= TSS[1:n] >= 0              # TSS on day i
    duration[1:n] >= 0         # duration on day i
    intensity[1:n] >= 0        # intensity on day i
    fitness[1:n] >= initial_fitness-1
    fatigue[1:n] >= 0
    weekly_TSS[1:n_weeks] >= 0
    form[1:n]
    fitness_error[1:length(target_dates)] >= 0  # fitness deviation for key events
end)

# Variables for determining build phase intensity
@variable(m, build_eps[i=1:length(build_weeks), j=build_day_choice])
@variable(m, build_eps_error[i=1:length(build_weeks), j=build_day_choice] >= 0)

# Variables defining maximum TSS at each phase
@variable(m, max_base_TSS >= 0)
@variable(m, max_build_TSS >= 0)

# Variable for determining the rate at which fatigue is increasing
# Used to regularize the objective function
@variable(m, fatigue_accel[1:n-1] >= 0)

# ===========================
# CONSTRAINTS
# ===========================

# Constraints on fitness, fatigue and form
@constraint(m, fatigue[1] == initial_fatigue * 6/7 + TSS[1] * 1/7)
@constraint(m, [i=2:n], fatigue[i] == fatigue[i-1] * 6/7 + TSS[i] * 1/7)
@constraint(m, fitness[1] == initial_fitness * 41/42 + TSS[1] * 1/42)
@constraint(m, [i=2:n], fitness[i] == fitness[i-1] * 41/42 + TSS[i] * 1/42)
@constraint(m, form .== fitness - fatigue)

# Constraints on race day performance
@constraint(m, [i=target_dates], form[i] >= 0)
@constraint(m, TSS[target_dates] .== target_race_TSSs)

# Adding rest days, but making sure work gets done on not-rest days
@constraint(m, [i=1:n_weeks], TSS[4*(i-1) + rest_day_choice] <= 0.4*maximum(target_fitnesses))

# Introducing base weeks
# Try to do 3 days of focused endurance work outside of rest days, 
# Amounting to ~80% of the TSS for the week
for i=1:length(base_weeks)
    @constraint(m, sum(TSS[7*(i-1) .+ base_day_choice]) >= 0.80 * weekly_TSS[i])
end

# Building up the build weeks
# First week, each workout is equal to target_fitness
# Then, every week, we increase by 5...
@constraint(m, [i=1:length(build_weeks), j=build_day_choice], 
            TSS[7*(build_weeks[i]-1)+j] == maximum(target_fitnesses) + 5*(i-1) + build_eps[i,j])
@constraint(m, build_eps_error .>= build_eps)
@constraint(m, build_eps_error .>= -build_eps)

# Rest week every fourth week, corresponding to reduced TSS by rest_week_factor
for i = 1:Int(floor(n_weeks/4))
    for j = (i-1)*4+1:i*4
        if (4*i != j) 
            if !(4*i in race_weeks) && !(j in race_weeks)
                @constraint(m, weekly_TSS[4*i] <= rest_week_factor*weekly_TSS[j])
            end
        end
    end
end

# Constraints on ramp rate per week, and on maximum weekday and weekend TSSs
@constraint(m, [i=1:n_weeks], weekly_TSS[i] == sum(TSS[7*i-6:7*i]))
for i=1:n_weeks
    if (i == 1) && ((i in race_weeks) == false)
        @constraint(m, weekly_TSS[1] <= initial_fitness*7 + 7*max_ramp_rate)
    elseif (i-1 in rest_weeks) == false
        @constraint(m, weekly_TSS[i-1] + 7*max_ramp_rate >= weekly_TSS[i])
    elseif (i-1 in rest_weeks)
        @constraint(m, weekly_TSS[i-2] + 7*max_ramp_rate >= weekly_TSS[i])
    end
    # for j = 1:5
    #     @constraint(m, TSS[7*(i-1) + j] <= weekday_max_TSS)
    # end
    # for j = 6:7
    #     @constraint(m, TSS[7*(i-1) + j] <= weekend_max_TSS)
    # end
end

# Making sure that the maximum weekly TSS is during the base phase, NOT the build
@constraint(m, max_build_TSS .>= weekly_TSS[build_weeks])
@constraint(m, 1.1*weekly_TSS[base_weeks[end]] >= max_build_TSS)

# Constraints on max fatigue, and adding fatigue accelerations
@constraint(m, fatigue .<= max_fatigue)

# Objective function (i.e. minimize fitness error)
@constraint(m, fitness_error .>= target_fitnesses .- fitness[target_dates])
@constraint(m, fitness_error .>= fitness[target_dates] .- target_fitnesses)
@constraint(m, [i=1:n-1], fatigue_accel[i] >= fatigue[i+1] - fatigue[i])
@objective(m, Min, sum(fitness_error) + 1e-3 * sum(build_eps_error))

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

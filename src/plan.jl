using JuMP, Plots, GLPK, Parameters, Dates

include("structs.jl")

include("plots.jl")

m = Model(GLPK.Optimizer)
set_optimizer_attribute(m, "msg_lev", GLPK.GLP_MSG_ON)

# Date counting
start_date = Dates.Date(2023, 10, 15)
target_race_dates = [Dates.Date(2024, 03, 29), 
                     Dates.Date(2024, 05, 04)]
target_race_TSSs = [250, 250]


struct Workout
    date::Dates.Date
    TSS::Float64
    week_count::Int
    week_type
    weekly_TSS::Float64
    fitness::Float64
    fatigue::Float64
    form::Float64
end     

# Parameters
target_dates = [d.value for d in target_race_dates - start_date]
n = maximum(target_dates)
n = 7*Int(ceil(n/7))
n_weeks = Int(n/7)
target_fitnesses = [85, 80]
initial_fatigue = 50
initial_fitness = 50
max_ramp_rate = 5 # fitness per week
max_fatigue = 120
max_rest_week_factor = 0.75
min_rest_week_factor = 0.5
rest_day_choice = 1 # Monday
build_day_choice = [2, 4]   # Tuesday, Thursday
base_day_choice = [2, 4, 6] # Tuesday, Thursday, Saturday
weekday_max_TSS = 200 
weekend_max_TSS = 250

# Determine base, build and specialty
# FEEL FREE TO OVERWRITE AND MODIFY THESE TO YOUR LIKING. 
# DEFINITELY NO MORE THAN 7 WEEKS IN INITIAL BUILD, REGARDLESS OF YOUR SEASON!
race_weeks = Int.(ceil.(target_dates/7))
rest_weeks  = [i for i in collect(1:Int(floor(n_weeks/4)))*4 if (i in race_weeks) == false]
n_build_weeks = minimum([7, Int(floor(maximum([4, 0.4 * (n_weeks 
        - length(rest_weeks) - length(race_weeks))])))])
n_base_weeks = n_weeks - length(race_weeks) - length(rest_weeks) - n_build_weeks
base_weeks = [i for i in collect(1:n_base_weeks) if (i in rest_weeks) == false]
build_weeks = []
for i=n_base_weeks+1:n_weeks
    if ((i in race_weeks) == false) && ((i in rest_weeks) == false)
        if (i < n_weeks) && (i+1 in race_weeks) && (i+1 != race_weeks[1])
            append!(rest_weeks, i)
        else
            append!(build_weeks, i)
        end
    end
end

# ===========================
# VARIABLES
# ===========================
# Variables for measuring progress
@variables(m, begin
    1000 >= TSS[1:n] >= 0      # TSS on day i
    duration[1:n] >= 0         # duration on day i
    intensity[1:n] >= 0        # intensity on day i
    fitness[1:n] >= initial_fitness-1
    fatigue[1:n] >= 0
    weekly_TSS[1:n_weeks] >= 0
    ramp_rate[1:n_weeks]
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
@constraint(m, [i=1:n_weeks], TSS[7*(i-1) + rest_day_choice] == 40)

# Introducing base weeks
# Try to do 3 days of focused endurance work outside of rest days, 
# Amounting to ~80% of the TSS for the week
for i = base_weeks
    for j = 1:length(base_day_choice) - 1
        @constraint(m, TSS[7*(i-1) + base_day_choice[j]] == TSS[7*(i-1) + base_day_choice[j+1]])
    end
    @constraint(m, sum(TSS[7*(i-1) .+ base_day_choice]) == 0.70 * weekly_TSS[i])
end

# Building up the build weeks
# First week, each workout is equal to target_fitness
# Then, every week, we increase by 5...
@constraint(m, [i=1:length(build_weeks), j=build_day_choice], 
            TSS[7*(build_weeks[i]-1)+j] == maximum(target_fitnesses) + 5*(i-1) + build_eps[i,j])
non_build_days = setdiff(1:7, build_day_choice, rest_day_choice)
@constraint(m, build_eps_error .>= build_eps)
@constraint(m, build_eps_error .>= -build_eps)

# Rest week every fourth week, corresponding to reduced TSS by rest_week_factor
for i = 1:length(rest_weeks)
    rw = rest_weeks[i]
    bws = []
    # Let's collect the values of three previous base, build and race weeks
    for j = rw-1:-1:1
        if length(bws) >= 3
            break
        end
        if (j in rest_weeks) == false
            append!(bws, j)
        end
    end
    for bw in bws
        @constraint(m, weekly_TSS[rw] <= max_rest_week_factor*weekly_TSS[bw])
        @constraint(m, weekly_TSS[rw] >= min_rest_week_factor*weekly_TSS[bw])
    end
end

# Constraints on ramp rate per week, 
# and on maximum weekday and weekend TSSs
# and on TSS in general
@constraint(m, [i=1:n_weeks], weekly_TSS[i] == sum(TSS[7*i-6:7*i]))
@constraint(m, [i=1:n_weeks], ramp_rate[i] <= max_ramp_rate)
for i=1:n_weeks
    if (i == 1)
        @constraint(m, weekly_TSS[1] == initial_fitness*7 + 7*ramp_rate[i])
    elseif (i in race_weeks) #|| (i in camp_weeks)
        continue
    elseif (i-1 in rest_weeks) == false
        @constraint(m, weekly_TSS[i-1] + 7*ramp_rate[i] == weekly_TSS[i])
    elseif (i-2 in rest_weeks) == false
        @constraint(m, weekly_TSS[i-2] + 7*ramp_rate[i] == weekly_TSS[i])
    end
    for j = 1:5
        @constraint(m, TSS[7*(i-1) + j] <= weekday_max_TSS)
    end
    for j = 6:7
        @constraint(m, TSS[7*(i-1) + j] <= weekend_max_TSS)
    end
end

# Making sure that the maximum weekly TSS is during the base phase, NOT the build
@constraint(m, max_build_TSS .>= weekly_TSS[build_weeks])
@constraint(m, weekly_TSS[base_weeks[end]] >= max_build_TSS + 50)

# Constraints on max fatigue, and adding fatigue accelerations
@constraint(m, fatigue .<= max_fatigue)

# Objective function (i.e. minimize fitness error)
@constraint(m, fitness_error .>= target_fitnesses .- fitness[target_dates])
@constraint(m, fitness_error .>= fitness[target_dates] .- target_fitnesses)
@constraint(m, [i=1:n-1], fatigue_accel[i] >= fatigue[i+1] - fatigue[i])
@objective(m, Min, sum(fitness_error) + 1e-3 * sum(build_eps_error) + 1e-7*sum(fatigue_accel))

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

# Plotting in base, build and rest weeks
import Plots.Shape
rectangle(w, h, x, y) = Shape(x .+ [0,w,w,0], y .+ [0,0,h,h])
for i in 1:n_weeks
    if i in rest_weeks
        push!(plots1, plot!(rectangle(7, weekend_max_TSS, 7*(i-1), 0), color = "green",
        opacity=0.25, label=false))
    elseif i in base_weeks
        push!(plots1, plot!(rectangle(7, weekend_max_TSS, 7*(i-1), 0), color = "blue",
        opacity=0.25, label=false))
    elseif i in build_weeks
        push!(plots1, plot!(rectangle(7, weekend_max_TSS, 7*(i-1), 0), color = "yellow",
        opacity=0.25, label=false))
    elseif i in race_weeks
        push!(plots1, plot!(rectangle(7, weekend_max_TSS, 7*(i-1), 0), color = "red", 
        opacity=0.25, label=false))
    end
end

# Let's plot the weekly progressions
push!(plots2, plot())
for i in 1:n_weeks
    if i in rest_weeks
        push!(plots2, plot!(rectangle(1, getvalue(weekly_TSS[i]), (i-1), 0), color = "green", 
        opacity=0.75, label=false))
    elseif i in base_weeks
        push!(plots2, plot!(rectangle(1, getvalue(weekly_TSS[i]), (i-1), 0), color = "blue", 
        opacity=0.75, label=false))
    elseif i in build_weeks
        push!(plots2, plot!(rectangle(1, getvalue(weekly_TSS[i]), (i-1), 0), color = "yellow", 
        opacity=0.75, label=false))
    elseif i in race_weeks
        push!(plots2, plot!(rectangle(1, getvalue(weekly_TSS[i]), (i-1), 0), color = "red", 
        opacity=0.75, label=false))
    end
end

plot(plots2[end])

function return_week_type(i:: Int)
    if i in rest_weeks
        return "rest"
    elseif i in base_weeks
        return "base"
    elseif i in build_weeks
        return "build"
    elseif i in race_weeks
        return "race"
    else
        return ArgumentError("Week number not in dataset.")
    end
end

# Filling in Workout data
workouts = []
for i in 1:n_weeks
    for j in 1:7
        day_number = 7*(i-1) + j
        nw = Workout(start_date + Dates.Day(day_number-1), 
                     Int(round(getvalue(TSS[day_number]))), 
                     i, 
                     return_week_type(i), 
                     Int(round(getvalue(weekly_TSS[i]))), 
                     Int(round(getvalue(fitness[day_number]))), 
                     Int(round(getvalue(fatigue[day_number]))), 
                     Int(round(getvalue(form[day_number]))),
                     )
        push!(workouts, nw)
    end
end

plot(plots2[end])

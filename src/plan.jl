using JuMP, Plots, GLPK, Parameters, Dates

include("structs.jl")

include("plots.jl")

m = Model(GLPK.Optimizer)
set_optimizer_attribute(m, "msg_lev", GLPK.GLP_MSG_ON)

plan_type = "A"

if plan_type == "A"
    target_fitnesses = [75, 70]
    initial_fatigue = 55
    initial_fitness = 55
elseif plan_type == "B"
    target_fitnesses = [65, 60]
    initial_fatigue = 50
    initial_fitness = 50
elseif plan_type == "C"
    target_fitnesses = [55, 50]
    initial_fatigue = 40
    initial_fitness = 40
elseif plan_type == "D"
    target_fitnesses = [45, 40]
    initial_fatigue = 30
    initial_fitness = 30
end

# Date counting
start_date = Dates.Date(2023, 10, 16)
target_race_dates = [Dates.Date(2024, 03, 30), 
                     Dates.Date(2024, 05, 04)]
target_race_TSSs = target_fitnesses * 3

# camp_week = [Dates.Date(2024, 03, 29), 
# Dates.Date(2024, 05, 04)]


struct Workout
    date::Dates.Date
    day_number::Int
    TSS::Float64
    time::Float64
    week_count::Int
    week_type
    workout_type
    weekly_TSS::Float64
    fitness::Float64
    fatigue::Float64
    form::Float64
end 

function toString(w)
    field_map = [:date => "Date", 
                :day_number => "Day number",
                :workout_type => "Workout type",
                :TSS => "Workout TSS",
                :time => "Workout time",
                :week_count => "Week number",
                :weekly_TSS => "Weekly TSS",
                :fitness => "Target fitness",
                :fatigue => "Target fatigue",
                :form => "Target form"
                ]
    strrep = ""
    for (k,v) in field_map
        strrep *= v 
        strrep *= ": "
        strrep *= string(getfield(w, k))
        if k  == :time
            strrep *= " hours"
        end
        strrep *= " \\n"
    end  
    return strrep
end

# Parameters
target_dates = [d.value for d in target_race_dates - start_date]
n = maximum(target_dates)
n = 7*Int(ceil(n/7))
n_weeks = Int(n/7)
all_dates = [start_date + Dates.Day(day_number-1) for day_number = 1:n]

max_ramp_rate = 4 # fitness per week
max_fatigue = 120
max_rest_week_factor = 0.6
min_rest_week_factor = 0.5
rest_day_choice = 1 # Monday
build_day_choice = [2, 4]   # Tuesday, Thursday
base_day_choice = [2, 4, 6] # Tuesday, Thursday, Saturday
weekday_max_TSS = 200 
weekend_max_TSS = 250

# TSS values per hour
base_TSS_per_hour = 45
rest_TSS_per_hour = 30
build_TSS_per_hour = 70
race_TSS_per_hour = 70

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
    time[1:n] >= 0      # time on day i
    duration[1:n] >= 0         # duration on day i
    intensity[1:n] >= 0        # intensity on day i
    fitness[1:n] >= initial_fitness-1
    fatigue[1:n] >= 0
    weekly_TSS[1:n_weeks] >= 0
    weekly_time[1:n_weeks] >= 0
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
@variable(m, max_fitness >= 0)

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
@constraint(m, [i=1:n_weeks], rest_TSS_per_hour * time[7*(i-1) + rest_day_choice] == TSS[7*(i-1) + rest_day_choice])

# Introducing base weeks
# Try to do 3 days of focused endurance work outside of rest days, 
# Amounting to ~80% of the TSS for the week
non_rest_days = setdiff(1:7, rest_day_choice)
for i = base_weeks
    for j = 1:length(base_day_choice) - 1
        @constraint(m, TSS[7*(i-1) + base_day_choice[j]] == TSS[7*(i-1) + base_day_choice[j+1]])
    end
    @constraint(m, sum(TSS[7*(i-1) .+ base_day_choice]) == 0.70 * weekly_TSS[i])
    for j = non_rest_days
        @constraint(m, TSS[7*(i-1) .+ j] == base_TSS_per_hour * time[7*(i-1) .+ j])
    end
end

for i = rest_weeks
    for j = 1:length(base_day_choice) - 1
        @constraint(m, TSS[7*(i-1) + base_day_choice[j]] == TSS[7*(i-1) + base_day_choice[j+1]])
    end
    for j = non_rest_days
        @constraint(m, TSS[7*(i-1) + j] == base_TSS_per_hour * time[7*(i-1) + j])
    end
    @constraint(m, sum(TSS[7*(i-1) .+ base_day_choice]) == 0.70 * weekly_TSS[i])
end

# Building up the build weeks
# First week, each workout is equal to target_fitness
# Then, every week, we increase by 5...
@constraint(m, [i=1:length(build_weeks), j=build_day_choice], 
            TSS[7*(build_weeks[i]-1)+j] == maximum(target_fitnesses) + 5*(i-1) + build_eps[i,j])
@constraint(m, [i=1:length(build_weeks), j=build_day_choice], 
            TSS[7*(build_weeks[i]-1)+j] == build_TSS_per_hour * time[7*(build_weeks[i]-1)+j])
non_build_days = setdiff(1:7, build_day_choice, rest_day_choice)
@constraint(m, [i=1:length(build_weeks), j=non_build_days], 
            TSS[7*(build_weeks[i]-1)+j] == base_TSS_per_hour * time[7*(build_weeks[i]-1)+j])
            
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

# Putting in times for the race weeks as well
for i = race_weeks
    for j = 1:7
        if 7*(i-1) + j in target_dates
            @constraint(m, TSS[7*(i-1) + j] == race_TSS_per_hour * time[7*(i-1) + j])
        elseif mod(7*(i-1) + j, 7) == 1
            @constraint(m, TSS[7*(i-1) + j] == rest_TSS_per_hour * time[7*(i-1) + j])
        elseif mod(7*(i-1) + j, 7) in build_day_choice
            @constraint(m, TSS[7*(i-1) + j] == (build_TSS_per_hour - 10) * time[7*(i-1) + j])
        else
            @constraint(m, TSS[7*(i-1) + j] == base_TSS_per_hour * time[7*(i-1) + j])
        end
    end
end

# Constraints on ramp rate per week, 
# and on maximum weekday and weekend TSSs
# and on TSS in general
@constraint(m, [i=1:n_weeks], weekly_TSS[i] == sum(TSS[7*i-6:7*i]))
@constraint(m, [i=1:n_weeks], weekly_time[i] == sum(time[7*i-6:7*i]))
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

# Make sure that the maximum fitness is as low as possible, and add it to the objective
@constraint(m, max_fitness .>= fitness)

# Objective function (i.e. minimize fitness error)
@constraint(m, fitness_error .>= target_fitnesses .- fitness[target_dates])
@constraint(m, fitness_error .>= fitness[target_dates] .- target_fitnesses)
@constraint(m, [i=1:n-1], fatigue_accel[i] >= fatigue[i+1] - fatigue[i])
@objective(m, Min, sum(fitness_error) + 1e-3 * (max_fitness + sum(build_eps_error)) + 1e-7*sum(fatigue_accel))

optimize!(m)

# Plotting
mf = maximum(getvalue.(TSS))

plots1 = []
plots2 = []
plots3 = []
push!(plots1, scatter(getvalue.(m[:TSS]), label="daily TSS"))
push!(plots1, plot!(getvalue.(m[:fitness]), label="fitness"))
push!(plots1, plot!(getvalue.(m[:fatigue]), label="fatigue"))
push!(plots1, scatter!(target_dates, target_fitnesses, label="fitness targets"))
# for i=1:n_weeks
#     push!(plots1, plot!([7*i + 0.5, 7*i + 0.5], [0, mf], label=false))
# end

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

# Let's plot the weekly progressions in TSS
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

# Plot the weekly progressions in time
push!(plots3, plot())
for i in 1:n_weeks
    if i in rest_weeks
        push!(plots3, plot!(rectangle(1, getvalue(weekly_time[i]), (i-1), 0), color = "green", 
        opacity=0.75, label=false))
    elseif i in base_weeks
        push!(plots3, plot!(rectangle(1, getvalue(weekly_time[i]), (i-1), 0), color = "blue", 
        opacity=0.75, label=false))
    elseif i in build_weeks
        push!(plots3, plot!(rectangle(1, getvalue(weekly_time[i]), (i-1), 0), color = "yellow", 
        opacity=0.75, label=false))
    elseif i in race_weeks
        push!(plots3, plot!(rectangle(1, getvalue(weekly_time[i]), (i-1), 0), color = "red", 
        opacity=0.75, label=false))
    end
end


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

function return_workout_type(day_count::Int, week_count::Int)
    week_type = return_week_type(week_count)
    if mod(day_count, 7) == 1
        return "Recovery ride"
    end
    if week_type in ["rest", "base"]
        return "Endurance ride"
    elseif week_type == "build"
        if mod(day_count, 7) in build_day_choice
            return "Intervals"
        else
            return "Endurance ride"
        end
    elseif week_type == "race"
        if day_count in target_dates
            return "Race"
        elseif mod(day_count, 7) in build_day_choice
                return "Endurance ride with mild efforts"
            else
                return "Endurance ride"
            end
        else
        return ArgumentError("Week type is not supported.")
    end
end

# Filling in Workout data
workouts = []
events = []
for i in 1:n_weeks
    for j in 1:7
        day_number = 7*(i-1) + j
        if getvalue(TSS[day_number]) > 0
            week_type = return_week_type(i)
            workout_type = return_workout_type(day_number, i)
            nw = Workout(start_date + Dates.Day(day_number-1), 
                        day_number, 
                        Int(round(getvalue(TSS[day_number]))), 
                        round(getvalue(time[day_number]), digits=2), 
                        i, 
                        week_type, 
                        workout_type,
                        Int(round(getvalue(weekly_TSS[i]))), 
                        Int(round(getvalue(fitness[day_number]))), 
                        Int(round(getvalue(fatigue[day_number]))), 
                        Int(round(getvalue(form[day_number]))),
                        )
            push!(workouts, nw)
            new_event = Dict(
                "summary" => nw.workout_type,
                "dtstart" => Dates.DateTime(nw.date) + Dates.Hour(13),
                "dtend" => Dates.DateTime(nw.date) + Dates.Hour(13) + Dates.Minute(Int64(round(nw.time * 60))),
                "description" => toString(nw)
            )
            push!(events, new_event)
        end
    end
end


plot(plots1[end])
xlabel!("Day number")
ylabel!("TSS")
savefig(plan_type * "_fitness_profile.pdf")
plot(plots2[end])
xlabel!("Week number")
ylabel!("Weekly TSS")
savefig(plan_type * "_weekly_TSS_profile.pdf")
plot(plots3[end])
xlabel!("Week number")
ylabel!("Weekly time (hours)")
savefig(plan_type * "_weekly_time_profile.pdf")


#20010911T124640Z format!
# Function to create an iCalendar event
function create_ical_event(event)
    # Create an iCalendar event as a string
    sum = event["summary"]
    descr = event["description"]
    dtstart = Dates.format(event["dtstart"], "yyyymmddTHHMMSSZ")
    dtend = Dates.format(event["dtend"], "yyyymmddTHHMMSSZ")
    event_text = """
    BEGIN:VEVENT
    SUMMARY:$sum
    DESCRIPTION:$descr
    DTSTART:$dtstart
    DTEND:$dtend
    END:VEVENT
    """
    return event_text
end

function write_calendar(file, events)
    ical_data = "BEGIN:VCALENDAR\nVERSION:2.0\n"
    for event in events
        ical_data *= create_ical_event(event)
    end
    ical_data *= "END:VCALENDAR"

    # Write the iCalendar data to a file
    open(plan_type * "_calendar.ics", "w") do file
        write(file, ical_data)
    end
    println("Calendar events written to " * plan_type * " calendar.ics")
    return ical_data
end

ical_data = write_calendar(plan_type * "_calendar.ics", events)
import Dates


# Define the Calendar struct
struct Calendar
    year::Int
    month::Int
    day::Int
end

# Constructor for the Calendar struct
function Calendar(year::Int, month::Int, day::Int)
    if !isvaliddate(year, month, day)
        throw(ArgumentError("Invalid date: $year-$month-$day"))
    end
    new(year, month, day)
end

# Function to get the current date
function today()
    now = Dates.now()
    Calendar(Dates.year(now), Dates.month(now), Dates.day(now))
end

# Function to add days to the calendar
function add_days(calendar::Calendar, days::Int)
    new_date = Dates.DateTime(calendar.year, calendar.month, calendar.day) + Dates.Day(days)
    Calendar(Dates.year(new_date), Dates.month(new_date), Dates.day(new_date))
end

# Function to subtract days from the calendar
function subtract_days(calendar::Calendar, days::Int)
    new_date = Dates.DateTime(calendar.year, calendar.month, calendar.day) - Dates.Day(days)
    Calendar(Dates.year(new_date), Dates.month(new_date), Dates.day(new_date))
end

# Function to check if a year is a leap year
function is_leap_year(year::Int)
    Dates.isleapyear(year)
end

# Function to get the number of days in a month
function days_in_month(year::Int, month::Int)
    Dates.daysinmonth(year, month)
end

# Function to check if a date is valid
function is_valid_date(calendar::Calendar)
    Dates.isvaliddate(calendar.year, calendar.month, calendar.day)
end

# Function to display the calendar as a string
function Base.show(io::IO, calendar::Calendar)
    print(io, "$(calendar.year)-$(calendar.month)-$(calendar.day)")
end

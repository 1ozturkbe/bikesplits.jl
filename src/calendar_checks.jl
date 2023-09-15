# Create a new Calendar instance
my_calendar = Calendar(2023, 7, 26)

# Display the current date
println("Current date: ", today())

# Add 10 days to the calendar
new_calendar = add_days(my_calendar, 10)
println("New date after adding 10 days: ", new_calendar)

# Subtract 5 days from the calendar
new_calendar = subtract_days(my_calendar, 5)
println("New date after subtracting 5 days: ", new_calendar)

# Check if the year is a leap year
println("Is 2024 a leap year? ", is_leap_year(2024))

# Get the number of days in a specific month
println("Number of days in February 2023: ", days_in_month(2023, 2))

# Check if the current date is valid
println("Is today a valid date? ", is_valid_date(today()))

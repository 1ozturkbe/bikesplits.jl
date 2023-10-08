using HTTP
using JSON

# Set your Google Calendar API credentials and endpoint
credentials_file = "your-credentials-file.json"  # Replace with your credentials file
calendar_id = "your-calendar-id@group.calendar.google.com"  # Replace with your calendar ID

# Load credentials JSON
credentials_json = JSON.parsefile(credentials_file)

# Generate an access token
response = HTTP.post("https://accounts.google.com/o/oauth2/token",
    query = [
        "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion" => credentials_json["private_key"]
    ]
)

token_data = JSON.parse(String(response.body))

# Create a new event
event_data = [
    "summary" => "Event 1",
    "start" => [
        "date" => "2023-09-25",
        "timeZone" => "Your_Timezone_Here"
    ],
    "end" => [
        "date" => "2023-09-26",
        "timeZone" => "Your_Timezone_Here"
    ]
]

response = HTTP.post("https://www.googleapis.com/calendar/v3/calendars/$calendar_id/events",
    headers = ["Authorization" => "Bearer $(token_data["access_token"])"],
    json = event_data
)

if response.status == 200
    println("Event created successfully!")
else
    println("Error creating event: $(String(response.body))")
end
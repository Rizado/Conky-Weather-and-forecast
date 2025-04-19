#!/bin/bash

# get_weather.sh v1.7
# by @wim66
# April 17 2025

# Cache settings
CACHE_TIMEOUT=900  # Seconds (900 = 15 minutes)

# Determine script path and directories
SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)
CACHE_DIR="$SCRIPT_DIR/cache"
WEATHER_DATA="$CACHE_DIR/weather_data.txt"
FORECAST_DATA="$CACHE_DIR/forecast_data.txt"

# Ensure cache directory exists
mkdir -p "$CACHE_DIR"

# Check if cache is still valid
if [ -f "$WEATHER_DATA" ]; then
    CURRENT_TIME=$(date +%s)
    FILE_TIME=$(stat -c %Y "$WEATHER_DATA" 2>/dev/null || date -r "$WEATHER_DATA" +%s 2>/dev/null)
    AGE=$((CURRENT_TIME - FILE_TIME))

    if [ "$AGE" -lt "$CACHE_TIMEOUT" ]; then
        ((AGE /= 60))  # Divide AGE by 60 and store result
        echo "Last update:${AGE}m ago" > $CACHE_DIR/last-update.txt # Print age in minutes
        exit 0
    fi
fi

# Load API configuration from settings.lua
ICON_SET=$(lua -e 'require("settings"); conky_vars(); print(ICON_SET)')
API_KEY=$(lua -e 'require("settings"); conky_vars(); print(API_KEY)')
CITY_ID=$(lua -e 'require("settings"); conky_vars(); print(CITY_ID)')
UNITS=$(lua -e 'require("settings"); conky_vars(); print(UNITS)')
LANG=$(lua -e 'require("settings"); conky_vars(); print(LANG)')

# Validate API configuration
if [ -z "$API_KEY" ] || [ -z "$CITY_ID" ] || [ -z "$UNITS" ] || [ -z "$LANG" ]; then
    echo "Error: Een of meer API-configuratievariabelen ontbreken." >&2
    exit 1
fi

# Split ICON_SET into theme and set name, construct full path
IFS='-' read -r THEME SET_NAME <<< "$ICON_SET"
ICON_DIR="$SCRIPT_DIR/weather-icons/$(echo "$THEME" | tr '[:upper:]' '[:lower:]')/$SET_NAME"

# Fetch current weather data
WEATHER_RESPONSE=$(curl -s "http://api.openweathermap.org/data/2.5/weather?id=$CITY_ID&appid=$API_KEY&units=$UNITS&lang=$LANG")

# Fetch 5 day / 3 hour forecast data
FORECAST_RESPONSE=$(curl -s "http://api.openweathermap.org/data/2.5/forecast?id=$CITY_ID&appid=$API_KEY&units=$UNITS&lang=$LANG")

# Check if current weather data request was successful
if ! echo "$WEATHER_RESPONSE" | jq -e '.cod // 0' | grep -qE '2[0-9][0-9]'; then
    echo "Error: Unable to fetch current weather data. Controleer API-sleutel of netwerkverbinding." >&2
    echo "$WEATHER_RESPONSE" >> "$CACHE_DIR/error.log"
    exit 1
fi

# Check if forecast data request was successful
if ! echo "$FORECAST_RESPONSE" | jq -e '.cod // 0' | grep -qE '2[0-9][0-9]'; then
    echo "Error: Unable to fetch forecast data. Controleer API-sleutel of netwerkverbinding." >&2
    echo "$FORECAST_RESPONSE" >> "$CACHE_DIR/error.log"
    exit 1
fi

# Function to translate weather descriptions
translate_weather() {
    local desc="$1"
    case "$desc" in
        "zeer lichte bewolking")
            echo "lichte bewolking"  # Translate "very light clouds" to "light clouds"
            ;;
        *)
            echo "$desc"  # Default: return the original description unchanged
            ;;
    esac
}

# Parse JSON response for current weather
CITY=$(echo "$WEATHER_RESPONSE" | jq -r .name)
WEATHER_ICON=$(echo "$WEATHER_RESPONSE" | jq -r '.weather[0].icon')
WEATHER_DESC=$(echo "$WEATHER_RESPONSE" | jq -r '.weather[0].description')
WEATHER_DESC=$(translate_weather "$WEATHER_DESC")
TEMP=$(echo "$WEATHER_RESPONSE" | jq -r '.main.temp')
TEMP_MIN=$(echo "$WEATHER_RESPONSE" | jq -r '.main.temp_min')
TEMP_MAX=$(echo "$WEATHER_RESPONSE" | jq -r '.main.temp_max')
HUMIDITY=$(echo "$WEATHER_RESPONSE" | jq -r '.main.humidity')
WIND_SPEED=$(echo "$WEATHER_RESPONSE" | jq -r '.wind.speed')

# Remove decimal places from temperatures
TEMP=${TEMP%.*}
TEMP_MIN=${TEMP_MIN%.*}
TEMP_MAX=${TEMP_MAX%.*}

# Append temperature unit based on the UNITS setting
if [ "$UNITS" = "metric" ]; then
    TEMP="${TEMP}°C"
    TEMP_MIN="${TEMP_MIN}°C"
    TEMP_MAX="${TEMP_MAX}°C"
elif [ "$UNITS" = "imperial" ]; then
    TEMP="${TEMP}°F"
    TEMP_MIN="${TEMP_MIN}°F"
    TEMP_MAX="${TEMP_MAX}°F"
fi

# Check if the weather icon file exists before copying (for current weather)
ICON_PATH="${ICON_DIR}/${WEATHER_ICON}.png"
if [ -f "$ICON_PATH" ]; then
    cp "$ICON_PATH" "${CACHE_DIR}/weathericon.png"
else
    echo "Warning: Icon $ICON_PATH not found!" >&2
fi

# Write weather data to file
cat <<EOF > "$WEATHER_DATA"
CITY=$CITY
LANG=$LANG
WEATHER_DESC=$WEATHER_DESC
TEMP=$TEMP
TEMP_MIN=$TEMP_MIN
TEMP_MAX=$TEMP_MAX
HUMIDITY=$HUMIDITY
WIND_SPEED=$WIND_SPEED
EOF

# Save forecast data as raw JSON for later processing (e.g. Lua)
echo "$FORECAST_RESPONSE" > "$FORECAST_DATA"
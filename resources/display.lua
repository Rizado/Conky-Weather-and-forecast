-- display.lua – Conky Weather with Cycling Labels and Flip Down Effect
-- by @wim66 – April 17, 2025
-- Forecast functionality moved to forecast.lua for modularity

require 'cairo'

-- Try to require the 'cairo_xlib' module safely
local status, cairo_xlib = pcall(require, 'cairo_xlib')

if not status then
    cairo_xlib = setmetatable({}, {
        __index = function(_, k)
            return _G[k]
        end
    })
end

-- Data fetch settings
local FETCH_INTERVAL = 60 -- Seconds between running get_forecast.sh
local last_fetch_time = 0
local FORCE_FETCH = false
-- Dynamic path
local SCRIPT_DIR = debug.getinfo(1, 'S').source:match[[^@?(.*[\/])[^\/]-$]] or "./resources/"
local FETCH_SCRIPT = SCRIPT_DIR .. "get_weather.sh"

-- Determine script directory
local script_dir = "./resources"

-- Global variables for label cycling and animation
local frame_count = 0
local label_cycle_frames = 10
local current_label_index = 1
local is_animating = false
local animation_frame = 0
local animation_duration = 3
local previous_label_index = 1

-- Function to load weather data from a file
local function read_weather_data()
    local weather_data = {}
    local file_path = script_dir .. "/cache/weather_data.txt"
    local file = io.open(file_path, "r")
    if not file then
        return {CITY = "N/A", LANG = "en", WEATHER_DESC = "N/A", ICON_SET = "default"}
    end
    for line in file:lines() do
        local key, value = line:match("([^=]+)=([^=]+)")
        if key and value then
            weather_data[key] = value
        end
    end
    file:close()
    return weather_data
end

-- Function to get the last modified time of weather_data.txt
local function get_last_update_time(lang)
    local file_path = script_dir .. "/cache/weather_data.txt"
    local cmd = "stat -c %Y " .. file_path .. " 2>/dev/null || echo 0"
    local handle = io.popen(cmd)
    local timestamp = handle:read("*all")
    handle:close()
    timestamp = tonumber(timestamp) or 0
    if timestamp == 0 then
        return "N/A"
    end
    local current_time = os.time()
    local seconds_ago = current_time - timestamp
    local translations = {
        nl = { just_now = "zojuist", minute = "minuut", minutes = "minuten", hour = "uur", hours = "uren", ago = "geleden" },
        en = { just_now = "just now", minute = "minute", minutes = "minutes", hour = "hour", hours = "hours", ago = "ago" },
        fr = { just_now = "à l'instant", minute = "minute", minutes = "minutes", hour = "heure", hours = "heures", ago = "il y a" },
        es = { just_now = "ahora mismo", minute = "minuto", minutes = "minutos", hour = "hora", hours = "horas", ago = "hace" },
        de = { just_now = "gerade eben", minute = "Minute", minutes = "Minuten", hour = "Stunde", hours = "Stunden", ago = "vor" }
    }
    local t = translations[lang] or translations.en
    if seconds_ago < 60 then
        return t.just_now
    elseif seconds_ago < 3600 then
        local minutes = math.floor(seconds_ago / 60)
        return minutes .. " " .. (minutes == 1 and t.minute or t.minutes) .. " " .. t.ago
    else
        local hours = math.floor(seconds_ago / 3600)
        return hours .. " " .. (hours == 1 and t.hour or t.hours) .. " " .. t.ago
    end
end

-- Function to get translated "Last Update" text
local function get_last_update_label(lang)
    local translations = {
        nl = "Laatste update",
        en = "Last Update",
        fr = "Dernière mise à jour",
        es = "Última actualización",
        de = "Letzte Aktualisierung"
    }
    return translations[lang] or translations.en
end

-- Language-based label translations and data pairs, with Min and Max combined
local function get_label_pairs(lang, weather_data)
    local labels = {}
    if lang == "nl" then
        labels = {
            {text = "Temp: " .. (weather_data.TEMP or "N/A")},
            {text = "Min: " .. (weather_data.TEMP_MIN or "N/A") .. " Max: " .. (weather_data.TEMP_MAX or "N/A")},
            {text = "Luchtvochtigheid: " .. (weather_data.HUMIDITY or "N/A") .. "%"},
            {text = "Wind snelheid: " .. (weather_data.WIND_SPEED or "N/A") .. " m/s"}
        }
    elseif lang == "en" then
        labels = {
            {text = "Temp: " .. (weather_data.TEMP or "N/A")},
            {text = "Min: " .. (weather_data.TEMP_MIN or "N/A") .. " Max: " .. (weather_data.TEMP_MAX or "N/A")},
            {text = "Humidity: " .. (weather_data.HUMIDITY or "N/A") .. "%"},
            {text = "Wind Speed: " .. (weather_data.WIND_SPEED or "N/A") .. " m/s"}
        }
    elseif lang == "fr" then
        labels = {
            {text = "Temp: " .. (weather_data.TEMP or "N/A")},
            {text = "Min: " .. (weather_data.TEMP_MIN or "N/A") .. " Max: " .. (weather_data.TEMP_MAX or "N/A")},
            {text = "Humidité: " .. (weather_data.HUMIDITY or "N/A") .. "%"},
            {text = "Vitesse du vent: " .. (weather_data.WIND_SPEED or "N/A") .. " m/s"}
        }
    elseif lang == "es" then
        labels = {
            {text = "Temp: " .. (weather_data.TEMP or "N/A")},
            {text = "Min: " .. (weather_data.TEMP_MIN or "N/A") .. " Max: " .. (weather_data.TEMP_MAX or "N/A")},
            {text = "Humedad: " .. (weather_data.HUMIDITY or "N/A") .. "%"},
            {text = "Velocidad del viento: " .. (weather_data.WIND_SPEED or "N/A") .. " m/s"}
        }
    elseif lang == "de" then
        labels = {
            {text = "Temp: " .. (weather_data.TEMP or "N/A")},
            {text = "Min: " .. (weather_data.TEMP_MIN or "N/A") .. " Max: " .. (weather_data.TEMP_MAX or "N/A")},
            {text = "Luftfeuchtigkeit: " .. (weather_data.HUMIDITY or "N/A") .. "%"},
            {text = "Windgeschwindigkeit: " .. (weather_data.WIND_SPEED or "N/A") .. " m/s"}
        }
    else
        labels = {
            {text = "Temp: " .. (weather_data.TEMP or "N/A")},
            {text = "Min: " .. (weather_data.TEMP_MIN or "N/A") .. " Max: " .. (weather_data.TEMP_MAX or "N/A")},
            {text = "Humidity: " .. (weather_data.HUMIDITY or "N/A") .. "%"},
            {text = "Wind Speed: " .. (weather_data.WIND_SPEED or "N/A") .. " m/s"}
        }
    end
    return labels
end

-- Function to calculate text width for centering
local function get_text_width(cr, text, font, size)
    cairo_select_font_face(cr, font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    local extents = cairo_text_extents_t:create()
    cairo_text_extents(cr, text, extents)
    return extents.width
end

-- Function to draw text with specified properties
local function draw_text(cr, text, x, y, font, size, color, alpha)
    cairo_select_font_face(cr, font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    cairo_set_source_rgba(cr, color[1], color[2], color[3], alpha or color[4])
    cairo_move_to(cr, x, y)
    cairo_show_text(cr, text)
end

-- Function to draw an image with specified size
local function draw_image(cr, path, x, y, width, height)
    local image = cairo_image_surface_create_from_png(path)
    if cairo_surface_status(image) == CAIRO_STATUS_SUCCESS then
        cairo_save(cr)
        cairo_translate(cr, x, y)
        cairo_scale(cr, width / cairo_image_surface_get_width(image), height / cairo_image_surface_get_height(image))
        cairo_set_source_surface(cr, image, 0, 0)
        cairo_paint(cr)
        cairo_restore(cr)
        cairo_surface_destroy(image)
    end
end

-- Main function to draw the weather display
function conky_draw_weather()
    if conky_window == nil then return end

    -- Run initial fetch at startup
    if last_fetch_time == 0 then
        local cmd = FETCH_SCRIPT
        if FORCE_FETCH then
            cmd = cmd .. " --force"
        end
        io.popen(cmd .. " 2>&1"):close()
    end

    -- Check if it's time to fetch new data
    local current_time = os.time()
    if current_time - last_fetch_time >= FETCH_INTERVAL then
        local cmd = FETCH_SCRIPT
        if FORCE_FETCH then
            cmd = cmd .. " --force"
        end
        local handle = io.popen(cmd .. " 2>&1")
        local output = handle:read("*all")
        handle:close()
        last_fetch_time = current_time
    end

    -- Load weather data
    local weather_data = read_weather_data()
    local city = weather_data.CITY or "Unknown"
    local lang = weather_data.LANG or "en"
    local weather_desc = weather_data.WEATHER_DESC or "No description"
    local icon_set = weather_data.ICON_SET or "default"

    -- Get label-value pairs for cycling
    local label_pairs = get_label_pairs(lang, weather_data)

    -- Create Cairo surface and context
    local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable, conky_window.visual,
                                         conky_window.width, conky_window.height)
    local cr = cairo_create(cs)

    -- Draw weather icon based on ICON_SET
    local weather_icon_path = script_dir .. "/cache/weathericon.png"
    if icon_set == "Light-vclouds" then
        draw_image(cr, weather_icon_path, 0, 0, 150, 150)
    else
        draw_image(cr, weather_icon_path, 10, 10, 120, 120)
    end

    -- Draw centered city name
    local city_font = "ChopinScript"
    local city_size = 72
    local city_color = {1, 0.4, 0, 1}
    local city_width = get_text_width(cr, city, city_font, city_size)
    local city_x = (conky_window.width - city_width) / 2
    draw_text(cr, city, city_x + 20, 90, city_font, city_size, city_color)

    -- Draw centered weather description
    local desc_font = "Dejavu Serif"
    local desc_size = 22
    local desc_color = {1, 0.66, 0, 1}
    local desc_width = get_text_width(cr, weather_desc, desc_font, desc_size)
    local desc_x = (conky_window.width - desc_width) / 2
    draw_text(cr, weather_desc, desc_x, conky_window.height - 134, desc_font, desc_size, desc_color)

    -- Draw last update time
    local last_update_label = get_last_update_label(lang)
    local last_update_time = get_last_update_time(lang)
    local last_update_text = last_update_label .. ": " .. last_update_time
    local last_update_font = "Dejavu Serif"
    local last_update_size = 12
    local last_update_color = {1, 0.66, 0, 1}
    local last_update_width = get_text_width(cr, last_update_text, last_update_font, last_update_size)
    local last_update_x = conky_window.width - last_update_width - 35
    draw_text(cr, last_update_text, last_update_x, 25, last_update_font, last_update_size, last_update_color)

    -- Draw 5-day forecast from forecast.lua, centered over Conky width
    local forecast = require(script_dir .. "/forecast")
    local forecast_width = 360 -- 5 icons (40px) + 4 gaps (40px)
    local forecast_x = (conky_window.width - forecast_width) / 2
    forecast.draw_forecast_block(cr, forecast_x, conky_window.height - 70)

    -- Label cycling and animation logic
    frame_count = frame_count + 1

    if frame_count >= label_cycle_frames and not is_animating then
        previous_label_index = current_label_index
        current_label_index = current_label_index + 1
        if current_label_index > #label_pairs then
            current_label_index = 1
        end
        is_animating = true
        animation_frame = 0
        frame_count = 0
    end

    -- Get current and previous label texts
    local current_text = label_pairs[current_label_index].text
    local previous_text = label_pairs[previous_label_index].text

    -- Draw labels with flip down effect
    local label_font = "Dejavu Serif"
    local label_size = 22
    local label_color = {1, 0.66, 0, 1}
    local label_y_base = conky_window.height - 105

    if is_animating then
        animation_frame = animation_frame + 1
        local progress = animation_frame / animation_duration
        local old_y = label_y_base + (progress * 30)
        local new_y = (label_y_base - 30) + (progress * 30)

        local old_width = get_text_width(cr, previous_text, label_font, label_size)
        local old_x = (conky_window.width - old_width) / 2
        draw_text(cr, previous_text, old_x, old_y, label_font, label_size, label_color, 1 - progress)

        local new_width = get_text_width(cr, current_text, label_font, label_size)
        local new_x = (conky_window.width - new_width) / 2
        draw_text(cr, current_text, new_x, new_y, label_font, label_size, label_color, progress)

        if animation_frame >= animation_duration then
            is_animating = false
        end
    else
        local label_width = get_text_width(cr, current_text, label_font, label_size)
        local label_x = (conky_window.width - label_width) / 2
        draw_text(cr, current_text, label_x, label_y_base, label_font, label_size, label_color)
    end

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end

-- Entry point for Conky
function conky_main()
    conky_draw_weather()
end
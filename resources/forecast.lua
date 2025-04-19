-- forecast.lua – 5-Day Weather Forecast Block for Conky
-- by @wim66 – April 17, 2025
-- Draws a modular forecast block at specified x, y coordinates
-- Updated to add configurable debug logging

package.path = package.path .. ";./resources/?.lua"
local json = require("dkjson")
require 'cairo'

-- Debug logging configuration
local Debug_log = false -- Set to false to disable debug logging

-- Helper function to write to debug log if enabled
local function write_log(message)
    if Debug_log then
        local log = io.open("conky_debug.log", "a")
        if log then
            log:write(message)
            log:close()
        end
    end
end

-- Get script directory
local script_path = debug.getinfo(1, 'S').source:match[[^@?(.*[\/])[^\/]-$]] or "./resources/"
local parent_path = script_path:match("^(.*[\\/])resources[\\/].*$") or ""
package.path = package.path .. ";" .. parent_path .. "?.lua"

-- Load settings.lua
local status, err = pcall(function() require("settings") end)
if not status then
    write_log("Error loading settings.lua: " .. tostring(err) .. "\n")
    error("Kan settings.lua niet laden: " .. err)
end
if not conky_vars then
    write_log("conky_vars function is not defined in settings.lua\n")
    error("conky_vars functie niet gedefinieerd in settings.lua")
end
conky_vars()

-- Log loaded settings
write_log("settings.lua geladen: ICON_SET=" .. tostring(ICON_SET) ..
          ", LANG=" .. tostring(LANG) ..
          ", UNITS=" .. tostring(UNITS) .. "\n")

-- Positioning and fetch settings
local POSITION = {
    x = 0, y = 25,
    center_x = true,
    center_y = false
}
local BLOCK_WIDTH = 360
local BLOCK_HEIGHT = 58
local FETCH_INTERVAL = 300
local last_fetch_time = 0
local FORCE_FETCH = false
local last_icon_log_time = 0

-- Default fallback values
local ICON_SET = ICON_SET or "Dark-modern"
local LANG = LANG or "en"
local UNITS = UNITS or "metric"
local TEMP_SUFFIX = (UNITS == "imperial") and "°F" or "°C"

-- Determine theme and clean ICON_SET
local theme = ICON_SET:match("^Dark%-") and "dark" or ICON_SET:match("^Light%-") and "light" or "dark"
local ICON_SET_CLEAN = ICON_SET:gsub("^Dark%-", ""):gsub("^Light%-", "")

-- Validate ICON_SET_CLEAN
local valid_icon_sets = { "dovora", "modern", "monochrome", "openweathermap", "SagiSan", "spils-icons", "vclouds" }
local is_valid = false
for _, set in ipairs(valid_icon_sets) do
    if ICON_SET_CLEAN == set then
        is_valid = true
        break
    end
end
if not is_valid then
    write_log("Ongeldige ICON_SET: " .. tostring(ICON_SET) .. ", fallback naar Dark-modern\n")
    theme = "dark"
    ICON_SET_CLEAN = "modern"
end

-- Translations for abbreviated day names
local DAY_ABBR = {
    en = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"},
    nl = {"Zo", "Ma", "Di", "Wo", "Do", "Vr", "Za"},
    fr = {"Dim", "Lun", "Mar", "Mer", "Jeu", "Ven", "Sam"},
    de = {"So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"},
    es = {"Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"}
}

-- Read and parse forecast_data.txt
local function read_forecast_data()
    local file_path = script_path .. "/cache/forecast_data.txt"
    local file = io.open(file_path, "r")
    if not file then
        write_log("Fout: Kan " .. file_path .. " niet openen\n")
        return {}
    end
    local content = file:read("*all")
    file:close()
    if not content or content == "" then
        write_log("Fout: forecast_data.txt is leeg\n")
        return {}
    end
    if not json then
        write_log("Fout: JSON module niet beschikbaar\n")
        return {}
    end
    local forecast, _, err = json.decode(content)
    if err then
        write_log("Fout bij JSON decoding: " .. tostring(err) .. "\n")
        return {}
    end
    if not forecast or not forecast.list then
        write_log("Fout: Geen geldige forecast data in JSON\n")
        return {}
    end

    local daily_forecasts = {}
    local added_days = {}
    local city_timezone = forecast.city and forecast.city.timezone or 0
    local city_name = forecast.city and forecast.city.name or "Onbekend"

    for _, entry in ipairs(forecast.list) do
        local dt_txt = entry.dt_txt
        local day = dt_txt:sub(1, 10)
        local hour = dt_txt:sub(12, 13)
        if hour == "12" and not added_days[day] then
            local icon = entry.weather and entry.weather[1] and entry.weather[1].icon or "01d"
            local temp = entry.main and entry.main.temp and math.floor(entry.main.temp + 0.5) or 0
            local sunrise = entry.sys and entry.sys.sunrise or (forecast.city and forecast.city.sunrise) or 0
            local sunset = entry.sys and entry.sys.sunset or (forecast.city and forecast.city.sunset) or 0
            local y, m, d = day:match("(%d+)%-(%d+)%-(%d+)")
            if y then
                local sunrise_table = os.date("*t", sunrise)
                sunrise_table.year, sunrise_table.month, sunrise_table.day = tonumber(y), tonumber(m), tonumber(d)
                local sunset_table = os.date("*t", sunset)
                sunset_table.year, sunset_table.month, sunrise_table.day = tonumber(y), tonumber(m), tonumber(d)
                sunrise = os.time(sunrise_table)
                sunset = os.time(sunset_table)
            end
            table.insert(daily_forecasts, {
                date = day,
                icon = icon,
                temp = temp,
                sunrise = sunrise,
                sunset = sunset,
                timezone = city_timezone
            })
            added_days[day] = true
        end
        if #daily_forecasts >= 5 then break end
    end
    if #daily_forecasts == 0 then
        write_log("Fout: Geen forecast entries voor 12:00 gevonden\n")
    end
    return daily_forecasts
end

-- Determine whether it's currently day or night
local function is_daytime(sunrise_ts, sunset_ts, city_timezone)
    local now = os.time()
    if not sunrise_ts or not sunset_ts or sunrise_ts == 0 or sunset_ts == 0 or not city_timezone then
        local now_table = os.date("*t")
        local fallback_sunrise = os.time({year=now_table.year, month=now_table.month, day=now_table.day, hour=6, min=0, sec=0})
        local fallback_sunset = os.time({year=now_table.year, month=now_table.month, day=now_table.day, hour=18, min=0, sec=0})
        write_log("is_daytime: Fallback gebruikt: Nu=" .. os.date("%Y-%m-%d %H:%M:%S", now) ..
                  ", Zonsopgang=" .. os.date("%Y-%m-%d %H:%M:%S", fallback_sunrise) ..
                  ", Zonsondergang=" .. os.date("%Y-%m-%d %H:%M:%S", fallback_sunset) .. "\n")
        return now >= fallback_sunrise and now < fallback_sunset
    end
    local local_now = now + city_timezone
    local sunrise_local = sunrise_ts + city_timezone
    local sunset_local = sunset_ts + city_timezone
    local now_hms = tonumber(os.date("%H", local_now)) * 3600 + 
                    tonumber(os.date("%M", local_now)) * 60 + 
                    tonumber(os.date("%S", local_now))
    local sunrise_hms = tonumber(os.date("%H", sunrise_local)) * 3600 + 
                        tonumber(os.date("%M", sunrise_local)) * 60 + 
                        tonumber(os.date("%S", sunrise_local))
    local sunset_hms = tonumber(os.date("%H", sunset_local)) * 3600 + 
                       tonumber(os.date("%M", sunset_local)) * 60 + 
                       tonumber(os.date("%S", sunset_local))
    local is_day = now_hms >= sunrise_hms and now_hms < sunset_hms
    if not is_day then
        write_log("is_daytime: Lokale tijd=" .. os.date("%Y-%m-%d %H:%M:%S", local_now) ..
                  ", Zonsopgang=" .. os.date("%Y-%m-%d %H:%M:%S", sunrise_local) ..
                  ", Zonsondergang=" .. os.date("%Y-%m-%d %H:%M:%S", sunset_local) ..
                  ", TZ_offset=" .. tostring(city_timezone/3600) .. " uur" ..
                  ", Is_dag=" .. tostring(is_day) .. "\n")
    end
    return is_day
end

-- Get translated day abbreviation
local function get_day_abbr(date_str)
    local y, m, d = date_str:match("(%d+)%-(%d+)%-(%d+)")
    if not y then
        write_log("Fout: Ongeldige datumstring: " .. tostring(date_str) .. "\n")
        return "N/A"
    end
    local timestamp = os.time({year = y, month = m, day = d})
    local weekday = tonumber(os.date("%w", timestamp)) + 1
    local abbr = (DAY_ABBR[LANG] or DAY_ABBR["en"])[weekday] or "N/A"
    write_log("get_day_abbr: Date=" .. date_str .. ", LANG=" .. tostring(LANG) .. ", Abbr=" .. abbr .. "\n")
    return abbr
end

-- Get text width
local function get_text_width(cr, text, font, size)
    cairo_select_font_face(cr, font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    local extents = cairo_text_extents_t:create()
    cairo_text_extents(cr, text, extents)
    return extents.width
end

-- Draw text
local function draw_text(cr, text, x, y, font, size, color, alpha)
    cairo_select_font_face(cr, font, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    cairo_set_source_rgba(cr, color[1], color[2], color[3], alpha or color[4])
    cairo_move_to(cr, x, y)
    cairo_show_text(cr, text)
end

-- Draw PNG image
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
    else
        write_log("Fout: Kan afbeelding niet laden: " .. path .. "\n")
    end
end

-- Draw forecast block
function draw_forecast_block(cr, x, y)
    local forecast = read_forecast_data()
    if #forecast == 0 then
        draw_text(cr, "Geen voorspelling beschikbaar", x, y + 20, "Dejavu Serif", 14, {1, 1, 1, 1})
        return
    end

    local spacing = 80
    local icon_height = 40
    local y_icon = y
    local y_day = y - 3
    local y_temp = y + icon_height + 15

    for i, f in ipairs(forecast) do
        local x_offset = x + (i - 1) * spacing
        local icon_base = f.icon:sub(1, 2)
        local suffix = "d"
        if DAY_NIGHT then
            suffix = is_daytime(f.sunrise, f.sunset, f.timezone) and "d" or "n"
        end
        local icon_path = string.format("%s/weather-icons/%s/%s/%s%s.png", script_path, theme, ICON_SET_CLEAN, icon_base, suffix)
        write_log(string.format("Dag %d: DAY_NIGHT=%s, Icoon: %s\n", i, tostring(DAY_NIGHT), icon_path))
        local day = get_day_abbr(f.date)
        local temp = string.format("%d%s", f.temp, TEMP_SUFFIX)

        draw_image(cr, icon_path, x_offset, y_icon, 40, 40)
        draw_text(cr, day, x_offset + 12, y_day, "Dejavu Serif", 14, {1, 1, 1, 1})
        draw_text(cr, temp, x_offset + 4, y_temp, "Dejavu Serif", 14, {1, 1, 1, 1})
    end
end

-- Main Conky function
function conky_draw_forecast()
    if conky_window == nil then return end

    if last_fetch_time == 0 then
        local cmd = script_path .. "get_weather.sh"
        io.popen(cmd .. " 2>&1"):close()
    end

    local current_time = os.time()
    if current_time - last_fetch_time >= FETCH_INTERVAL then
        local cmd = script_path .. "get_weather.sh"
        local handle = io.popen(cmd .. " 2>&1")
        handle:read("*all")
        handle:close()
        last_fetch_time = current_time
    end

    local cs = cairo_create_surface(conky_window.display, conky_window.drawable, conky_window.visual,
                                    conky_window.width, conky_window.height)
    local cr = cairo_create(cs)

    local x = POSITION.center_x and math.max(0, (conky_window.width - BLOCK_WIDTH) / 2) or POSITION.x
    local y = POSITION.center_y and math.max(0, (conky_window.height - BLOCK_HEIGHT) / 2) or POSITION.y

    draw_forecast_block(cr, x, y)

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end

-- Return module for requiring
return {
    draw_forecast_block = draw_forecast_block
}
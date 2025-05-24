-- background.lua
-- by @wim66
-- April 17 2025

-- Required Cairo Modules
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

-- Load settings.lua from parent directory
local script_path = debug.getinfo(1, 'S').source:match[[^@?(.*[\/])[^\/]-$]]
local parent_path = script_path:match("^(.*[\\/])resources[\\/].*$") or ""
package.path = package.path .. ";" .. parent_path .. "?.lua"

local status, err = pcall(function() require("settings") end)
if not status then print("Error loading settings.lua: " .. err); return end
if not conky_vars then print("conky_vars function is not defined in settings.lua"); return end
conky_vars()

-- Utility
local unpack = table.unpack or unpack  -- Compatibility for Lua 5.1 and newer

-- Parse a border color string like "0,0xRRGGBB,alpha,..." into a gradient table
local function parse_border_color(border_color_str)
    local gradient = {}
    for position, color, alpha in border_color_str:gmatch("([%d%.]+),0x(%x+),([%d%.]+)") do
        table.insert(gradient, {tonumber(position), tonumber(color, 16), tonumber(alpha)})
    end
    -- Return a default gradient if parsing fails
    if #gradient == 3 then
        return gradient
    end
    return { {0, 0x003E00, 1}, {0.5, 0x03F404, 1}, {1, 0x003E00, 1} }
end

-- Parse a background color string like "0xRRGGBB,alpha" into a table
local function parse_bg_color(bg_color_str)
    local hex, alpha = bg_color_str:match("0x(%x+),([%d%.]+)")
    if hex and alpha then
        return { {1, tonumber(hex, 16), tonumber(alpha)} }
    end
    -- Fallback to solid black if parsing fails
    return { {1, 0x000000, 1} }
end

-- Read color values from settings.lua variables
local border_color = parse_border_color(border_COLOR)
local bg_color = parse_bg_color(bg_COLOR)

-- All drawable elements
local boxes_settings_day = {
    -- Background
    {
        type = "background",
        x = 2, y = 7, w = 516, h = 256,
        centre_x = false,
        corners = {20, 20, 20, 20},
        draw_me = true,
        colour = bg_color
    },
    -- Second background layer with linear gradient
    {
        type = "layer2",
        x = 2, y = 7, w = 516, h = 256,
        centre_x = false,
        corners = {20, 20, 20, 20},
        draw_me = true,
        linear_gradient = {0, 0, 0, 260},
        colours = { {0, 0x0000ff, 0.5}, {0.6, 0x0000ff, 0.5}, {0.8, 0x008000, 0.5}, {1, 0x008000, 0.5} }
    },
    -- Border
    {
        type = "border",
        x = 0, y = 5, w = 520, h = 260,
        centre_x = false,
        corners = {20, 20, 20, 20},
        draw_me = true,
        border = 8,
        colour = border_color,
        linear_gradient = {0, 130, 520,130}
    }
}

local boxes_settings_night = {
    -- Background (dark theme)
    {
        type = "background",
        x = 2, y = 7, w = 516, h = 256,
        centre_x = false,
        corners = {20, 20, 20, 20},
        draw_me = true,
        colour = parse_bg_color("0x1C2526,0.9") -- Dark grey-blue background
    },
    -- Second background layer with linear gradient
    {
        type = "layer2",
        x = 2, y = 7, w = 516, h = 256,
        centre_x = false,
        corners = {20, 20, 20, 20},
        draw_me = true,
        linear_gradient = {0, 0, 0, 260},
        colours = { {0, 0x0000ff, 0.5}, {0.6, 0x0000ff, 0.5}, {0.8, 0xff00ff, 0.5}, {1, 0xff00ff, 0.5} } -- Dark gradient
    },
    -- Border
    {
        type = "border",
        x = 0, y = 5, w = 520, h = 260,
        centre_x = false,
        corners = {20, 20, 20, 20},
        draw_me = true,
        border = 8,
        colour = parse_border_color("0,0x0000ff,1, 0.5,0x55aaff,1, 1,0x0000ff,1"), -- Blue gradient border
        linear_gradient = {0, 130, 520,130}
    }
}

-- Function to get sunrise and sunset times
local function get_sun_times()
    -- Path to weather_data.txt, relative to parent_path (Conky directory)
    local file_path = parent_path .. "/resources/cache/weather_data.txt"
    local file
    -- Try multiple times if the file is not immediately available
    for i = 1, 3 do
        file = io.open(file_path, "r")
        if file then break end
        os.execute("sleep 1")
    end
    if not file then
        return 6 * 60, 18 * 60, 0 -- Fallback timezone: UTC
    end

    -- Read the file and search for JSON section
    local content = file:read("*all")
    file:close()

    -- Extract sunrise, sunset, timezone, and dt (last update)
    local sunrise = content:match('"sunrise":(%d+)')
    local sunset = content:match('"sunset":(%d+)')
    local timezone = content:match('"timezone":(%-?%d+)') or "0" -- Support negative offsets, default UTC
    local dt = content:match('"dt":(%d+)') -- Timestamp of the data

    if not sunrise or not sunset or not dt then
        return 6 * 60, 18 * 60, 0
    end

    -- Check if the data is recent (less than 24 hours old)
    local current_time = os.time()
    local data_age = current_time - tonumber(dt)
    if data_age > 24 * 3600 then
        return 6 * 60, 18 * 60, 0
    end

    -- Convert Unix timestamps to local time (minutes since midnight)
    local tz_offset = tonumber(timezone) -- In seconds
    -- Validate timezone
    if math.abs(tz_offset) > 50400 then
        tz_offset = 0
    end
    -- Treat timestamp as UTC and add only the API timezone offset
    local sunrise_epoch = tonumber(sunrise) + tz_offset
    local sunset_epoch = tonumber(sunset) + tz_offset
    local sunrise_time = os.date("!*t", sunrise_epoch)
    local sunset_time = os.date("!*t", sunset_epoch)

    return sunrise_time.hour * 60 + sunrise_time.min, sunset_time.hour * 60 + sunset_time.min, tz_offset
end

-- Function to choose the appropriate boxes_settings
local function get_boxes_settings()
    -- Check forced mode
    if _G.force_theme and _G.force_theme ~= "" then
        if _G.force_theme == "night" then
            return boxes_settings_night
        elseif _G.force_theme == "day" then
            return boxes_settings_day
        end
    end

    -- Check external file
    local file = io.open(parent_path .. "theme.txt", "r")
    if file then
        local theme = file:read("*all"):lower()
        file:close()
        if theme:match("night") then
            return boxes_settings_night
        elseif theme:match("day") then
            return boxes_settings_day
        end
    end

    -- Based on sunrise and sunset
    local sunrise, sunset, tz_offset = get_sun_times()
    -- Current time in the city's timezone
    local now = os.date("!*t", os.time() + tz_offset)
    local current_min = now.hour * 60 + now.min

    if current_min >= sunrise and current_min < sunset then
        return boxes_settings_day
    else
        return boxes_settings_night
    end
end

-- Helper: Convert hex to RGBA
local function hex_to_rgba(hex, alpha)
    return ((hex >> 16) & 0xFF) / 255, ((hex >> 8) & 0xFF) / 255, (hex & 0xFF) / 255, alpha
end

-- Helper: Draw custom rounded rectangle
local function draw_custom_rounded_rectangle(cr, x, y, w, h, r)
    local tl, tr, br, bl = unpack(r)

    cairo_new_path(cr)
    cairo_move_to(cr, x + tl, y)
    cairo_line_to(cr, x + w - tr, y)
    if tr > 0 then cairo_arc(cr, x + w - tr, y + tr, tr, -math.pi/2, 0) else cairo_line_to(cr, x + w, y) end
    cairo_line_to(cr, x + w, y + h - br)
    if br > 0 then cairo_arc(cr, x + w - br, y + h - br, br, 0, math.pi/2) else cairo_line_to(cr, x + w, y + h) end
    cairo_line_to(cr, x + bl, y + h)
    if bl > 0 then cairo_arc(cr, x + bl, y + h - bl, bl, math.pi/2, math.pi) else cairo_line_to(cr, x, y + h) end
    cairo_line_to(cr, x, y + tl)
    if tl > 0 then cairo_arc(cr, x + tl, y + tl, tl, math.pi, 3*math.pi/2) else cairo_line_to(cr, x, y) end
    cairo_close_path(cr)
end

-- Helper: Center X position
local function get_centered_x(canvas_width, box_width)
    return (canvas_width - box_width) / 2
end

-- Main drawing function
function conky_draw_background()
    if conky_window == nil then return end

    local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable, conky_window.visual, conky_window.width, conky_window.height)
    local cr = cairo_create(cs)
    local canvas_width = conky_window.width

    -- Choose the appropriate boxes_settings
    local boxes_settings = get_boxes_settings()

    for _, box in ipairs(boxes_settings) do
        if box.draw_me then
            local x, y, w, h = box.x, box.y, box.w, box.h
            if box.centre_x then x = get_centered_x(canvas_width, w) end

            if box.type == "background" then
                cairo_set_source_rgba(cr, hex_to_rgba(box.colour[1][2], box.colour[1][3]))
                draw_custom_rounded_rectangle(cr, x, y, w, h, box.corners)
                cairo_fill(cr)

            elseif box.type == "layer2" then
                local grad = cairo_pattern_create_linear(unpack(box.linear_gradient))
                for _, color in ipairs(box.colours) do
                    cairo_pattern_add_color_stop_rgba(grad, color[1], hex_to_rgba(color[2], color[3]))
                end
                cairo_set_source(cr, grad)
                draw_custom_rounded_rectangle(cr, x, y, w, h, box.corners)
                cairo_fill(cr)
                cairo_pattern_destroy(grad)

            elseif box.type == "border" then
                local grad = cairo_pattern_create_linear(unpack(box.linear_gradient))
                for _, color in ipairs(box.colour) do
                    cairo_pattern_add_color_stop_rgba(grad, color[1], hex_to_rgba(color[2], color[3]))
                end
                cairo_set_source(cr, grad)
                cairo_set_line_width(cr, box.border)
                draw_custom_rounded_rectangle(
                    cr,
                    x + box.border / 2,
                    y + box.border / 2,
                    w - box.border,
                    h - box.border,
                    {
                        math.max(0, box.corners[1] - box.border / 2),
                        math.max(0, box.corners[2] - box.border / 2),
                        math.max(0, box.corners[3] - box.border / 2),
                        math.max(0, box.corners[4] - box.border / 2)
                    }
                )
                cairo_stroke(cr)
                cairo_pattern_destroy(grad)
            end
        end
    end

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end
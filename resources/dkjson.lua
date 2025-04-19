-- dkjson.lua (local copy for Lua 5.4+ / Conky)
-- David Kolf’s JSON module (https://dkolf.de/src/dkjson-lua.fsl/)
-- Adapted for embedded usage in Conky
-- Version 2.8

local json = {}

local function unicode_codepoint_as_utf8(codepoint)
  if codepoint <= 0x7f then
    return string.char(codepoint)
  elseif codepoint <= 0x7ff then
    local b1 = 0xc0 + math.floor(codepoint / 0x40)
    local b2 = 0x80 + (codepoint % 0x40)
    return string.char(b1, b2)
  elseif codepoint <= 0xffff then
    local b1 = 0xe0 + math.floor(codepoint / 0x1000)
    local b2 = 0x80 + (math.floor(codepoint / 0x40) % 0x40)
    local b3 = 0x80 + (codepoint % 0x40)
    return string.char(b1, b2, b3)
  elseif codepoint <= 0x10ffff then
    local b1 = 0xf0 + math.floor(codepoint / 0x40000)
    local b2 = 0x80 + (math.floor(codepoint / 0x1000) % 0x40)
    local b3 = 0x80 + (math.floor(codepoint / 0x40) % 0x40)
    local b4 = 0x80 + (codepoint % 0x40)
    return string.char(b1, b2, b3, b4)
  else
    error("invalid Unicode codepoint '" .. codepoint .. "'")
  end
end

local function newdecoder()
  local json_string
  local pos
  local nullv = setmetatable({}, {__tojson = function() return "null" end})

  local function skip_whitespace()
    local _, e = json_string:find("^[ \n\r\t]*", pos)
    pos = (e or pos - 1) + 1
  end

  local function parse_string()
    local i = pos + 1
    local res = ""
    while i <= #json_string do
      local c = json_string:sub(i, i)
      if c == '"' then
        pos = i + 1
        return res
      elseif c == "\\" then
        local next_char = json_string:sub(i+1, i+1)
        if next_char == "u" then
          local hex = json_string:sub(i+2, i+5)
          res = res .. unicode_codepoint_as_utf8(tonumber(hex, 16))
          i = i + 6
        else
          local escapes = { ['"']='"', ['\\']='\\', ['/']='/', ['b']='\b',
                            ['f']='\f', ['n']='\n', ['r']='\r', ['t']='\t' }
          res = res .. (escapes[next_char] or next_char)
          i = i + 2
        end
      else
        res = res .. c
        i = i + 1
      end
    end
    error("unterminated string")
  end

  local function parse_number()
    local s, e = json_string:find('^-?%d+%.?%d*[eE]?[+-]?%d*', pos)
    local num = tonumber(json_string:sub(s, e))
    pos = e + 1
    return num
  end

  local function parse_literal()
    if json_string:sub(pos, pos+3) == "true" then
      pos = pos + 4
      return true
    elseif json_string:sub(pos, pos+4) == "false" then
      pos = pos + 5
      return false
    elseif json_string:sub(pos, pos+3) == "null" then
      pos = pos + 4
      return nullv
    end
  end

  local function parse_array()
    pos = pos + 1
    skip_whitespace()
    local res = {}
    if json_string:sub(pos, pos) == "]" then
      pos = pos + 1
      return res
    end
    while true do
      local val = parse_value()
      res[#res + 1] = val
      skip_whitespace()
      local c = json_string:sub(pos, pos)
      if c == "]" then
        pos = pos + 1
        break
      elseif c ~= "," then
        error("expected ',' or ']'")
      end
      pos = pos + 1
      skip_whitespace()
    end
    return res
  end

  local function parse_object()
    pos = pos + 1
    skip_whitespace()
    local res = {}
    if json_string:sub(pos, pos) == "}" then
      pos = pos + 1
      return res
    end
    while true do
      skip_whitespace()
      local key = parse_string()
      skip_whitespace()
      if json_string:sub(pos, pos) ~= ":" then
        error("expected ':' after key")
      end
      pos = pos + 1
      skip_whitespace()
      res[key] = parse_value()
      skip_whitespace()
      local c = json_string:sub(pos, pos)
      if c == "}" then
        pos = pos + 1
        break
      elseif c ~= "," then
        error("expected ',' or '}'")
      end
      pos = pos + 1
    end
    return res
  end

  function parse_value()
    skip_whitespace()
    local c = json_string:sub(pos, pos)
    if c == '"' then
      return parse_string()
    elseif c == "-" or c:match("%d") then
      return parse_number()
    elseif c == "{" then
      return parse_object()
    elseif c == "[" then
      return parse_array()
    else
      return parse_literal()
    end
  end

  return function(text)
    json_string = text
    pos = 1
    return parse_value()
  end
end

json.decode = newdecoder()

return json

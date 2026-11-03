-- Translation of a Lua pattern to an ECMA-262 regular expression (schemas-and-contracts.md, "The `pattern`
-- option"; OQ-85 point 1). Exact for a defined subset; every other construct is refused, never approximated.
global <const> require, string, table, error, tonumber

local core = require("hecate.core")

local byte, sub, find, format = string.byte, string.sub, string.find, string.format
local concat = table.concat

--- ASCII-pinned bodies of the character classes (the inside of a regex character class).
local CLASS_BODY <const> = {
  a = "A-Za-z",
  c = "\\x00-\\x1F\\x7F",
  d = "0-9",
  g = "\\x21-\\x7E",
  l = "a-z",
  p = "\\x21-\\x2F\\x3A-\\x40\\x5B-\\x60\\x7B-\\x7E",
  s = " \\t\\n\\x0B\\f\\r",
  u = "A-Z",
  w = "A-Za-z0-9",
  x = "A-Fa-f0-9",
}

--- Characters escaped with a backslash outside a character class.
local SYNTAX <const> = "^$\\.*+?()[]{}|/"

---@class hecate.schema.pattern
local M = {}

---@param pattern string
---@param reason string
---@param position integer?
local function refuse(pattern, reason, position)
  error(core.ArgumentError(
    ("schema: the pattern %q cannot be emitted as a JSON Schema pattern: %s"):format(pattern, reason),
    { context = { option = "pattern", pattern = pattern, position = position } }), 3)
end

--- A literal character outside a character class.
---@param c string
---@return string
local function literal(c)
  local b = byte(c)
  if b < 0x20 or b == 0x7F then return format("\\x%02X", b) end
  if find(SYNTAX, c, 1, true) then return "\\" .. c end
  return c
end

--- A literal character inside a character class: everything but letters, digits and `_` as a hex escape.
---@param c string
---@return string
local function set_literal(c)
  if find(c, "^[%w_]$") then return c end
  return format("\\x%02X", byte(c))
end

--- Translates a Lua pattern to an ECMA-262 regular expression.
--- Raises `ArgumentError` for a construct outside the supported subset.
---@param pattern string
---@return string
function M.to_ecma(pattern)
  if find(pattern, "[\128-\255]") then
    refuse(pattern, "only ASCII characters are supported", find(pattern, "[\128-\255]"))
  end
  local n = #pattern
  local out = {}
  local i = 1
  local open, closed = {}, {} -- open capture groups (stack of indexes), and the set of closed ones
  local groups = 0
  if sub(pattern, 1, 1) == "^" then out[1] = "^"; i = 2 end

  --- Reads the set starting at `i` (at `[`); returns the translation and the index after it.
  local function read_set()
    local start = i
    local q = i + 1
    local negated = sub(pattern, q, q) == "^"
    if negated then q = q + 1 end
    local first = q
    -- like Lua's `classEnd`: the first character is always part of the set, even a `]`
    repeat
      if q > n then refuse(pattern, "unfinished set", start) end
      local c = sub(pattern, q, q)
      q = q + 1
      if c == "%" then
        if q > n then refuse(pattern, "unfinished set", start) end
        q = q + 1
      end
    until sub(pattern, q, q) == "]" and q <= n
    local closing = q
    local parts = {}
    local p = first
    while p < closing do
      local c = sub(pattern, p, p)
      if c == "%" then
        local e = sub(pattern, p + 1, p + 1)
        if find(e, "^%a$") then
          local body = CLASS_BODY[e]
          if body == nil then
            refuse(pattern, "a negated class cannot be used inside a set, or the escape is unknown: %" .. e, p)
          end
          parts[#parts + 1] = body
        elseif find(e, "^%d$") then
          refuse(pattern, "a back-reference cannot be used inside a set", p)
        else
          parts[#parts + 1] = set_literal(e)
        end
        p = p + 2
      elseif sub(pattern, p + 1, p + 1) == "-" and p + 2 < closing then
        local hi = sub(pattern, p + 2, p + 2)
        if hi == "%" then refuse(pattern, "an escape cannot end a range", p) end
        if byte(c) > byte(hi) then refuse(pattern, "the range is empty", p) end
        parts[#parts + 1] = set_literal(c) .. "-" .. set_literal(hi)
        p = p + 3
      else
        parts[#parts + 1] = set_literal(c)
        p = p + 1
      end
    end
    i = closing + 1
    return "[" .. (negated and "^" or "") .. concat(parts) .. "]"
  end

  while i <= n do
    local c = sub(pattern, i, i)
    if c == "(" then
      if sub(pattern, i + 1, i + 1) == ")" then refuse(pattern, "a position capture `()`", i) end
      groups = groups + 1
      open[#open + 1] = groups
      out[#out + 1] = "("
      i = i + 1
    elseif c == ")" then
      if #open == 0 then refuse(pattern, "unbalanced `)`", i) end
      closed[open[#open]] = true
      open[#open] = nil
      out[#out + 1] = ")"
      i = i + 1
    elseif c == "$" and i == n then
      out[#out + 1] = "$"
      i = i + 1
    else
      local piece, quantifiable = nil, true
      if c == "%" then
        local e = sub(pattern, i + 1, i + 1)
        if e == "" then refuse(pattern, "the pattern ends with `%`", i) end
        if e == "b" or e == "f" then refuse(pattern, "%" .. e .. " has no exact translation", i) end
        if find(e, "^%d$") then
          local index = tonumber(e)
          if index == 0 or not closed[index] then refuse(pattern, "invalid back-reference %" .. e, i) end
          piece, quantifiable = "(?:\\" .. e .. ")", false
        elseif find(e, "^%a$") then
          local lower = e:lower()
          local body = CLASS_BODY[lower]
          if body == nil then refuse(pattern, "unknown escape %" .. e, i) end
          piece = "[" .. (lower == e and "" or "^") .. body .. "]"
        else
          piece = literal(e)
        end
        i = i + 2
      elseif c == "[" then
        piece = read_set()
      elseif c == "." then
        piece = "[\\s\\S]"
        i = i + 1
      else
        piece = literal(c)
        i = i + 1
      end
      out[#out + 1] = piece
      if quantifiable then
        local q = sub(pattern, i, i)
        if q == "*" or q == "+" or q == "?" then
          out[#out + 1] = q
          i = i + 1
        elseif q == "-" then
          out[#out + 1] = "*?"
          i = i + 1
        end
      end
    end
  end
  if #open > 0 then refuse(pattern, "unfinished capture", n) end
  return concat(out)
end

return M

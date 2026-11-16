-- Strings that match a `pattern` option. The emitted JSON Schema carries the pattern translated to ECMA-262 by
-- `hecate.schema.pattern`, an exact translation of a defined subset (schemas-and-contracts.md, "The `pattern`
-- option"), so this module reads only that subset: anchors, literals (escaped or `\xHH`), classes `[...]` with ranges,
-- `\s` and `\S`, groups, the back-reference `(?:\N)` and the quantifiers `*`, `+`, `?` and `*?`. Only ASCII is produced.
global <const> require, type, ipairs, pairs, error, string, table, tonumber, math

local core = require("hecate.core")

---@class hecate.test.pattern_text
local M = {}

local byte, sub, char = string.byte, string.sub, string.char

local WHITESPACE = { 9, 10, 11, 12, 13, 32 }
local ESCAPES = { t = 9, n = 10, f = 12, r = 13, v = 11 }

local function unreadable(regex, position)
  error(core.ArgumentError(("test.generate: the pattern %q is not in the subset of hecate.schema.pattern (at %d)")
    :format(regex, position)), 0)
end

-- The set of bytes (0 to 127) as a sorted list.
local function listed(set)
  local out = {}
  for b = 0, 127 do if set[b] then out[#out + 1] = b end end
  return out
end

-- Reads one class item at `i`: returns a byte, or a table set (for `\s` and `\S`), and the next index.
local function class_item(regex, i)
  local c = sub(regex, i, i)
  if c ~= "\\" then return byte(c), i + 1 end
  local e = sub(regex, i + 1, i + 1)
  if e == "x" then
    local hex = sub(regex, i + 2, i + 3)
    if not hex:find("^%x%x$") then unreadable(regex, i) end
    return tonumber(hex, 16), i + 4
  elseif e == "s" or e == "S" then
    local set = {}
    for _, b in ipairs(WHITESPACE) do set[b] = true end
    if e == "S" then
      local complement = {}
      for b = 0, 127 do if not set[b] then complement[b] = true end end
      set = complement
    end
    return set, i + 2
  elseif ESCAPES[e] then
    return ESCAPES[e], i + 2
  elseif e == "" then
    unreadable(regex, i)
  end
  return byte(e), i + 2
end

-- Reads a class starting at `[`: returns its bytes and the index after `]`.
local function read_class(regex, i)
  local at = i
  i = i + 1
  local negated = sub(regex, i, i) == "^"
  if negated then i = i + 1 end
  local set = {}
  while true do
    if i > #regex then unreadable(regex, at) end
    if sub(regex, i, i) == "]" then break end
    local low, after = class_item(regex, i)
    if type(low) == "table" then
      for b in pairs(low) do set[b] = true end
      i = after
    elseif sub(regex, after, after) == "-" and sub(regex, after + 1, after + 1) ~= "]" and after + 1 <= #regex then
      local high, past = class_item(regex, after + 1)
      if type(high) ~= "number" or high < low then unreadable(regex, after) end
      for b = low, high do if b < 128 then set[b] = true end end
      i = past
    else
      if low < 128 then set[low] = true end
      i = after
    end
  end
  if negated then
    local complement = {}
    for b = 0, 127 do if not set[b] then complement[b] = true end end
    set = complement
  end
  return listed(set), i + 1
end

--- Parses the regular expression into a tree: a sequence of `{ set, low, high }` (a repeated byte), `{ group, index }`
--- and `{ backref }` nodes.
---@param regex string
---@return table nodes
function M.parse(regex)
  local i, n = 1, #regex
  if sub(regex, 1, 1) == "^" then i = 2 end
  local root = { kind = "sequence" }
  local stack, current, groups = {}, root, 0
  local function push(node) current[#current + 1] = node end
  local function quantified(set, position)
    local q = sub(regex, position, position)
    ---@type integer, integer?, integer
    local low, high, after = 1, 1, position
    if q == "*" then low, high, after = 0, nil, position + 1
      if sub(regex, after, after) == "?" then after = after + 1 end
    elseif q == "+" then low, high, after = 1, nil, position + 1
    elseif q == "?" then low, high, after = 0, 1, position + 1 end
    push({ kind = "bytes", set = set, low = low, high = high })
    return after
  end
  while i <= n do
    local c = sub(regex, i, i)
    if c == "(" then
      if sub(regex, i, i + 3) == "(?:\\" then
        local digits, close = regex:match("^(%d+)()%)", i + 4)
        if not digits then unreadable(regex, i) end
        push({ kind = "backref", index = tonumber(digits) })
        i = close + 1
      elseif sub(regex, i + 1, i + 1) == "?" then
        unreadable(regex, i) -- a group form the translation never emits
      else
        groups = groups + 1
        local group = { kind = "group", index = groups }
        push(group)
        stack[#stack + 1] = current
        current = group
        i = i + 1
      end
    elseif c == ")" then
      if #stack == 0 then unreadable(regex, i) end
      current = stack[#stack]
      stack[#stack] = nil
      i = i + 1
    elseif c == "$" and i == n then
      i = i + 1
    elseif c == "[" then
      local set, after = read_class(regex, i)
      i = quantified(set, after)
    elseif c == "\\" then
      local e = sub(regex, i + 1, i + 1)
      local value
      if e == "x" then
        local hex = sub(regex, i + 2, i + 3)
        if not hex:find("^%x%x$") then unreadable(regex, i) end
        value, i = tonumber(hex, 16), i + 4
      elseif e == "" then
        unreadable(regex, i)
      else
        value, i = byte(e), i + 2
      end
      if value > 127 then unreadable(regex, i) end
      i = quantified({ value }, i)
    else
      if byte(c) > 127 then unreadable(regex, i) end
      i = quantified({ byte(c) }, i + 1)
    end
  end
  if #stack > 0 then unreadable(regex, n) end
  return root
end

-- The bytes to draw from: the printable ones when the set has any, else the whole set.
local function pool(set)
  local printable = {}
  for _, b in ipairs(set) do if b >= 32 and b <= 126 then printable[#printable + 1] = b end end
  return #printable > 0 and printable or set
end

-- `state.length` counts what was produced and `state.limit` stops an attempt that grows without bound (a chain of
-- back-references multiplies the text it repeats).
local function emit(node, between, cap, captured, out, state)
  if node.kind == "bytes" then
    local candidates = pool(node.set)
    if #candidates == 0 then return false end
    local high = node.high or math.max(node.low, cap)
    local count = node.low == high and node.low or between(node.low, high)
    state.length = state.length + count
    if state.length > state.limit then return false end
    for _ = 1, count do out[#out + 1] = char(candidates[between(1, #candidates)]) end
  elseif node.kind == "backref" then
    local text = captured[node.index]
    if text == nil then return false end
    state.length = state.length + #text
    if state.length > state.limit then return false end
    out[#out + 1] = text
  else
    local start = #out
    for _, child in ipairs(node) do
      if not emit(child, between, cap, captured, out, state) then return false end
    end
    if node.kind == "group" then captured[node.index] = table.concat(out, "", start + 1) end
  end
  return true
end

local CAPS = { 0, 2, 3, 4, 6, 10, 16, 24, 40 }

--- The longest string an attempt may build (characters), whatever `maximum` says.
M.MAX_LENGTH = 65536

--- Returns a string that matches `regex` (the ECMA-262 form of a `pattern`) and whose length is between `minimum` and
--- `maximum` (bytes, which are characters here), or nil when no attempt fits the length. `between(low, high)` draws an
--- integer in the closed range from the seeded source.
---
--- Raises `hecate.core.ArgumentError` for a regular expression outside the subset.
---@param regex string
---@param between fun(low: integer, high: integer): integer
---@param minimum? integer
---@param maximum? integer
---@return string? text
function M.generate(regex, between, minimum, maximum)
  local tree = M.parse(regex)
  minimum, maximum = minimum or 0, maximum or math.huge
  local limit = math.min(maximum, M.MAX_LENGTH)
  for attempt = 1, 90 do
    local out = {}
    if emit(tree, between, CAPS[(attempt - 1) % #CAPS + 1], {}, out, { length = 0, limit = limit }) then
      local text = table.concat(out)
      if #text >= minimum and #text <= maximum then return text end
    end
  end
  return nil
end

return M
